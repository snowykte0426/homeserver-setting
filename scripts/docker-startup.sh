#!/bin/bash
# Docker 데몬이 준비될 때까지 대기 (최대 90초)
timeout=90
until /usr/local/bin/docker info &>/dev/null 2>&1; do
    if [ $timeout -le 0 ]; then
        echo "$(date): Docker daemon did not start in time." >&2
        exit 1
    fi
    sleep 3
    timeout=$((timeout - 3))
done

echo "$(date): Docker ready. Starting containers..."
/usr/local/bin/docker start my-resume mysql redis claude-trigger nxdi-server
sleep 20
/usr/local/bin/docker start boot-notifier
echo "$(date): Done."
