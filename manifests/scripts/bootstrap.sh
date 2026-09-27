#!/bin/sh
set -eu

# 404s if the path doesn't exist yet at all -- treat that the same as
# "no value". Idempotent: only ever writes a value once per path. Same
# pattern as k8s-zot's own bootstrap-secrets job.
ensure_value() {
  path="$1"
  existing=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN_SELF" \
    "$OPENBAO_ADDR/v1/kv/data/homelab/$path" || echo '{}')
  value=$(echo "$existing" | jq -r '.data.data.value // empty')
  if [ -n "$value" ]; then
    echo "$path already has a value, skipping."
    return
  fi
  echo "No value at $path, generating..."
  generated=$(openssl rand -base64 24)
  curl -sf -X POST -H "X-Vault-Token: $VAULT_TOKEN_SELF" \
    -H "Content-Type: application/json" \
    -d "{\"data\": {\"value\": \"$generated\"}}" \
    "$OPENBAO_ADDR/v1/kv/data/homelab/$path" > /dev/null
  echo "Stored new value at $path."
}

main() {
  apk add --no-cache curl jq openssl >/dev/null

  SA_JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  VAULT_TOKEN_SELF=$(curl -sf -X POST "$OPENBAO_ADDR/v1/auth/kubernetes/login" \
    -d "{\"jwt\": \"$SA_JWT\", \"role\": \"backstage-bootstrap\"}" | jq -r .auth.client_token)
  export VAULT_TOKEN_SELF

  ensure_value "k8s-backstage/postgres-password"
  ensure_value "k8s-backstage/backend-auth-key"
}

# Guarded so test/bootstrap-script.bats can source this file to exercise
# ensure_value directly (with curl/openssl mocked) without also running
# main's real OpenBao login.
if [ "${BOOTSTRAP_SH_SOURCED:-0}" != "1" ]; then
  main
fi
