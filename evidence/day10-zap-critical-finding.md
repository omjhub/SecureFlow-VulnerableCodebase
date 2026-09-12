# CRITICAL — Live Werkzeug Interactive Debugger Exposed (AV-08, elevated severity)

## Discovery
During Day 10 authenticated ZAP full-scan, the spider's crawl results
included file-path-like URLs (e.g. /usr/local/lib/python3.12/site-packages/flask/app.py)
sourced from Werkzeug debugger stack-trace pages. Initial verification
attempt failed due to a DNS resolution difference between host and
container context (host.docker.internal only resolves inside Docker
Desktop-managed containers, not the host terminal) — re-verified
correctly via localhost.

## Confirmed
GET http://localhost:5000/transfer?__debugger__=yes&cmd=resource&f=debugger.js
returns HTTP 200 with the full, genuine Werkzeug interactive debugger
JavaScript, confirming FLASK_DEBUG=True (or equivalent) is active in
this deployment and the debugger endpoint is live and reachable,
unauthenticated at the HTTP level (reachable without any session state
beyond normal page access).

## Severity and impact
The retrieved JavaScript confirms a functioning remote Python code
execution console (openShell/handleConsoleSubmit, submitting arbitrary
Python via cmd= parameter) is architecturally present and reachable.
Execution is gated by a PIN (EVALEX_TRUSTED / pinauth flow) — the PIN
itself was NOT tested or bypassed, as doing so would constitute active
exploitation beyond the scope of confirming the finding.

This elevates AV-08 (previously documented as an information-disclosure
finding — stack traces revealing file paths and hardcoded credential
fallbacks) to a CRITICAL, RCE-adjacent finding: the debugger is not
merely leaking information on error, it is a live, reachable
administrative interface whose only protection is a PIN of unverified
strength.

## Remediation (AppSec-owned, per Security Gate ownership policy)
Set debug=False (or FLASK_DEBUG=0 / FLASK_ENV=production) in the Flask
application configuration for any non-local deployment. This is a
one-line application-code change, squarely AppSec-owned per this
project's ownership matrix (docs/security-gate-policy.md Section 2) —
routed via the standard AppSec intake process, not remediated directly
in this engagement.
