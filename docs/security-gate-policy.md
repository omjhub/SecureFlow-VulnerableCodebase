# SecureFlow Security Gate Policy

## 1. Purpose

This document defines how the SecureFlow CI/CD pipeline decides whether a
pull request is allowed to merge. It exists because different pipeline
stages detect fundamentally different classes of finding, owned by
different teams with different remediation responsibilities. A single,
uniform "fail on any CRITICAL finding" rule, applied blindly across every
stage, either blocks delivery over findings the requesting engineer cannot
fix themselves (application-layer bugs owned by AppSec), or fails to block
delivery over findings that genuinely should never ship (infrastructure
misconfigurations owned by DevSecOps). This policy resolves that by
evaluating every finding through an ownership lens, not severity alone.

## 2. Ownership Matrix

| Scanner | Domain | Owner | Findings Category |
|---|---|---|---|
| Gitleaks | Secrets in git history | DevSecOps | Any committed credential |
| Trivy (image scan) | Container base image CVEs | DevSecOps | CK-01, dependency CVEs |
| Trivy (K8s config scan) | Kubernetes manifest misconfiguration | DevSecOps | CK-04, CK-06, CK-07, CK-08, CK-09 |
| Checkov | Terraform / cloud infrastructure misconfiguration | DevSecOps | IV-01, IV-08, IV-09, IV-10 |
| SonarQube | Application source code (SAST) | AppSec | AV-*, TV-*, FV-* |
| OWASP ZAP (Week 2) | Running application (DAST) | AppSec | AV-*, TV-*, FV-* |

**Rationale:** DevSecOps-owned scanners target artifacts the platform team
directly controls and can remediate without touching application business
logic — Dockerfiles, Kubernetes manifests, Terraform, and the secrets
lifecycle. AppSec-owned scanners target the application's own source code
and runtime behavior, which requires domain knowledge of the business logic
that only the team who wrote that code reliably has.

## 3. Hard-Fail vs. Soft-Fail Rules

- **Hard-fail (blocks merge):** any finding from a DevSecOps-owned scanner,
  regardless of the individual scanner's own severity label, given that two
  of the four DevSecOps-owned tools in this pipeline (Gitleaks, Checkov in
  OSS mode) do not reliably expose a severity tier at all. A committed
  secret or a failed Checkov infrastructure check is treated as
  unconditionally blocking.
- **Soft-fail (does not block merge):** any finding from an AppSec-owned
  scanner, at any severity, including CRITICAL/BLOCKER. These findings are
  surfaced prominently in the PR comment and routed to the AppSec team's
  intake queue, but do not prevent the PR from merging.

This differs from Day 3's original per-stage design (SonarQube hard-failing
on CRITICAL/BLOCKER in isolation) precisely because that per-stage design
had no ownership awareness. The Security Gate is the stage where ownership
is applied and the earlier, cruder severity-only logic is superseded.

## 4. Exception Process

A DevSecOps-owned finding may be temporarily exempted from blocking a merge
via the `/security-exception` PR comment trigger, subject to:

1. The commenter must provide a written justification in the same comment.
2. The exception applies only to the specific PR it is issued on, and only
   for the current commit at time of issuance — a new commit requires a new
   exception.
3. Exceptions are logged (via the PR comment thread itself, which is
   permanent and auditable) and must reference a remediation deadline.
4. Exceptions do not apply to Gitleaks findings (committed secrets) under
   any circumstances — a leaked credential is remediated by rotation and
   history rewrite, not bypassed.

## 5. AppSec Intake Template

When the Security Gate posts AppSec-owned findings to a PR comment, each
finding includes:
