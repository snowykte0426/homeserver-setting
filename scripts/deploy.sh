#!/usr/bin/env bash
# 저장소 변경분을 홈서버에 반영한다. self-hosted runner 에서 checkout 루트 기준으로 실행된다.
# 사용: scripts/deploy.sh <before-sha> <after-sha>
#
# 서버 파일이 저장소의 이전 버전(before)과 다르면 누군가 서버에서 직접 고친 것으로 보고 중단한다.
# 이 경우 scripts/pull-from-server.sh 로 서버 내용을 먼저 저장소에 반영한 뒤 다시 push 한다.
#
# macOS 기본 bash(3.2)에서 돌아야 하므로 배열/연관배열을 쓰지 않는다.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

before=${1:-}
after=${2:?after sha 가 필요합니다}

nginx_dir=/opt/homebrew/etc/nginx
startup_dir="$HOME/Downloads/homeserver-setting/scripts"
agent_dir="$HOME/Library/LaunchAgents"
notifier_dir="$HOME/Downloads/boot-notifier"
minecraft_dir="$HOME/Downloads/minecraft-server"
backup_dir="$HOME/Downloads/homeserver-setting/backups/$(date +%Y%m%d-%H%M%S)"

# 저장소 경로 -> 서버 경로. 비어 있으면 배포 대상이 아니다.
target_of() {
    case $1 in
        *.example) ;;
        nginx/nginx.conf) echo "$nginx_dir/nginx.conf" ;;
        nginx/servers/*.conf) echo "$nginx_dir/servers/${1#nginx/servers/}" ;;
        scripts/docker-startup.sh) echo "$startup_dir/docker-startup.sh" ;;
        scripts/launchd-dispatch.sh) echo "$startup_dir/launchd-dispatch.sh" ;;
        launchd/actions.runner.*.plist) echo "$agent_dir/${1#launchd/}" ;;
        launchd/site.kimtaeeun.docker-startup.plist) echo "$agent_dir/site.kimtaeeun.docker-startup.plist" ;;
        apps/boot-notifier/*) echo "$notifier_dir/${1#apps/boot-notifier/}" ;;
        services/minecraft/docker-compose.yml) echo "$minecraft_dir/docker-compose.yml" ;;
    esac
}

if [[ -n $before ]] && git cat-file -e "$before^{commit}" 2>/dev/null; then
    changed=$(git diff --name-only --diff-filter=ACMR "$before" "$after")
    deleted=$(git diff --name-only --diff-filter=D "$before" "$after")
else
    echo "이전 커밋을 찾을 수 없어 전체 파일을 대상으로 합니다."
    before=
    changed=$(git ls-files)
    deleted=
fi

for path in $deleted; do
    target=$(target_of "$path")
    [[ -n $target ]] && echo "::warning::$path 가 저장소에서 삭제됐지만 서버 파일($target)은 지우지 않습니다."
done

targets=
for path in $changed; do
    target=$(target_of "$path")
    [[ -n $target ]] && targets="$targets$path"$'\n'
done
# GitHub Secret 으로 관리하는 서버 전용 설정 파일. 비어 있으면 서버 파일을 그대로 둔다.
# $(...) 로 끝의 개행을 정규화해서 내용이 같으면 재배포하지 않는다.
notifier_env=$(printf '%s' "${BOOT_NOTIFIER_ENV:-}")
notifier_env_changed=0
if [[ -n $notifier_env && $notifier_env != "$(cat "$notifier_dir/config.env" 2>/dev/null)" ]]; then
    notifier_env_changed=1
fi

if [[ -z $targets && $notifier_env_changed == 0 ]]; then
    echo "배포할 변경이 없습니다."
    exit 0
fi

# 1) 드리프트 검사: 하나라도 걸리면 아무것도 바꾸지 않는다.
drift=0
while IFS= read -r path; do
    [[ -z $path ]] && continue
    target=$(target_of "$path")
    [[ -e $target ]] || continue
    cmp -s "$path" "$target" && continue
    if [[ -n $before ]] && git cat-file -e "$before:$path" 2>/dev/null &&
        git show "$before:$path" | cmp -s - "$target"; then
        continue
    fi
    echo "::error::드리프트: $target 가 서버에서 직접 수정됐습니다. pull-from-server.sh 로 먼저 반영하세요."
    drift=1
done <<< "$targets"
[[ $drift == 0 ]] || exit 1

# 2) 백업 후 반영
nginx_changed=0 plist_changed=0 runner_plist_changed=0 notifier_changed=0 minecraft_changed=0
while IFS= read -r path; do
    [[ -z $path ]] && continue
    target=$(target_of "$path")
    cmp -s "$path" "$target" 2>/dev/null && continue
    if [[ -e $target ]]; then
        mkdir -p "$backup_dir/$(dirname "$path")"
        cp -p "$target" "$backup_dir/$path"
    fi
    mkdir -p "$(dirname "$target")"
    # 기존 파일이 있으면 cp 는 대상의 권한을 유지한다.
    cp "$path" "$target"
    echo "반영: $path -> $target"
    case $path in
        nginx/*) nginx_changed=1 ;;
        launchd/actions.runner.*) runner_plist_changed=1 ;;
        launchd/*) plist_changed=1 ;;
        apps/boot-notifier/*) notifier_changed=1 ;;
        services/minecraft/*) minecraft_changed=1 ;;
    esac
done <<< "$targets"

if [[ $notifier_env_changed == 1 ]]; then
    if [[ -e $notifier_dir/config.env ]]; then
        mkdir -p "$backup_dir/apps/boot-notifier"
        cp -p "$notifier_dir/config.env" "$backup_dir/apps/boot-notifier/config.env"
    fi
    (umask 077 && printf '%s\n' "$notifier_env" > "$notifier_dir/config.env")
    echo "반영: secrets.BOOT_NOTIFIER_ENV -> $notifier_dir/config.env"
    notifier_changed=1
fi

# 3) 서비스 적용
if [[ $nginx_changed == 1 ]]; then
    if ! nginx -t; then
        echo "::error::nginx -t 실패, 이전 설정으로 되돌립니다."
        for backup in "$backup_dir"/nginx/nginx.conf "$backup_dir"/nginx/servers/*.conf; do
            [[ -e $backup ]] && cp "$backup" "$nginx_dir/${backup#"$backup_dir"/nginx/}"
        done
        nginx -t
        exit 1
    fi
    nginx -s reload
    echo "nginx 재적용 완료"
fi

if [[ $plist_changed == 1 ]]; then
    plist="$agent_dir/site.kimtaeeun.docker-startup.plist"
    launchctl bootout "gui/$(id -u)/site.kimtaeeun.docker-startup" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
    echo "docker-startup LaunchAgent 재등록 완료"
fi

if [[ $runner_plist_changed == 1 ]]; then
    # 이 작업 자체가 runner 위에서 돌고 있으므로 여기서 재시작하지 않는다.
    echo "::warning::runner plist 가 바뀌었습니다. 서버에서 launchctl kickstart -k gui/\$(id -u)/actions.runner.snowykte0426-homeserver-setting.homeserver 로 재시작하세요."
fi

if [[ $notifier_changed == 1 ]]; then
    if [[ ! -f $notifier_dir/config.env ]]; then
        echo "::error::$notifier_dir/config.env 가 없습니다."
        exit 1
    fi
    docker build -t boot-notifier "$notifier_dir"
    docker rm -f boot-notifier >/dev/null 2>&1 || true
    docker run -d --name boot-notifier --restart unless-stopped boot-notifier
    echo "boot-notifier 재배포 완료"
fi

if [[ $minecraft_changed == 1 ]]; then
    (cd "$minecraft_dir" && docker compose up -d)
    echo "minecraft compose 적용 완료"
fi

echo "배포 완료 (백업: $backup_dir)"
