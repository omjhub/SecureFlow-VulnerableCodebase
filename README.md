# SecureFlow — Secure CI/CD Pipeline for a Vulnerable Banking Platform

This repository is forked from [Dcoder21/SecureFlow-VulnerableCodebase](https://github.com/Dcoder21/SecureFlow-VulnerableCodebase), a deliberately vulnerable banking microservices codebase. **The vulnerable application code is the base repo's, not mine.** What's mine is everything built on top of it: a seven-stage DevSecOps CI/CD pipeline, the security tooling wired into it, and the remediation of the infrastructure-as-code findings that pipeline surfaced.

## The pipeline

A GitHub Actions pipeline enforcing security at seven stages before code can merge:

| Stage | Tool | Purpose |
|---|---|---|
| Secret scanning | Gitleaks | Catch hardcoded credentials before they reach the repo |
| Static analysis | SonarQube | Application code quality and security issues |
| Container scanning | Trivy | CVEs in container images |
| Kubernetes config scanning | Trivy | Misconfigurations in K8s manifests |
| IaC scanning | Checkov | Terraform infrastructure misconfigurations |
| Secrets management | HashiCorp Vault | Centralised secrets, no plaintext credentials in code or config |
| Policy enforcement | OPA Gatekeeper | Admission control policy on the cluster |
| Runtime detection | Falco | Anomalous behaviour detection at runtime |

The pipeline distinguishes DevSecOps-owned findings (Gitleaks, Trivy, Checkov, which block a merge) from AppSec-owned findings (SonarQube, which route to a separate intake without blocking), reflecting how a real organisation would split ownership between infrastructure security and application security teams.

## Infrastructure remediation

The Terraform IaC in this repo started with 72 failing Checkov checks. Rather than suppressing them, each was worked through individually:

- **IAM** scoped to least-privilege managed policies, removing duplicate `AdministratorAccess` grants
- **EKS** moved to private subnets with restricted endpoint access, KMS secrets encryption, full control plane logging, and a supported Kubernetes version
- **S3** buckets fully encrypted, versioned, logged, with public access blocked, plus lifecycle rules and event notifications
- **RDS** moved to private subnets with encryption at rest and in transit (forced SSL/TLS), automated backups, deletion protection, Multi-AZ, IAM authentication, and CloudWatch logging
- **IRSA** (IAM Roles for Service Accounts) established via an OIDC provider, replacing shared node-role permissions with a per-service least-privilege pattern
- **VPC flow logs**, a locked-down default security group, and explicit KMS key policies added to close remaining gaps

This brought Checkov down to 6 remaining findings, each individually reviewed: one resolved by forcing SSL/TLS on RDS connections, and the rest genuinely tool-limitation findings (cases where the underlying design is correct but Checkov's static check can't recognise it), each documented with a `checkov:skip` annotation explaining why, not suppressed silently. Final state: 72 to 0, with every skip formally justified rather than blanket-ignored.

## Proof the pipeline actually blocks

This isn't a pipeline that only runs and reports, it enforces. A recent pull request into `main` was automatically blocked by the security gate:

```
Security Gate Report
DevSecOps-Owned Findings (blocking):
  Gitleaks (secrets): 87
  Trivy image scan (CRITICAL/HIGH CVEs): 175
  Trivy K8s config scan (CRITICAL/HIGH): 13
  Checkov Terraform scan (failed checks): 0
AppSec-Owned Findings (routed, non-blocking):
  SonarQube (application code): 2 — routed to AppSec intake
Result: BLOCKED — DevSecOps-owned findings present (275 total)
```

That block is expected and correct: the base repo's application code is intentionally vulnerable, so the secret and CVE scanners are supposed to find a large number of issues in it. The infrastructure layer (Checkov) is clean at 0, which is the part I was responsible for hardening.

## Tools

`Gitleaks` `SonarQube` `Trivy` `Checkov` `HashiCorp Vault` `OPA Gatekeeper` `Falco` `Terraform` `GitHub Actions` `AWS (EKS, RDS, S3, IAM)`
