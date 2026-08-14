# Day 4 — Master Findings Summary Table
**SecureFlow DevSecOps Pipeline | AMDARI Project 3**

All four Day 4 pipeline stages confirmed hard-failing as expected, given no
remediation has occurred yet (remediation begins Day 12). This document
consolidates findings from Trivy (image scan), Trivy (Kubernetes config scan),
and Checkov (Terraform scan) against the vulnerability index, following the
same mapping approach used for Gitleaks and SonarQube on Day 3.

---

## Pipeline Stage Results Summary

| Stage | Tool | Result | Count |
|---|---|---|---|
| 3 | Trivy (image scan) | Hard-fail | 172 CRITICAL/HIGH CVEs (56 auth-service, 58 transaction-service, 58 frontend) |
| 4a | Trivy (K8s config scan) | Hard-fail | 16 CRITICAL/HIGH misconfigurations |
| 4b | Checkov (Terraform scan) | Hard-fail | 72 failed checks (52 passed, 0 skipped) |

---

## Master Table — Tool | Finding ID | Severity | File | Line | Owner

### Container CVEs (Trivy Image Scan)

| Tool | Finding | Severity | File | Owner |
|---|---|---|---|---|
| Trivy | CK-01 — 7 CRITICAL CVEs in python:3.9-slim base (local baseline; per-service CI totals higher due to added dependencies) | CRITICAL/HIGH | All 3 Dockerfiles | DevSecOps |
| Trivy | CVE-2026-31789 (openssl heap overflow) | CRITICAL | libssl3t64, openssl, openssl-provider-legacy | DevSecOps |
| Trivy | CVE-2026-13221 (perl regex silent-incorrect) | CRITICAL | perl-base | DevSecOps |
| Trivy | jaraco.context CVE-2026-23949 (path traversal) | HIGH | Python package layer | DevSecOps |
| Trivy | wheel CVE-2026-24049 (privilege escalation) | HIGH | Python package layer | DevSecOps |

### Kubernetes Misconfigurations (Trivy K8s Config Scan)

| Tool | Finding ID | Check | Severity | File | Owner |
|---|---|---|---|---|---|
| Trivy | CK-04 | KSV-0017 Privileged container | HIGH | auth-service.yaml, frontend.yaml, transaction-service.yaml | DevSecOps |
| Trivy | CK-04 (related) | KSV-0118 Default security context | HIGH | auth-service.yaml, frontend.yaml, transaction-service.yaml, databases.yaml (x4) | DevSecOps |
| Trivy | CK-04 (related) | KSV-0014 Root filesystem not read-only | HIGH | auth-service.yaml, frontend.yaml, transaction-service.yaml, databases.yaml (x2) | DevSecOps |
| Trivy | CK-09 | KSV-0109 ConfigMap with secrets | HIGH | configmap.yaml | DevSecOps |
| — | CK-06, CK-07, CK-08 | Not detected by Trivy K8s scan (see Day 4 coverage-gap note; CK-06 independently caught by SonarQube Day 3) | — | — | DevSecOps |

### Infrastructure Misconfigurations (Checkov Terraform Scan)

| Tool | Finding ID | Check | File | Owner |
|---|---|---|---|---|
| Checkov | IV-08 | CKV_AWS_274 AdministratorAccess policy attached | eks/main.tf, iam/main.tf | DevSecOps |
| Checkov | IV-08 | CKV_AWS_62/63/286/287/288/289/290/355 Wildcard IAM action/resource, privilege escalation, credential/data exfiltration risk | iam/main.tf | DevSecOps |
| Checkov | IV-08 (related) | CKV2_AWS_40 Full IAM privileges allowed | iam/main.tf | DevSecOps |
| Checkov | IV-09 | CKV_AWS_53/54/55/56 S3 public access block disabled (both buckets) | s3/main.tf | DevSecOps |
| Checkov | IV-09 (related) | CKV2_AWS_6 No S3 Public Access block resource | s3/main.tf | DevSecOps |
| Checkov | IV-09 (related) | CKV_AWS_21/145 No S3 versioning, no KMS encryption | s3/main.tf | DevSecOps |
| Checkov | IV-10 | CKV_AWS_38/39 EKS public endpoint accessible/not disabled | eks/main.tf | DevSecOps |
| Checkov | IV-10 (related) | CKV_AWS_130 VPC subnets assign public IP by default | vpc/main.tf | DevSecOps |
| Checkov | IV-10 (related) | CKV_AWS_260/25/24 Security group allows ingress from 0.0.0.0/0 (ports 80, 3389, 22) | vpc/main.tf | DevSecOps |
| Checkov | IV-01 (adjacent) | CKV_AWS_16/17 RDS not encrypted at rest, publicly accessible | rds/main.tf (both instances) | DevSecOps |
| — | Additional findings beyond original index | CKV_AWS_58/37 (EKS secrets encryption, control-plane logging), CKV_AWS_129/157/161/226/293/353/118 (RDS logging, Multi-AZ, IAM auth, minor upgrades, deletion protection, performance insights, enhanced monitoring), CKV2_AWS_11/12 (VPC flow logging, default SG), CKV_AWS_144/18 (S3 replication, access logging), CKV2_AWS_30/60/61/62 (RDS query logging/tags, S3 lifecycle/event notifications) | Various | DevSecOps — genuine additional hardening gaps beyond the documented three-item list |

---

## Notable Findings Beyond the Original Vulnerability Index

Checkov and Trivy K8s both surfaced substantially more findings than the
documented IV-08/IV-09/IV-10 and CK-04–CK-09 baseline. Worth stating plainly:
this is expected and appropriate — real IaC scanners apply hundreds of
policies, while the original vulnerability index intentionally documents only
the headline, deliberately-planted issues. The additional findings (RDS
encryption, backup retention, VPC flow logging, IAM-authenticated database
access, missing security group descriptions, S3 lifecycle/versioning/KMS
encryption) represent genuine infrastructure hardening gaps consistent with
the same categories (IV-01, IV-08, IV-09, IV-10) already in scope, not new
categories requiring index expansion.

## Tool Coverage Gap (carried from K8s findings mapping)

CK-06 (mutable `:latest` tags) and CK-07 (missing labels) are not detected by
Trivy's K8s config scan at any severity, confirmed empirically. CK-06 is
independently caught by SonarQube (Day 3, `kubernetes:S6596`). CK-07 and CK-08
(no NetworkPolicy) remain undetected by any scanner in the pipeline as of Day
4 — CK-08 in particular is structurally difficult for static per-file
scanning to catch, since it represents an absent resource rather than a
misconfigured one.

## Checkov Severity Limitation

Checkov's open-source mode (no Bridgecrew/Prisma Cloud API key) does not
populate the `severity` field on failed checks — confirmed via direct JSON
inspection (`set(c.get('severity') for c in failed[:20])` returned `{None}`).
The pipeline's gate logic was corrected to hard-fail on any failed check
rather than filtering by severity, since severity data is unavailable in this
configuration.
