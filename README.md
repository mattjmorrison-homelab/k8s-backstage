# k8s-backstage

Helm chart and deployment manifests for Backstage (this homelab's
dependency/relationship catalog, todo #41) -- namespace, the Backstage
Deployment/Service, a hand-rolled Postgres StatefulSet, the OpenBao-backed
ExternalSecrets, and the Ingress.

Split from [app-backstage](https://github.com/mattjmorrison-homelab/app-backstage)
(source + CI), same split as every other app in this cluster: this repo's
changes sync via ArgoCD immediately on push, while app-backstage's changes
go through the full build/test/publish pipeline.

Bare-app pass only -- no catalog discovery, CI validation, or plugins yet.
See todo #41 for what's deliberately not scoped.
