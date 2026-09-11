# Day 9 — Unplanned Full Cluster Recovery

## What happened
At the start of Day 9, discovered the entire local kind cluster and all
Docker containers across every project had been removed — traced to an
external cause (not a deliberate action), confirmed via docker ps -a
showing containers from multiple unrelated projects also missing or
exited. The kind control-plane container for this project did not exist
in docker ps -a output at all.

## Recovery
Rebuilt the entire cluster from scratch using committed manifests and
documented procedures from Days 6-8: kind cluster creation, image
rebuild/load, base manifest application (including all NetworkPolicies),
Vault installation and full manual configuration (K8s auth, secrets,
policies, roles, audit logging), OPA Gatekeeper installation and all
four ConstraintTemplates/Constraints, Falco installation with custom
rules.

Encountered two genuine new issues during recovery, both diagnosed and
resolved:
- A Vault exec attempted before the pod was ready (simple timing retry)
- A Docker Desktop network degradation causing image pull timeouts
  (resolved via Docker Desktop restart, same remedy as Day 1/Day 6)

## Verification
Final state confirmed to exactly match pre-incident results: all 5
application/database pods Running (2/2 on app services), all 4 Gatekeeper
constraints showing identical violation counts to Day 8's original run
(0/0/0/3, with the 3 being the same already-documented :latest-tag gap),
Falco 2/2 Running with custom rules loaded.

## Significance
This is a genuine, unplanned demonstration of the value of
infrastructure-as-code and documented procedure: despite total loss of
the running cluster state, nothing of substance was actually lost, since
every piece of configuration existed as either committed YAML or a
documented, repeatable command sequence. Full recovery took under an
hour, entirely from git history and prior session documentation.

## Update: Prometheus/Grafana Install — Second Real Incident

During Prometheus + Grafana installation, Docker Desktop filled to
capacity, requiring a full system restart. This interrupted the original
helm install mid-operation, leaving the release permanently stuck in
pending-install status (confirmed via helm list) — every subsequent
upgrade/rollback attempt correctly failed rather than proceed against a
broken state.

Separately, and more significantly: Grafana's default image tag
(13.2.1-distroless) crashed repeatedly with exit code 135 (SIGBUS),
not OOMKilled (137) as initially hypothesized — ruling out resource
exhaustion as the actual cause, confirmed via kubectl's lastState.terminated
field rather than assumed from docker stats alone. SIGBUS on Apple
Silicon is a known signature of architecture-mismatched or emulation-
incompatible binaries, particularly in minimal "distroless" image
variants with less tolerance for platform quirks than standard images.

Resolved via clean uninstall/reinstall with an explicit, non-distroless
Grafana image (grafana/grafana:11.4.0) specified from the initial
install, avoiding the stuck pending-install trap entirely on the second
attempt. Confirmed stable: 3/3 Running, 0 restarts, verified against a
real working dashboard showing live per-namespace metrics across the
entire rebuilt cluster (secureflow, vault, monitoring, kube-system).

Full cluster (Vault, Gatekeeper, Falco, Prometheus/Grafana, all app
services) confirmed fully restored and stable following both incidents.
