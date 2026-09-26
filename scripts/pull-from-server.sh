#!/usr/bin/env bash
# 홈서버의 현재 설정 파일을 이 저장소로 가져온다. 시크릿 파일은 가져오지 않는다.
# 사용: HOMESERVER=user@host ./scripts/pull-from-server.sh
set -euo pipefail

host=${HOMESERVER:?HOMESERVER=user@host 를 지정하세요}
repo=$(cd "$(dirname "$0")/.." && pwd)

# repo 경로 <- 서버 경로
files=(
  "nginx/nginx.conf|/opt/homebrew/etc/nginx/nginx.conf"
  "nginx/servers/kimtaeeun.conf|/opt/homebrew/etc/nginx/servers/kimtaeeun.conf"
  "launchd/site.kimtaeeun.docker-startup.plist|Library/LaunchAgents/site.kimtaeeun.docker-startup.plist"
  "launchd/homebrew.mxcl.nginx.plist|Library/LaunchAgents/homebrew.mxcl.nginx.plist"
  "scripts/docker-startup.sh|Downloads/homeserver-setting/scripts/docker-startup.sh"
  "services/minecraft/docker-compose.yml|Downloads/minecraft-server/docker-compose.yml"
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
