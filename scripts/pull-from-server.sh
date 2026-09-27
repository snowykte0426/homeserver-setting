#!/usr/bin/env bash
set -euo pipefail

host=${HOMESERVER:?HOMESERVER=user@host 를 지정하세요}
repo=$(cd "$(dirname "$0")/.." && pwd)

files=(
  "nginx/nginx.conf|/opt/homebrew/etc/nginx/nginx.conf"
  "nginx/servers/kimtaeeun.conf|/opt/homebrew/etc/nginx/servers/kimtaeeun.conf"
  "launchd/site.kimtaeeun.docker-startup.plist|Library/LaunchAgents/site.kimtaeeun.docker-startup.plist"
  "launchd/homebrew.mxcl.nginx.plist|Library/LaunchAgents/homebrew.mxcl.nginx.plist"
  "launchd/actions.runner.snowykte0426-homeserver-setting.homeserver.plist|Library/LaunchAgents/actions.runner.snowykte0426-homeserver-setting.homeserver.plist"
  "scripts/launchd-dispatch.sh|Downloads/homeserver-setting/scripts/launchd-dispatch.sh"
  "scripts/docker-startup.sh|Downloads/homeserver-setting/scripts/docker-startup.sh"
  "services/minecraft/docker-compose.yml|Downloads/minecraft-server/docker-compose.yml"
  "services/mail/docker-compose.yml|Downloads/mailserver/docker-compose.yml"
)

for entry in "${files[@]}"; do
  local_path=${entry%%|*}
  remote_path=${entry#*|}
  mkdir -p "$repo/$(dirname "$local_path")"
  ssh "$host" "cat \"$remote_path\"" > "$repo/$local_path"
done

ssh "$host" 'tar -C ~/Downloads --exclude=config.env --exclude=__pycache__ --exclude=.DS_Store --exclude=last_ips.json -cf - boot-notifier' \
  | tar -C "$repo/apps" -xf -

git -C "$repo" status --short
