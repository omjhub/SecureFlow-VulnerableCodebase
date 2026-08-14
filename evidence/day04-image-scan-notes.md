# Day 4 — Trivy Image Scan Findings

Local baseline (python:3.9-slim, bare image): 7 CRITICAL + 44 HIGH = 51 CRITICAL/HIGH combined
(Debian layer: 7 CRITICAL, 41 HIGH; Python layer: 0 CRITICAL, 3 HIGH)

Per-service CI scan (built images, includes service dependencies):

- auth-service: 56 CRITICAL/HIGH
- transaction-service: 58 CRITICAL/HIGH
- frontend: 58 CRITICAL/HIGH
- Total: 172

Each service exceeds the bare-image baseline because service-specific
Python dependencies (Flask, psycopg2-binary, PyJWT, requests) installed
via pip add their own CVE surface on top of the base image's existing
vulnerabilities. Pipeline correctly hard-failed (exit code 1) on CK-01,
consistent with the intended state through Day 12 remediation.
