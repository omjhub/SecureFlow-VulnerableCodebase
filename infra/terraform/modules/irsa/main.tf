variable "project" { type = string }
variable "environment" { type = string }
variable "cluster_oidc_issuer_url" { type = string }
variable "oidc_provider_arn" { type = string }
variable "namespace" {
  type    = string
  default = "secureflow"
}

# Example IRSA binding for the artifacts bucket access this service actually
# needs — auth-service reads CI/CD artifacts for a health/version check.
# This is a template pattern: one aws_iam_role + trust policy per service
# that genuinely needs scoped AWS access, bound to that service's own
# Kubernetes ServiceAccount only.

data "aws_iam_policy_document" "auth_service_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.namespace}:auth-service-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "auth_service_irsa" {
  name               = "${var.project}-${var.environment}-auth-service-irsa"
  assume_role_policy = data.aws_iam_policy_document.auth_service_trust.json
}

# Scoped, read-only policy — this role can read from the artifacts bucket
# specifically, nothing else. No wildcard actions, no wildcard resources.
data "aws_iam_policy_document" "auth_service_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.project}-artifacts",
      "arn:aws:s3:::${var.project}-artifacts/*",
    ]
  }
}

resource "aws_iam_role_policy" "auth_service_irsa" {
  name   = "${var.project}-${var.environment}-auth-service-irsa-policy"
  role   = aws_iam_role.auth_service_irsa.id
  policy = data.aws_iam_policy_document.auth_service_permissions.json
}

output "auth_service_irsa_role_arn" {
  value = aws_iam_role.auth_service_irsa.arn
}
