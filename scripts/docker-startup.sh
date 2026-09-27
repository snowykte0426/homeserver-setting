#!/bin/bash
timeout=300
until /usr/local/bin/docker info &>/dev/null 2>&1; do
    if [ $timeout -le 0 ]; then
        echo "$(date): Docker daemon did not start in time." >&2
        exit 1
    fi
    sleep 3
    timeout=$((timeout - 3))
done

echo "$(date): Docker ready. Starting containers..."
/usr/local/bin/docker start mysql redis my-resume nxdi-server sandrone claude-trigger minecraft
sleep 20
/usr/local/bin/docker start boot-notifier
echo "$(date): Done."
