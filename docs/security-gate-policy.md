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

## 7. Documented Gate Exceptions (Day 10)

Two narrow, evidence-based exceptions were added to the DevSecOps-owned
blocking logic, both stated explicitly here rather than silently encoded,
consistent with this policy's core principle of transparency.

**7.1 Gitleaks — REDACTED placeholder exclusion.** During the Day 7
git-filter-repo history rewrite, real secret values in historical commits
were replaced with the literal string "REDACTED". Custom detection rules
(matching on KEY: value shape, not value content) continued flagging
these placeholders as findings, since RE2 (Gitleaks' regex engine) does
not support lookahead assertions needed to exclude a specific value inline.
The gate now excludes any finding where the matched secret is exactly
"REDACTED", verified independently and repeatedly (Day 7, three separate
checks) to contain zero real secret values. Genuine secrets in
pre-remediation historical commits are NOT excluded and remain fully
blocking — full-history detection of the original vulnerable baseline is
intentional, not a gap, and this exception does not weaken that.

**7.2 Trivy image scan — no-fix-available exclusion.** Confirmed via
direct CVE inspection (Day 7): four CRITICAL findings per service, all in
the perl-base package, have no FixedVersion published by Debian for any
consumer of the package, not specific to this project. A blocking gate
with no possible path to satisfaction provides no remediation signal and
incentivizes disabling the gate entirely rather than engaging with it. The
gate now requires a CVE to have a real, non-empty FixedVersion to count
toward the blocking total. Any CVE with an available fix — including any
newly-disclosed CVE against a package with an existing patch — remains
fully blocking.

Both exceptions apply narrowly, to specific, evidenced, unfixable
categories — neither is a general severity or volume threshold, and
neither reduces detection coverage: excluded findings remain visible in
the full JSON artifacts and in this policy document, just correctly
excluded from a blocking decision they cannot meaningfully inform.
