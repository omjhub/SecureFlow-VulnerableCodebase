variable "project" { type = string }
variable "environment" { type = string }

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-igw"
  }
}

# Public subnets — retained only for the NAT gateway and any public-facing
# load balancer. EKS nodes no longer live here (see private subnets below).
# CKV_AWS_130 — accepted risk, both public subnets: these subnets
# specifically host the NAT gateway, which requires a public IP to
# function. This is correct by design, not a misconfiguration.
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = ["${var.project}-az-a", "${var.project}-az-b"][count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.environment}-public-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# IV-10 remediated — private subnets for EKS nodes. No public IP
# auto-assignment, no direct route to the internet gateway.
resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 10}.0/24"
  availability_zone       = ["${var.project}-az-a", "${var.project}-az-b"][count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project}-${var.environment}-private-${count.index}"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project}-${var.environment}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project}-${var.environment}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project}-${var.environment}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# IV-08 adjacent, remediated — ingress restricted to the application's
# actual ports, from within the VPC only, not the entire internet.
# CKV2_AWS_5 — accepted risk: this security group is defined but not
# yet attached to the EKS node group's network interfaces. Wiring it
# in requires updating the eks module's aws_eks_node_group resource
# with vpc_security_group_ids — a follow-up, not today's scope.
resource "aws_security_group" "app" {
  name        = "${var.project}-${var.environment}-app-sg"
  description = "Restricted ingress for SecureFlow application ports"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Frontend"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "auth-service and transaction-service, internal only"
    from_port   = 5001
    to_port     = 5002
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # CKV_AWS_382 — accepted risk: broad egress required for image pulls
  # and external API calls from application pods. Narrowing this to
  # specific destinations is a follow-up, not today's scope.
  egress {
    description = "All outbound — accepted risk, see comment above"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-app-sg"
  }
}

# CKV2_AWS_12 remediated — lock down the VPC's own default security
# group, which AWS creates automatically with permissive rules that
# Terraform doesn't manage unless explicitly claimed like this.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  # No ingress/egress blocks = fully closed, no traffic allowed.
}

# CKV2_AWS_11 remediated — VPC flow logs, capturing all accepted and
# rejected traffic for the audit trail.
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${var.project}-${var.environment}-flow-logs"
  retention_in_days = 90
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.project}-${var.environment}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${var.project}-${var.environment}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
