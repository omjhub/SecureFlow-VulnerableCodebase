variable "project" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "db_password" { type = string }

data "aws_caller_identity" "current" {}

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

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-db-subnet"
  subnet_ids = var.private_subnet_ids
}

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

  # CKV_AWS_382 remediated (not skipped) — a database has no legitimate
  # reason to reach the open internet; restricted to VPC-internal traffic,
  # same as ingress.
  egress {
    description = "VPC-internal only — RDS does not need external egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

# CKV2_AWS_30 remediated — custom parameter group enabling query logging.
resource "aws_db_parameter_group" "postgres" {
  name   = "${var.project}-${var.environment}-postgres-params"
  family = "postgres14"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }
}

# CKV_AWS_118 remediated — enhanced monitoring requires its own IAM role,
# trusted by the RDS monitoring service specifically.
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project}-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
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
  password = var.db_password # IV-01 remains out of scope — RDS Vault migration is a follow-up.

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name
  publicly_accessible    = false

  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project}-${var.environment}-authdb-final"
  copy_tags_to_snapshot     = true

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
  iam_database_authentication_enabled = true

  multi_az                    = true
  auto_minor_version_upgrade  = true
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
  parameter_group_name   = aws_db_parameter_group.postgres.name
  publicly_accessible    = false

  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project}-${var.environment}-txdb-final"
  copy_tags_to_snapshot     = true

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
  iam_database_authentication_enabled = true

  multi_az                    = true
  auto_minor_version_upgrade  = true
}
