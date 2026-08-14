# Day 4 — Trivy Kubernetes Config Scan: Findings Mapping

## Summary

Trivy config scan (scan-type: config, scan-ref: infra/kubernetes/) against the base
Kubernetes manifests returned 16 total findings, all at HIGH severity, zero CRITICAL.
Pipeline correctly hard-failed (exit code 1) per the CRITICAL/HIGH threshold.

Severity filter was removed entirely and the scan re-run against the same report -
identical 16 findings returned, confirming no additional findings exist at
LOW/MEDIUM/UNKNOWN severity that the filter was hiding.

## Mapping to Vulnerability Index

| Trivy Check | Finding | File(s) | Vulnerability Index |
|---|---|---|---|
| KSV-0017 | Privileged container | auth-service.yaml, frontend.yaml, transaction-service.yaml | CK-04 - exact match |
| KSV-0109 | ConfigMap with secrets | configmap.yaml | CK-09 - exact match |
| KSV-0118 | Default security context configured | auth-service.yaml, frontend.yaml, transaction-service.yaml, databases.yaml (x4) | Related to CK-04; not separately numbered |
| KSV-0014 | Root filesystem not read-only | auth-service.yaml, frontend.yaml, transaction-service.yaml, databases.yaml (x2) | Related to CK-04; not separately numbered |

## Confirmed Coverage Gap

CK-06 (mutable :latest image tags) and CK-07 (missing required labels) do not
appear anywhere in Trivy's config scan output for these manifests, at any severity.
This was confirmed empirically by re-running the parsing script with the severity
filter fully removed - the result set was identical to the filtered version,
proving these checks are absent from Trivy's KSV rule set for this scan, not
merely filtered out by severity threshold.

Notably, CK-06 is independently detected by SonarQube (Day 3 finding
kubernetes:S6596, "Use a specific version tag for the image instead of latest",
flagged on all three service manifests at MAJOR severity). This demonstrates
real, concrete value in running multiple IaC/config scanners with overlapping
but non-identical rule coverage: a gap in one tool's ruleset was independently
covered by another tool already in the pipeline.

CK-07 (missing labels) and CK-08 (no NetworkPolicy in the namespace) remain
undetected by any scanner in the pipeline so far. CK-08 in particular is
structurally difficult for static per-file config scanning to catch at all,
since it represents the absence of an entire resource rather than a
misconfiguration within an existing file - a genuine, inherent limitation of
this class of tool, not a configuration error.

## Raw Findings (full list, unfiltered)

HIGH  KSV-0014  base/auth-service.yaml            Root file system is not read-only
HIGH  KSV-0017  base/auth-service.yaml            Privileged
HIGH  KSV-0118  base/auth-service.yaml            Default security context configured
HIGH  KSV-0109  base/configmap.yaml               ConfigMap with secrets
HIGH  KSV-0014  base/databases.yaml               Root file system is not read-only
HIGH  KSV-0014  base/databases.yaml               Root file system is not read-only
HIGH  KSV-0118  base/databases.yaml               Default security context configured
HIGH  KSV-0118  base/databases.yaml               Default security context configured
HIGH  KSV-0118  base/databases.yaml               Default security context configured
HIGH  KSV-0118  base/databases.yaml               Default security context configured
HIGH  KSV-0014  base/frontend.yaml                Root file system is not read-only
HIGH  KSV-0017  base/frontend.yaml                Privileged
HIGH  KSV-0118  base/frontend.yaml                Default security context configured
HIGH  KSV-0014  base/transaction-service.yaml     Root file system is not read-only
HIGH  KSV-0017  base/transaction-service.yaml     Privileged
HIGH  KSV-0118  base/transaction-service.yaml     Default security context configured
