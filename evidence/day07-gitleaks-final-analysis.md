# Day 7 — Gitleaks Post-Remediation Analysis (Verified)

## Summary
After git-filter-repo history rewrite and force-push, Gitleaks reports 167
findings across the full rewritten history. Investigated exhaustively —
confirmed NOT a remediation failure. Initial investigation was complicated
by a stale local artifact referencing a commit hash that no longer exists
post-rewrite; re-verified against the fresh run #56 artifact for the
definitive result below.

## Verified Root Causes (both confirmed via direct git/grep inspection)

1. Custom Gitleaks rules (flask-secret-key, postgres-connection-string) match
   on KEY: <value> pattern shape, not on the specific value. Post-scrub lines
   reading "POSTGRES_PASSWORD: REDACTED" still satisfy the pattern, since the
   rule doesn't distinguish a real secret from a redaction placeholder.

2. 110 generic-api-key findings in evidence/day03-sonarqube-findings.json are
   false positives on SonarQube's internal finding-key format
   (AZ-[alphanumeric]{18,20}), confirmed by direct extraction and pattern
   match — unrelated to any real secret.

## Verified Clean (definitive)
Cross-referenced every docker-compose.yml finding's commit hash against the
fresh run #56 Gitleaks artifact: zero findings contain any of the four real
secret values (authpass123, txpass123, super-secret-key-123, changeme) in
any commit reachable in current history. All matches are either REDACTED
placeholders or false positives.

## Conclusion
Remediation is complete and verified. Gitleaks will not show fully "green"
under full-history scanning with pattern-based custom rules that don't
distinguish redaction placeholders from real secrets — this is a gate-design
characteristic, not a security gap. Recommend as Week 2+ follow-up: tighten
custom rule regexes to exclude the literal string "REDACTED", or add it to
an allowlist, to eliminate this specific false-positive class going forward.
