#!/usr/bin/env bash
# The deployment directory contains the Compose files, nonsecret .env, and private config/server.env.
set +x
set +v
set -euo pipefail

if [[ $# != 1 || $1 != /* ]]; then
    printf '%s\n' 'Usage: start.sh ABSOLUTE_DEPLOYMENT_DIRECTORY' >&2
    exit 2
fi

axia_deploy_directory=$1
cd "$axia_deploy_directory"
export AXIA_ENV_FILE="$axia_deploy_directory/config/server.env"
bash "$axia_deploy_directory/preflight.sh" "$AXIA_ENV_FILE"

# Never resolve/print the environment, pull a mutable tag, or build on this shared production host.
axia_docker=$(command -v docker || true)
if [[ -z $axia_docker && -x /usr/local/bin/docker ]]; then
    axia_docker=/usr/local/bin/docker
fi
if [[ -z $axia_docker ]]; then
    printf '%s\n' 'Docker is unavailable in this session.' >&2
    exit 1
fi
axia_compose=("$axia_docker" compose --env-file "$axia_deploy_directory/.env" -f "$axia_deploy_directory/docker-compose.yml")
if [[ -f $axia_deploy_directory/compose.host.yml ]]; then
    axia_compose+=(-f "$axia_deploy_directory/compose.host.yml")
fi
"${axia_compose[@]}" config --quiet
"${axia_compose[@]}" up --detach --no-build --pull never server

axia_health_matches() {
    local axia_probe_response
    axia_probe_response=$(curl --fail --silent --max-time 2 --write-out '\n%{http_code}' "$1") || return 1
    [[ $axia_probe_response == "$2"$'\n200' ]]
}

for ((axia_attempt = 0; axia_attempt < 30; axia_attempt++)); do
    if axia_health_matches http://127.0.0.1:18080/health/live alive &&
        axia_health_matches http://127.0.0.1:18080/health/ready ready; then
        printf '%s\n' 'Axia is live and database-ready; provider login and synchronization still require verification.'
        exit 0
    fi
    sleep 2
done

printf '%s\n' 'Axia did not become ready. Inspect its private server logs; no other service was restarted.' >&2
exit 1
