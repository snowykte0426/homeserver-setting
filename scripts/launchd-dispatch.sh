#!/bin/bash
set -euo pipefail

case ${SSH_ORIGINAL_COMMAND:-} in
    runner)
        pkill -f 'bin/RunnerService.js' || true
        pkill -f 'bin/Runner.Listener' || true
        cd "$HOME/Downloads/actions-runner"
        export ACTIONS_RUNNER_SVC=1
        exec ./runsvc.sh
        ;;
    docker-startup)
        exec /bin/bash "$HOME/Downloads/homeserver-setting/scripts/docker-startup.sh"
        ;;
    *)
        echo "unknown command: ${SSH_ORIGINAL_COMMAND:-}" >&2
        exit 1
        ;;
esac
