# Day 4 — Master Findings Summary Table (Unified Format)
**Tool | Finding ID | Severity | File | Line | Owner**

This supersedes the multi-table version in day04-master-findings-summary.md
with a single table matching the exact requested format. Findings are
grouped by category; representative entries shown per group where a
single check applies to many near-identical lines (full detail remains in
the JSON evidence files under evidence/day04/).

| Tool | Finding ID | Severity | File | Line | Owner |
|---|---|---|---|---|---|
| Gitleaks | flask-secret-key | — (hard-fail, no severity tier) | docker-compose.yml | 45 | DevSecOps |
| Gitleaks | postgres-connection-string | — (hard-fail) | docker-compose.yml | 18, 30, 44, 58 | DevSecOps |
| Gitleaks | postgres-connection-string | — (hard-fail) | infra/kubernetes/base/configmap.yaml | 11, 12 | DevSecOps |
| Gitleaks | flask-secret-key | — (hard-fail) | infra/kubernetes/base/configmap.yaml | 9, 10 | DevSecOps |
| Gitleaks | postgres-connection-string | — (hard-fail) | infra/terraform/main.tf | 66 | DevSecOps |
| Gitleaks | postgres-connection-string / flask-secret-key | — (hard-fail) | .env.txt (historical, commit 6ba14d27) | 31, 39, 44 | DevSecOps |
| SonarQube | python:S4790 (AV-05) | CRITICAL | services/auth-service/app.py | 32 | AppSec |
| SonarQube | python:S4502 (TV-06/FV-05) | CRITICAL | services/auth-service/app.py | 12 | AppSec |
| SonarQube | python:S4502 (FV-05) | CRITICAL | services/frontend/app.py | 10 | AppSec |
| SonarQube | python:S4502 (TV-06) | CRITICAL | services/transaction-service/app.py | 10 | AppSec |
| SonarQube | python:S8392 | BLOCKER | services/auth-service/app.py | 162 | AppSec (deployment-config edge case — see Day 3 notes) |
| SonarQube | python:S8392 | BLOCKER | services/frontend/app.py | 185 | AppSec (deployment-config edge case) |
| SonarQube | python:S8392 | BLOCKER | services/transaction-service/app.py | 201 | AppSec (deployment-config edge case) |
| SonarQube | terraform:S6302 (IV-08) | BLOCKER | infra/terraform/modules/iam/main.tf | 52 | DevSecOps |
| SonarQube | terraform:S8793 (IV-10) | BLOCKER | infra/terraform/modules/rds/main.tf | 46, 66 | DevSecOps |
| SonarQube | terraform:S6281 (IV-09) | CRITICAL | infra/terraform/modules/s3/main.tf | 20, 34 | DevSecOps |
| Trivy (image) | CVE-2026-31789 (openssl) | CRITICAL | services/*/Dockerfile (python:3.9-slim base) | n/a — package-level, not line-level | DevSecOps |
| Trivy (image) | CVE-2026-13221 (perl-base) | CRITICAL | services/*/Dockerfile (python:3.9-slim base) | n/a — package-level | DevSecOps |
| Trivy (K8s) | KSV-0017 — CK-04 | HIGH | infra/kubernetes/base/auth-service.yaml | n/a — Trivy config output does not report line numbers for this rule | DevSecOps |
| Trivy (K8s) | KSV-0017 — CK-04 | HIGH | infra/kubernetes/base/frontend.yaml | n/a | DevSecOps |
| Trivy (K8s) | KSV-0017 — CK-04 | HIGH | infra/kubernetes/base/transaction-service.yaml | n/a | DevSecOps |
| Trivy (K8s) | KSV-0109 — CK-09 | HIGH | infra/kubernetes/base/configmap.yaml | n/a | DevSecOps |
| Checkov | CKV_AWS_274 — IV-08 | — (severity unavailable, OSS mode) | infra/terraform/modules/iam/main.tf | 23-26 | DevSecOps |
| Checkov | CKV_AWS_62/63/286-290/355 — IV-08 | — (severity unavailable) | infra/terraform/modules/iam/main.tf | 44-56 | DevSecOps |
| Checkov | CKV_AWS_53/54/55/56 — IV-09 | — (severity unavailable) | infra/terraform/modules/s3/main.tf | 20-27, 34-41 | DevSecOps |
| Checkov | CKV_AWS_38/39 — IV-10 | — (severity unavailable) | infra/terraform/modules/eks/main.tf | 31-47 | DevSecOps |
| Checkov | CKV_AWS_130 — IV-10 | — (severity unavailable) | infra/terraform/modules/vpc/main.tf | 23-33 | DevSecOps |
| Checkov | CKV_AWS_260/25/24 — IV-10 | — (severity unavailable) | infra/terraform/modules/vpc/main.tf | 51-69 | DevSecOps |
| Checkov | CKV_AWS_16/17 — IV-01 adjacent | — (severity unavailable) | infra/terraform/modules/rds/main.tf | 35-53, 55-70 | DevSecOps |

## Notes on Gaps in This Table

- **Gitleaks and Checkov severity columns show "—"** because neither tool's
  configuration in this pipeline assigns a tiered severity: Gitleaks
  hard-fails on any match by design (no severity concept), and Checkov's
  open-source mode (no Bridgecrew/Prisma API key) leaves `severity` as
  `null` on every finding — confirmed empirically on Day 4.
- **Trivy image-scan findings are package-level, not line-level** — a CVE
  in an installed OS/Python package doesn't correspond to a specific line
  in the Dockerfile; the Dockerfile line that pulls in the vulnerable base
  image is `FROM python:3.9-slim` (line 1 in each Dockerfile), but the
  vulnerability itself lives inside the resulting image's installed
  packages, not the Dockerfile text.
- **Trivy K8s config output did not include line numbers** in the fields
  captured by this pipeline's extraction script; this is a known limitation
  of the current script, not of Trivy itself (Trivy's raw JSON may include
  more granular location data than was extracted — worth revisiting if
  finer precision is needed for the final report).
- **Owner column for `python:S8392`** (binding to 0.0.0.0) is marked as an
  edge case: it's flagged inside application `.py` files but is arguably a
  deployment-configuration concern rather than a pure application-logic
  bug — noted rather than resolved, per Day 3's precedent of stating
  judgment calls explicitly.
