# Data source to import existing VPC
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Security Group for Neptune
resource "aws_security_group" "neptune_sg" {
  name        = "DigitalTwinService-NeptuneSG-${var.stack_suffix}"
  description = "Allow intra-VPC on port 8182"
  vpc_id      = var.vpc_id

  ingress {
    description = "Neptune TCP"
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "Neptune TCP"
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = ["10.190.16.0/20"]
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
  cluster_identifier                  = "digital-twin-service-neptune-${lower(var.stack_suffix)}"
  engine                              = "neptune"
  engine_version                      = "1.4.4.0"
  neptune_subnet_group_name           = aws_neptune_subnet_group.neptune_subnet_group.name
  iam_database_authentication_enabled = false
  vpc_security_group_ids              = [aws_security_group.neptune_sg.id]

  # TODO: Disable and provide a final_snapshot_identifier when deploying to prod
  skip_final_snapshot = true

  serverless_v2_scaling_configuration {
    min_capacity = 1.0
    max_capacity = 32.0
  }

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
