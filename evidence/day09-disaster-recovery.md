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

## Update: Local Container Registry — Follow-up Work

Set up a local Docker registry (registry:2), connected to the kind network,
with containerd on the control-plane node configured to trust it via
/etc/containerd/certs.d/localhost:5001/hosts.toml. Pushed all three
service images and confirmed real, non-empty RepoDigests for the first
time in the project (Day 8's local-only images never had this).

Proved the full chain works: a test pod successfully pulled a
digest-referenced image through the registry and passed live Gatekeeper
admission. Updated all three Deployment manifests to reference real
pushed digests instead of :latest tags, removing the now-unnecessary
imagePullPolicy: IfNotPresent workaround.

Result: K8sNoLatestTag constraint violations dropped from 3 (Day 8's
documented, accepted gap) to 0 — genuinely closed, not skipped or
explained away.

While rolling out the new digests, discovered a second, distinct
consequence of the day's earlier Docker Desktop incident: Vault's
Kubernetes auth configuration had been silently wiped (vault-0 had
restarted once, 3+ hours earlier, confirmed via kubectl get pod restart
count), consistent with dev mode's in-memory-only storage losing all
configuration on any restart. Diagnosed precisely via vault read
auth/kubernetes/config returning "No value found" despite the pod
itself appearing healthy — re-applied Vault's full configuration
(auth method, secrets, policies, roles, audit logging) to resolve.

Final state: all pods healthy, all four Gatekeeper constraints at zero
violations, digest-based image pinning genuinely functional end to end.

## Day 10 Update: Real NetworkPolicy Gap Discovered and Closed

While closing the remaining Trivy K8s findings (readOnlyRootFilesystem on
all workloads, ConfigMap secret removal), discovered a genuine,
previously-undetected gap: none of the app services' or databases'
egress NetworkPolicies included a namespaceSelector for the vault
namespace. Default-deny NetworkPolicy behavior only matches
same-namespace pods without an explicit namespaceSelector — meaning
cross-namespace Vault access should never have worked reliably at any
point since Vault was first deployed.

Root-caused via two distinct symptoms in sequence: app-service pods
timing out with "context deadline exceeded" (DNS resolved, connection
timed out) after NetworkPolicy updates were applied but before the Vault
rule was added; then, after fixing app-service policies, database pods
failed differently with "lookup vault.vault.svc: i/o timeout" (DNS
itself failing) — revealing the databases had never had ANY egress
policy at all, only ingress, since their Vault dependency was added
after the original Day 8 NetworkPolicy design.

Added explicit namespaceSelector-based egress rules (port 8200) to all
five workloads' policies. All five pods (auth-service, frontend,
transaction-service, auth-db, transaction-db) confirmed 2/2 Running
following the fix — the full remediation stack (Vault injection,
readOnlyRootFilesystem, real digest pinning, dependency upgrades) now
functioning correctly together for the first time.

This finding is a genuine, valuable one: default-deny network policies
can create silent, hard-to-detect gaps precisely because failures are
timeouts, not clear rejections, and initial connections can appear to
succeed due to timing/caching before a real gap consistently manifests.
