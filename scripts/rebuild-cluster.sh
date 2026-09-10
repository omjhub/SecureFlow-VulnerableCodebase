#!/bin/bash
set -e

echo "=== Phase 1: Cluster, images, base manifests ==="
kind create cluster --name secureflow

docker build -t secureflow/auth-service:latest ./services/auth-service
docker build -t secureflow/transaction-service:latest ./services/transaction-service
docker build -t secureflow/frontend:latest ./services/frontend

kind load docker-image secureflow/auth-service:latest --name secureflow
kind load docker-image secureflow/transaction-service:latest --name secureflow
kind load docker-image secureflow/frontend:latest --name secureflow

kubectl apply -k infra/kubernetes/base/
sleep 15

echo "=== Phase 2: Vault ==="
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update
helm install vault hashicorp/vault --set='server.dev.enabled=true' --namespace vault --create-namespace
sleep 30

kubectl create serviceaccount auth-service-sa -n secureflow --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount transaction-service-sa -n secureflow --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount frontend-sa -n secureflow --dry-run=client -o yaml | kubectl apply -f -

kubectl exec -n vault vault-0 -- sh -c '
vault auth enable kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
vault secrets enable -path=secureflow kv-v2
vault kv put secureflow/auth-service DB_PASSWORD="authpass123" JWT_SECRET="super-secret-key-123"
vault kv put secureflow/transaction-service DB_PASSWORD="txpass123"
vault kv put secureflow/frontend SESSION_SECRET="changeme"
vault policy write auth-service-policy - <<EOF
path "secureflow/data/auth-service" { capabilities = ["read"] }
EOF
vault policy write transaction-service-policy - <<EOF
path "secureflow/data/transaction-service" { capabilities = ["read"] }
EOF
vault policy write frontend-policy - <<EOF
path "secureflow/data/frontend" { capabilities = ["read"] }
EOF
vault write auth/kubernetes/role/auth-service-role bound_service_account_names=auth-service-sa bound_service_account_namespaces=secureflow policies=auth-service-policy ttl=1h
vault write auth/kubernetes/role/transaction-service-role bound_service_account_names=transaction-service-sa bound_service_account_namespaces=secureflow policies=transaction-service-policy ttl=1h
vault write auth/kubernetes/role/frontend-role bound_service_account_names=frontend-sa bound_service_account_namespaces=secureflow policies=frontend-policy ttl=1h
vault audit enable file file_path=/vault/logs/audit.log
'

kubectl delete pod -n secureflow -l svc=auth-service --ignore-not-found
kubectl delete pod -n secureflow -l svc=frontend --ignore-not-found
kubectl delete pod -n secureflow -l svc=transaction-service --ignore-not-found
sleep 20

echo "=== Phase 3: Gatekeeper and Falco ==="
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts 2>/dev/null || true
helm repo update
helm install gatekeeper gatekeeper/gatekeeper --namespace gatekeeper-system --create-namespace
sleep 45

kubectl apply -f infra/kubernetes/gatekeeper/

helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
helm repo update
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set collectors.containerEngine.enabled=true \
  --set falco.json_output=true \
  --set falco.json_include_output_property=true \
  --set-file customRules."secureflow_rules\.yaml"=infra/kubernetes/falco/custom-rules.yaml

sleep 30
echo "=== Rebuild complete. Verifying ==="
kubectl get pods -n secureflow
kubectl get pods -n vault
kubectl get pods -n gatekeeper-system
kubectl get pods -n falco
kubectl get constraint --all-namespaces
