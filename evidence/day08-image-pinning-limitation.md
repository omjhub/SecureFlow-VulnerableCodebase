# Day 8 — Image Digest Pinning: Documented Local Environment Limitation

## What was attempted
Pinned all three service images to their real, verified content digests
(docker inspect --format='{{.Id}}') in place of mutable :latest tags,
directly addressing CK-06.

Digests used:
- secureflow/auth-service: sha256:840089336099f95c213aed58d9635dfe473c0ba1409c337c9853088adf86af98
- secureflow/transaction-service: sha256:39f55080ca830e8bfbb44af25c4ca6f8374a5734e40f1cf7188b100bba1c3ef1
- secureflow/frontend: sha256:57d2ec4fed6135db00eed45ad3bd8c58b880d83489756caa1d53da6ab150bc0e

## What went wrong
Kubernetes' image resolution requires an exact reference match against the
node's local containerd image store. Loading an image via kind load
docker-image (by tag) does not register a corresponding digest-addressable
alias, confirmed directly via `crictl images` on the node — the image
existed only under its :latest tag reference, never under the digest
reference, despite identical underlying content (matching Image ID).

Attempted imagePullPolicy: Never to force local-only resolution; this
produced an explicit ErrImageNeverPull, confirming — rather than working
around — that no local registration exists under the digest reference at all.

## Root cause
This is a structural characteristic of local kind clusters without a
backing container registry, not a configuration error. A real production
cluster pulling from an actual registry (ECR, GHCR, Docker Hub) would
resolve both tag and digest references to the same stored manifest
natively — this limitation is specific to locally-built, never-pushed
images in a registry-less local test cluster.

## Resolution
Reverted to :latest + imagePullPolicy: IfNotPresent for the actually
running cluster. The correct digest values are documented above and were
independently verified as accurate — the pinning logic and intent are
correct; only the local kind environment prevents live enforcement without
introducing a real (even local) registry, which is out of scope for today.

## Recommended follow-up
Stand up a local registry (e.g. `kind` supports a local registry add-on)
or push images to a real registry, to properly demonstrate and enforce
digest-based pulls in a way that mirrors production behavior.
