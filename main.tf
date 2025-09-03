
# Data source to import existing VPC
data "aws_vpc" "selected" {
  id = var.vpc_id
}

### Start - AWS Neptune Deployment

# IAM Permissions for Loading Data
resource "aws_iam_role" "neptune_loader_role" {
  name = "NeptuneLoadRole-${var.stack_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["rds.amazonaws.com"] }
      Action    = ["sts:AssumeRole"]
    }]
  })
}

resource "aws_iam_role_policy" "neptune_loader_policy" {
  name = "NeptuneLoadPolicy-${var.stack_suffix}"
  role = aws_iam_role.neptune_loader_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.customer_upload_bucket}",
          "arn:aws:s3:::${var.customer_upload_bucket}/*"
        ]
      }
    ]
  })
}

# Security Group for Neptune
resource "aws_security_group" "neptune_sg" {
  name        = "DigitalTwinService-NeptuneSG-${var.stack_suffix}"
  description = "Allow intra-VPC on port 8182"
  vpc_id      = var.vpc_id

  ingress {
    description = "RailNetwork TCP"
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }
  ingress {
    description = "Databricks TCP"
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = ["10.4.0.0/16"] # TODO Retrieve the Databricks VPC CIDR Block dynamically
  }

  ingress {
    description                  = "Development JumpServer"
    from_port                    = 8182
    to_port                      = 8182
    protocol                     = "tcp"
    security_groups              = [ "sg-0727b3125ad1ecc45" ]
    self                         = false
  }

  /* TODO: Via IaC add JumpServer SG */
  # ingress {
  #   description                  = "Neptune TCP from application SG"
  #   from_port                    = 8182
  #   to_port                      = 8182
  #   protocol                     = "tcp"
  #   security_groups              = [ "sg-0727b3125ad1ecc45" ]
  #   self                         = false
  # }

  # this was commented intentionally to bypass DataExchangeService SG since it was not deployed

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "NeptuneSG-${var.stack_suffix}"
  }
}

# Neptune Subnet Group
resource "aws_neptune_subnet_group" "neptune_subnet_group" {
  name        = "neptune-serverless-subnets-${lower(var.stack_suffix)}"
  description = "Private subnets for Neptune Serverless"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "NeptuneSubnetGroup-${var.stack_suffix}"
  }
}

# Neptune Serverless Cluster
resource "aws_neptune_cluster" "neptune_cluster" {
  cluster_identifier                     = "digital-twin-service-neptune-${lower(var.stack_suffix)}"
  engine                                 = "neptune"
  engine_version                         = "1.4.5.0"
  neptune_subnet_group_name              = aws_neptune_subnet_group.neptune_subnet_group.name
  iam_database_authentication_enabled    = false
  vpc_security_group_ids                 = [aws_security_group.neptune_sg.id]

  # TODO: Disable and provide a final_snapshot_identifier when deploying to prod
  skip_final_snapshot = true

  serverless_v2_scaling_configuration {
    min_capacity = 1.0
    max_capacity = 32.0
  }

  iam_roles = [
    aws_iam_role.neptune_loader_role.arn
  ]

  tags = {
    Name = "NeptuneCluster-${var.stack_suffix}"
  }
}

# Neptune Serverless Instance
resource "aws_neptune_cluster_instance" "neptune_instance" {
  identifier         = "digital-twin-service-instance-${lower(var.stack_suffix)}"
  cluster_identifier = aws_neptune_cluster.neptune_cluster.id
  instance_class     = "db.serverless"

  tags = {
    Name = "NeptuneInstance-${var.stack_suffix}"
  }
}


### Start - AWS Lambda Deployment

resource "aws_security_group" "lambda_sg" {
  name        = "LambdaSG-${var.stack_suffix}"
  description = "Allow Lambda to reach Neptune on 8182"
  vpc_id      = var.vpc_id

  egress {
    from_port       = 8182
    to_port         = 8182
    protocol        = "tcp"
    security_groups = [ aws_security_group.neptune_sg.id ]
  }

  # Allow all outbound to cover CloudWatch, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "lambda_worker_role" {
  name = "LambdaWorker-${var.stack_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["lambda.amazonaws.com"] }
      Action    = ["sts:AssumeRole"]
    }]
  })
}

resource "aws_iam_role_policy" "lambda_read_policy" {
  name = "ReadS3Policy-${var.stack_suffix}"
  role = aws_iam_role.lambda_worker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.customer_upload_bucket}",
          "arn:aws:s3:::${var.customer_upload_bucket}/*"
        ]
      }
    ]
  })
}

# Attach managed policies for VPC access + logs
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.lambda_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/_build"
  output_path = "${path.module}/_build/lambda_query_worker.zip"
}

resource "aws_lambda_function" "lambda_neptune_query" {
  function_name    = "NeptuneQueryWorker-${var.stack_suffix}"
  filename         =  data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256 # Tracks changes within the zip file
  handler          = "watcher.handler"
  runtime          = "nodejs18.x"
  role             = aws_iam_role.lambda_worker_role.arn
  timeout          = 30

  # VPC access so it can reach Neptune endpoints
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [
      aws_security_group.lambda_sg.id,
      aws_security_group.neptune_sg.id
    ]
  }

  environment {
    variables = {
      NEPTUNE_LOADER_URL = aws_neptune_cluster.neptune_cluster.endpoint
      CUSTOMER_UPLOAD_BUCKET = var.customer_upload_bucket
      IAM_LOADER_ROLE = aws_iam_role.neptune_loader_role.arn
      REGION = var.region
    }
  }
}


resource "aws_ssm_parameter" "digital_twin_service_config" {
  name        = "/${lower(var.stack_suffix)}/config/digital-twin-service"
  description = "Configuration for Digital Twin Service"
  type        = "String"
  tier        = "Standard"

  value = <<EOT
{
 "NeptuneWriterEndpoint":"${aws_neptune_cluster.neptune_cluster.endpoint}",
 "LambdaWorker":"NeptuneQueryWorker-${var.stack_suffix}"
}
EOT
}
