#!/bin/bash
set -euo pipefail
# Run from any directory. Requires gh authentication with repository administration access.
repository="aljaroudi/Muntathir"
root="$(cd "$(dirname "$0")/../.." && pwd)"
runner="$root/.local-ci/runner"
name="Muntathir-local-Mac"
mkdir -p "$runner"
cd "$runner"
if [ ! -f .runner ]; then
  release="$(gh api repos/actions/runner/releases/latest)"
  asset="$(printf '%s' "$release" | /usr/bin/python3 -c 'import json,sys; r=json.load(sys.stdin); print(next(a["name"] for a in r["assets"] if "osx-arm64" in a["name"] and a["name"].endswith(".tar.gz")))')"
  digest="$(printf '%s' "$release" | /usr/bin/python3 -c 'import json,sys; r=json.load(sys.stdin); print(next(a.get("digest", "") for a in r["assets"] if "osx-arm64" in a["name"] and a["name"].endswith(".tar.gz")))')"
  case "$digest" in sha256:*) ;; *) echo "Runner release lacks SHA-256 digest; refusing unverified download" >&2; exit 1 ;; esac
  tag="$(printf '%s' "$release" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
  gh release download "$tag" --repo actions/runner --pattern "$asset" --dir . --clobber
  printf '%s  %s\n' "${digest#sha256:}" "$asset" | shasum -a 256 -c -
  tar xzf "$asset"
  rm "$asset"
  token="$(gh api --method POST "repos/$repository/actions/runners/registration-token" --jq .token)"
  ./config.sh --unattended --url "https://github.com/$repository" --token "$token" \
    --name "$name" --labels muntathir-deploy --work _work
  unset token
fi
service="$HOME/Library/LaunchAgents/actions.runner.aljaroudi-Muntathir.$name.plist"
if [ ! -f "$service" ]; then ./svc.sh install; fi
# Share the logged-in GUI security session so the service can access signing identities.
if /usr/libexec/PlistBuddy -c 'Print :SessionCreate' "$service" >/dev/null 2>&1; then
  ./svc.sh stop
  /usr/libexec/PlistBuddy -c 'Delete :SessionCreate' "$service"
fi
./svc.sh start
./svc.sh status
