# gcloud session helpers — keep refresh tokens off disk between work sessions.
#
# gcloud has no macOS Keychain backend, so the next-best thing is explicit
# lifecycle: log in when you start working, revoke + delete the SQLite stores
# when you stop. Cost: one browser auth per work session.

gcloud_login() {
  gcloud auth login --update-adc "$@"
}

gcloud_logout() {
  gcloud auth revoke --all 2>/dev/null
  rm -f \
    "$HOME/.config/gcloud/credentials.db" \
    "$HOME/.config/gcloud/access_tokens.db" \
    "$HOME/.config/gcloud/application_default_credentials.json" \
    "$HOME/.config/gcloud/legacy_credentials"/*/*.json 2>/dev/null
  rmdir "$HOME/.config/gcloud/legacy_credentials"/* 2>/dev/null
  rmdir "$HOME/.config/gcloud/legacy_credentials" 2>/dev/null
  echo "gcloud session ended; credential stores removed"
}

gcloud_status() {
  local active
  active=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)
  if [ -n "$active" ]; then
    echo "active: $active"
    [ -f "$HOME/.config/gcloud/credentials.db" ] && \
      echo "credentials.db: $(stat -f '%z bytes, modified %Sm' "$HOME/.config/gcloud/credentials.db")"
  else
    echo "no active gcloud session"
  fi
}
