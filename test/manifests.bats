#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template backstage-test manifests)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "namespace is backstage" {
  ns=$(resource Namespace backstage)
  [ -n "$ns" ]
}

@test "backend Deployment runs as the backstage ServiceAccount and pulls via the dedicated zot-pull secret" {
  sa=$(resource Deployment backstage | yq '.spec.template.spec.serviceAccountName')
  pull_secret=$(resource Deployment backstage | yq '.spec.template.spec.imagePullSecrets[0].name')
  [ "$sa" = "backstage" ]
  [ "$pull_secret" = "backstage-zot-pull-secret" ]
}

@test "backend Deployment wires all six OpenBao-sourced secret env vars to the backstage Secret" {
  for key in POSTGRES_PASSWORD BACKEND_SECRET GITHUB_APP_ID AUTH_GITHUB_CLIENT_ID AUTH_GITHUB_CLIENT_SECRET GITHUB_APP_PRIVATE_KEY; do
    name=$(resource Deployment backstage | yq ".spec.template.spec.containers[0].env[] | select(.name == \"$key\") | .valueFrom.secretKeyRef.name")
    ref_key=$(resource Deployment backstage | yq ".spec.template.spec.containers[0].env[] | select(.name == \"$key\") | .valueFrom.secretKeyRef.key")
    [ "$name" = "backstage" ]
    [ "$ref_key" = "$key" ]
  done
}

@test "backend Deployment sets plain Postgres connection env vars without going through a Secret" {
  host=$(resource Deployment backstage | yq '.spec.template.spec.containers[0].env[] | select(.name == "POSTGRES_HOST") | .value')
  user=$(resource Deployment backstage | yq '.spec.template.spec.containers[0].env[] | select(.name == "POSTGRES_USER") | .value')
  [ "$host" = "backstage-postgres" ]
  [ "$user" = "backstage" ]
}

@test "ExternalSecret backstage pulls all six keys from kv/homelab/k8s-backstage" {
  count=$(resource ExternalSecret backstage | yq '.spec.data | length')
  [ "$count" = "6" ]
  key=$(resource ExternalSecret backstage | yq '.spec.data[] | select(.secretKey == "GITHUB_APP_PRIVATE_KEY") | .remoteRef.key')
  [ "$key" = "homelab/k8s-backstage/github-app-private-key" ]
}

@test "zot-pull ExternalSecret reads k8s-backstage's own dedicated pull credential, not app-backstage's publish one" {
  key=$(resource ExternalSecret backstage-zot-pull-secret | yq '.spec.data[0].remoteRef.key')
  [ "$key" = "homelab/service/k8s-zot/k8s-backstage/zot-pull" ]
}

@test "SecretStore authenticates as the backstage Kubernetes-auth role via the backstage ServiceAccount" {
  role=$(resource SecretStore openbao | yq '.spec.provider.vault.auth.kubernetes.role')
  sa=$(resource SecretStore openbao | yq '.spec.provider.vault.auth.kubernetes.serviceAccountRef.name')
  [ "$role" = "backstage" ]
  [ "$sa" = "backstage" ]
}

@test "Postgres runs as a StatefulSet with its own PVC, not a bare Deployment" {
  replicas=$(resource StatefulSet backstage-postgres | yq '.spec.replicas')
  pvc_name=$(resource StatefulSet backstage-postgres | yq '.spec.volumeClaimTemplates[0].metadata.name')
  [ "$replicas" = "1" ]
  [ "$pvc_name" = "data" ]
}

@test "Postgres gets its password from the backstage Secret, and a fixed non-secret user/db" {
  password_name=$(resource StatefulSet backstage-postgres | yq '.spec.template.spec.containers[0].env[] | select(.name == "POSTGRES_PASSWORD") | .valueFrom.secretKeyRef.name')
  user=$(resource StatefulSet backstage-postgres | yq '.spec.template.spec.containers[0].env[] | select(.name == "POSTGRES_USER") | .value')
  [ "$password_name" = "backstage" ]
  [ "$user" = "backstage" ]
}

@test "Postgres Service is headless, matching the StatefulSet's serviceName" {
  cluster_ip=$(resource Service backstage-postgres | yq '.spec.clusterIP')
  service_name=$(resource StatefulSet backstage-postgres | yq '.spec.serviceName')
  [ "$cluster_ip" = "None" ]
  [ "$service_name" = "backstage-postgres" ]
}

@test "Ingress routes backstage.morrisons.site to the backend Service on port 7007" {
  host=$(resource Ingress backstage | yq '.spec.rules[0].host')
  port=$(resource Ingress backstage | yq '.spec.rules[0].http.paths[0].backend.service.port.number')
  [ "$host" = "backstage.morrisons.site" ]
  [ "$port" = "7007" ]
}
