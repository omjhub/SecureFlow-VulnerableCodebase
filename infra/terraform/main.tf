# SecureFlow Terraform — remediated baseline (Day 8).
# DO NOT `terraform apply` this against a real AWS account without review —
# this tree exists for Checkov static analysis in the pipeline.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "project" {
  type    = string
  default = "secureflow"
}

variable "environment" {
  type    = string
  default = "dev"
}

module "vpc" {
  source      = "./modules/vpc"
  project     = var.project
  environment = var.environment
}

module "iam" {
  source  = "./modules/iam"
  project = var.project
}

module "s3" {
  source  = "./modules/s3"
  project = var.project
}

module "eks" {
  source                  = "./modules/eks"
  project                  = var.project
  environment              = var.environment
  vpc_id                   = module.vpc.vpc_id
  public_subnet_ids        = module.vpc.public_subnet_ids
  private_subnet_ids       = module.vpc.private_subnet_ids
  app_security_group_id    = module.vpc.app_security_group_id
}

# Registers AWS IAM's trust in the EKS cluster's own OIDC identity
# provider — this is the missing link IRSA depends on. Without this
# resource, no IAM role can trust tokens issued by this cluster at all.
data "tls_certificate" "eks" {
  url = module.eks.cluster_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = module.eks.cluster_oidc_issuer_url
}

module "irsa" {
  source                  = "./modules/irsa"
  project                 = var.project
  environment              = var.environment
  cluster_oidc_issuer_url  = module.eks.cluster_oidc_issuer_url
  oidc_provider_arn        = aws_iam_openid_connect_provider.eks.arn
}

module "rds" {
  source             = "./modules/rds"
  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  db_password        = "postgres" # IV-01 remains out of scope — RDS Vault migration is a follow-up.
}
