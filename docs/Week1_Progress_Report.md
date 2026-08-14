# SecureFlow DevSecOps Pipeline — Week 1 Progress Report

**Project:** AMDARI Project 3 — Securing a Vulnerable Banking Platform with a DevSecOps Pipeline
**Repository:** github.com/omjhub/SecureFlow-VulnerableCodebase
**Reporting Period:** Days 1–5 (Week 1)
**Author:** omjhub

---

## 1. Executive Summary

Week 1 focused on Pillar 1 of the engagement — building the detection foundation of a seven-stage GitHub Actions security pipeline. By the end of Day 5, four of the seven planned stages (Gitleaks secret scanning, SonarQube SAST, Trivy image/Kubernetes scanning, Checkov Terraform scanning) are operational, hard-failing correctly against the intentionally vulnerable SecureFlow baseline, and aggregated through a fifth stage — a differentiated Security Gate — that applies ownership-aware policy rather than uniform severity thresholds. Branch protection is configured and verified to genuinely enforce the gate's decision, not merely report it. A `/security-exception` mechanism provides an auditable override path for legitimate exceptions.

Across the pipeline, findings were precisely mapped against the documented vulnerability index (AV-*, TV-*, FV-*, IV-*, CK-*), with several genuine findings identified beyond the original index and several documented tool-coverage gaps. Multiple real implementation bugs were encountered, diagnosed from first principles, and resolved — not worked around — and each is documented below as a deliberate part of the evidence trail, since correctly diagnosing a pipeline's own bugs is itself a core DevSecOps skill this project is meant to build.

Pipeline is currently red across every DevSecOps-owned stage, as intended: no remediation has occurred yet. This is the correct, designed state through Day 12.

---

## 2. Pipeline Architecture

### 2.1 Stages Implemented (Week 1)

| Stage | Tool | Trigger Scope | Hard-Fail Condition |
|---|---|---|---|
| 1 — Secret Scan | Gitleaks (CLI, direct invocation) | Full git history | Any finding |
| 2 — SAST | SonarQube Cloud | PR diff (PR-scoped) / whole project (push-scoped) | CRITICAL/BLOCKER |
| 3 — Image Scan | Trivy | All 3 service images | CRITICAL/HIGH CVEs |
| 4a — K8s Config Scan | Trivy (config mode) | infra/kubernetes/ | CRITICAL/HIGH misconfigurations |
| 4b — IaC Scan | Checkov | infra/terraform/ | Any failed check (severity unavailable in OSS mode) |
| 5 — Security Gate | Custom aggregation (bash + jq + github-script) | All upstream artifacts | Any DevSecOps-owned finding |

### 2.2 Key Architecture Decisions

- **Gitleaks runs via direct CLI invocation, not the `gitleaks-action` wrapper.** The wrapper scopes `pull_request`-triggered runs to the PR's diff only; the project's full-history requirement (`--log-opts='--all'`) needed the CLI called directly with an explicit `--source .` and full `fetch-depth: 0` checkout.
- **Every scanner stage separates "run the scan" from "decide pass/fail."** Each scan step uses a tool-specific non-blocking flag (`exit-code: 0` for Trivy, `soft_fail: true` for Checkov) so all findings are captured as artifacts regardless of severity, and a subsequent step applies the actual gate logic. This pattern, established on Day 3 and reused through Day 5, is what makes the Security Gate's aggregation possible — every stage's full findings survive as a downloadable JSON artifact.
- **The Security Gate applies ownership, not severity, as the primary gating axis.** Gitleaks, Trivy (image + K8s), and Checkov are DevSecOps-owned and block on any finding. SonarQube (and, in Week 2, OWASP ZAP) are AppSec-owned and never block, regardless of severity — this resolves a real architectural tension first identified on Day 3, when SonarQube's isolated hard-fail-on-CRITICAL logic was shown to conflict with the project's own stated ownership model once real application-layer CRITICAL findings existed on `main`.
- **Branch protection, not just pipeline exit codes, enforces the gate.** A required-status-check rule on `main` (Security Gate) was configured on Day 5, converting the gate from a self-reported result into a genuinely unbypassable merge block, verified by observing the GitHub UI's merge button become disabled on a failing PR.
- **image-scan, k8s-iac-scan, and terraform-iac-scan run in parallel**, not sequentially as the original task documentation specified, since the three are functionally independent scanners with no shared inputs — a deliberate, documented deviation reducing total pipeline runtime with no loss of detection accuracy.

---

## 3. Findings Summary

### 3.1 Aggregate Counts (as of Day 5, `main` branch)

| Source | Total Findings |
|---|---|
| Gitleaks (full history) | 16 (repo-current) / additional historical findings recovered from a since-renamed `.env.txt`, confirming git history permanence |
| SonarQube (full project) | 55 total, 12 CRITICAL/BLOCKER |
| Trivy (image scan, 3 services combined) | 172 CRITICAL/HIGH |
| Trivy (K8s config scan) | 16 CRITICAL/HIGH |
| Checkov (Terraform) | 72 failed checks (of 124 total) |
| **DevSecOps-owned total feeding Security Gate** | **339** |

### 3.2 Vulnerability Index Coverage

Confirmed exact or near-exact matches: AV-01, AV-02, AV-05, AV-06, AV-07, AV-08 (Days 1–2, manual exploitation and SonarQube); TV-01, TV-03, TV-06 (Day 2, SonarQube); FV-01, FV-05, FV-06, FV-07 (Days 1–2); IV-01, IV-03, IV-05, IV-06, IV-07, IV-08, IV-09, IV-10 (Gitleaks, SonarQube, Checkov); CK-01, CK-02, CK-04, CK-09 (Trivy image and K8s scans).

**Confirmed tool coverage gaps, verified empirically rather than assumed:** CK-06 (mutable `:latest` tags) is not detected by Trivy's K8s ruleset at any severity, but is independently caught by SonarQube — demonstrating real value in overlapping tool coverage. CK-07 (missing labels) and CK-08 (no NetworkPolicy) remain undetected by any scanner as of Day 5; CK-08 is flagged as structurally difficult for any per-file static scanner to catch, since it represents an absent resource rather than a misconfigured one, and is expected to be addressed by OPA Gatekeeper admission policies in Week 2.

**Findings beyond the original documented index:** Checkov surfaced approximately 60 additional genuine infrastructure hardening gaps (RDS encryption/backup/monitoring, VPC flow logging, S3 versioning/lifecycle/KMS encryption, security group description requirements) consistent with the existing IV categories but not individually named in the original vulnerability index. SonarQube independently flagged a supply-chain finding in the pipeline's own workflow file (unpinned `actions/checkout` version), and a network-binding finding (`0.0.0.0` binding) across all three services' Flask apps.

---

## 4. Challenges and Resolutions

Five genuine implementation bugs were encountered, diagnosed, and fixed this week. Each is documented here deliberately, since correctly diagnosing a pipeline's own defects — distinct from the vulnerabilities the pipeline is scanning for — is a core, transferable DevSecOps skill.

**4.1 — Gitleaks custom rule regex mismatch (Day 3).** Initial `.gitleaks.toml` rules assumed quoted assignment syntax (`KEY = 'value'`), matching Python conventions. The actual codebase used unquoted YAML/`.env`-style assignment (`KEY: value`, `KEY=value`), causing custom rules to silently match nothing without erroring. Diagnosed by manually inspecting the target files' actual format rather than assuming the original rule design was correct, and corrected with a regex accepting optional quoting.

**4.2 — `aquasecurity/trivy-action` tag format (Day 4).** The action's version tag changed from unprefixed (`0.36.0`) to `v`-prefixed (`v0.36.0`) as a direct response to a supply-chain attack on the action itself, verified against the project's release notes rather than assumed. This is treated as a live, concrete instance of the OWASP A03:2025 Software Supply Chain Failures category this project targets — occurring in the project's own tooling, not just the application under test.

**4.3 — Checkov severity field unavailable in OSS mode (Day 4).** Initial gate logic filtered Checkov findings by severity, matching the pattern used for Trivy. The job passed green despite 72 genuine failed checks, because Checkov's open-source mode (no Bridgecrew/Prisma Cloud API key) does not populate the `severity` field — every finding's severity was `null`, so the filter matched nothing without throwing an error. Caught by noticing the console log showed real failures despite a passing job status, and confirmed via direct JSON inspection (`set(c.get('severity') for c in failed_checks)` returned `{None}`) before correcting the gate to hard-fail on any failed check.

**4.4 — `actions/github-script` default token permissions (Day 5).** The Security Gate's PR-comment-posting step failed with a 403 "Resource not accessible by integration" error. GitHub's response headers explicitly named the missing scopes (`issues=write; pull_requests=write`), which the default `GITHUB_TOKEN` does not grant by default. Resolved with an explicit job-level `permissions:` block, granted only to the one job that needs it — consistent with least-privilege practice observed elsewhere in the project (PAT scoping, Day 2).

**4.5 — SonarQube "new code" diff-detection granularity (Day 5).** While testing the Security Gate's non-blocking AppSec path, an adjacent comment line added above a flagged CRITICAL line did not cause SonarQube to re-flag it — "new code" is determined by whether the specific flagged line's own content changed, not its proximity to an edit. Resolved by modifying the flagged line's content directly (a trailing, behavior-inert comment), which correctly triggered new-code detection.

**4.6 — `/security-exception` workflow bootstrapping (Day 5).** The exception-handling workflow, triggered on `issue_comment`, could not fire until it existed on the repository's default branch — but landing it on `main` required passing the very gate the exception mechanism exists to formalize. Resolved using the repository admin's built-in "merge without waiting for requirements" override, which is itself the real-world mechanism the project's own policy document (Section 4) describes — used here as the deliberate, first, and documented use of that override to bootstrap the exception system into existence.

---

## 5. Key Learnings

- A pipeline stage reporting success is not proof of correctness; several bugs this week (4.3, 4.5) produced a passing or misleading result while the underlying logic was wrong. Direct inspection of raw data, not trust in a green checkmark, caught both.
- Git history is genuinely permanent absent deliberate rewriting — demonstrated empirically, not just explained conceptually, when Gitleaks recovered secrets from a file renamed away on Day 1.
- Differentiated, ownership-aware gating is materially more complex to implement correctly than uniform severity-based gating, but is necessary once an organization has genuine role separation between infrastructure and application ownership — a tension this project surfaced organically rather than by design instruction alone.
- Tooling itself is part of the supply chain under evaluation (4.2), not exempt from the same scrutiny applied to the application.

---

## 6. Open Questions for Week 2

- CK-07 (missing labels) and CK-08 (no NetworkPolicy) remain undetected by any Week 1 scanner — will OPA Gatekeeper's admission-time enforcement close this gap, or does it require a separate, additional detection mechanism prior to enforcement?
- The Security Gate currently treats all Checkov findings as equally blocking (severity unavailable in OSS mode). Is a self-maintained severity mapping (keyed by `check_id`) worth building in Week 2, or is "any failed check blocks" an acceptable permanent policy given the infrastructure-ownership rationale in Section 3 of the policy document?
- Vault's dynamic secrets and per-service policies (Week 2) will change how secrets are detected going forward — does Gitleaks' scanning scope need to change once secrets move out of environment variables and into Vault-injected mounted files?
- Falco's runtime detection (Week 2) is the first stage operating on a live, running system rather than static analysis — what evidence-capture pattern (equivalent to this week's JSON-artifact-per-stage approach) is appropriate for runtime alerts, which are inherently time-series rather than point-in-time?

---

*End of Week 1 Progress Report. Full evidence, JSON findings, and screenshots referenced throughout are committed under `evidence/` and `screenshots/` in the project repository.*
