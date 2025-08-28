pipeline {
    agent any

    parameters {
        choice(name: 'Environment', choices: ['dev', 'stg', 'prod'], description: 'Environment for deployment')
        choice(name: 'Action', choices: ['apply', 'destroy'], description: 'Choose the Terraform action to perform')
        choice(name: 'region', choices: ['us-east-1', 'us-east-2'], description: 'Choose the specific region')
    }

    environment {
        AWS_DEFAULT_REGION = "${params.region}"
    }

    stages {
        stage('Set AWS account') {
            steps {
                script {
                    def accountMap = [
                        dev:  '569575870388',
                        stg:  'TBD',
                        prod: 'TBD'
                    ]
                    def aws_account_id = accountMap[params.Environment]
                    env.ROLE_ARN = "arn:aws:iam::${aws_account_id}:role/jenkins-terraform-execution"
                    echo "Using AWS Role ARN: ${ROLE_ARN}"
                }
            }
        }

        stage('Assume STS Role') {
            steps {
                script {
                    def credentialsJson = sh(script: "aws sts assume-role --role-arn $ROLE_ARN --role-session-name JenkinsSession", returnStdout: true).trim()
                    def credentials = readJSON text: credentialsJson
                    env.AWS_ACCESS_KEY_ID     = credentials.Credentials.AccessKeyId
                    env.AWS_SECRET_ACCESS_KEY = credentials.Credentials.SecretAccessKey
                    env.AWS_SESSION_TOKEN     = credentials.Credentials.SessionToken
                }
            }
        }

        stage('Verify AWS Credentials') {
            steps {
                sh 'aws sts get-caller-identity'
            }
        }

        stage('Initialize Terraform') {
            steps {
                sh "terraform init -upgrade -backend-config=./env/${params.Environment}/backend.config"
            }
        }

        stage('Validate Terraform') {
            steps {
                sh 'terraform validate'
            }
        }

        stage('Plan Terraform') {
            steps {
                sh 'terraform plan -out=tfplan'
            }
        }

        stage('Apply Terraform') {
            when {
                expression { params.Action == 'apply' }
            }
            steps {
                withEnv(["TF_LOG=DEBUG"]) {
                    sh 'terraform apply -auto-approve tfplan'
                }
            }
        }

        stage('Destroy Terraform') {
            when {
                expression { params.Action == 'destroy' }
            }
            steps {
                withEnv(["TF_LOG=DEBUG"]) {
                    sh "terraform destroy -auto-approve"
                }
            }
        }
    }
}
