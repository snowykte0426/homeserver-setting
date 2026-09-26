#!/bin/bash
# launchd 가 `ssh localhost <name>` 으로 호출하는 forced command (authorized_keys 의 command=).
# macOS TCC 때문에 launchd 가 직접 띄운 프로세스는 ~/Downloads 에 접근할 수 없다.
# 원격 로그인(sshd)에는 전체 디스크 접근 권한이 있으므로 sshd 아래에서 실행되게 우회한다.
set -euo pipefail

case ${SSH_ORIGINAL_COMMAND:-} in
    runner)
        # 이전 ssh 세션이 끊기며 남긴 runner 프로세스 정리
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
