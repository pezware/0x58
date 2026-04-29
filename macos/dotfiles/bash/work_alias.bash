alias prettier="prettier --config ~/.config/prettierrc"

### K8s

alias ,getpodver="kubectl get pods -n core -o jsonpath='{range .items[*]}{.metadata.name}{\" : \"}{range .spec.containers[*]}{.image}{\" \"}{end}{\"\n\"}{end}'"
alias ,govicommonplace="vim ~/src/iden2/local-infra-doc/devlog.md"

### K8s
alias ,getpodver="kubectl get pods -n core -o jsonpath='{range .items[*]}{.metadata.name}{\" : \"}{range .spec.containers[*]}{.image}{\" \"}{end}{\"\n\"}{end}'"

alias k="kubectl"
alias ,gcpfleet="gcloud container fleet memberships get-credentials iden2-staging-gke --location=europe-west4 --project=iden2-ops-staging"
