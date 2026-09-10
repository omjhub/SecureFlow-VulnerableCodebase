variable "project" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "db_password" { type = string }

data "aws_caller_identity" "current" {}

# Dedicated KMS key for RDS storage encryption.
resource "aws_kms_key" "rds" {
  description             = "${var.project}-${var.environment} RDS storage encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EnableRootAccountAccess"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action   = "kms:*"
      Resource = "*"
    }]
  })
}

# IV-10 remediated — private subnets, matching the EKS module's approach.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-db-subnet"
  subnet_ids = var.private_subnet_ids
}

# CKV2_AWS_5 remediated — this security group is genuinely attached, via
# vpc_security_group_ids below, to both aws_db_instance resources.
resource "aws_security_group" "db" {
  name        = "${var.project}-${var.environment}-db-sg"
  description = "PostgreSQL access, restricted to VPC-internal traffic only"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from within the VPC only"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "All outbound — RDS instances initiate no external connections in normal operation"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "auth" {
  identifier     = "${var.project}-${var.environment}-authdb"
  engine         = "postgres"
  engine_version = "14"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  db_name  = "authdb"
  username = "authuser"
  password = var.db_password # IV-01 remains out of Day 8 scope — Vault migration for RDS credentials is a separate, larger follow-up.

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period = 7
  deletion_protection     = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.project}-${var.environment}-authdb-final"

  performance_insights_enabled     = true
  performance_insights_kms_key_id  = aws_kms_key.rds.arn

  enabled_cloudwatch_logs_exports    = ["postgresql", "upgrade"]
  iam_database_authentication_enabled = true

  multi_az = true

  auto_minor_version_upgrade = true
}

resource "aws_db_instance" "transactions" {
  identifier     = "${var.project}-${var.environment}-txdb"
  engine         = "postgres"
  engine_version = "14"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  db_name  = "transactiondb"
  username = "txuser"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project}-${var.environment}-txdb-final"

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn

  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
  iam_database_authentication_enabled = true

  multi_az = true

  auto_minor_version_upgrade = true
}
