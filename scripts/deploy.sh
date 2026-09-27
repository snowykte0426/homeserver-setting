#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

before=${1:-}
after=${2:?after sha 가 필요합니다}

nginx_dir=/opt/homebrew/etc/nginx
startup_dir="$HOME/Downloads/homeserver-setting/scripts"
agent_dir="$HOME/Library/LaunchAgents"
notifier_dir="$HOME/Downloads/boot-notifier"
minecraft_dir="$HOME/Downloads/minecraft-server"
mail_dir="$HOME/Downloads/mailserver"
backup_dir="$HOME/Downloads/homeserver-setting/backups/$(date +%Y%m%d-%H%M%S)"

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
        services/mail/docker-compose.yml) echo "$mail_dir/docker-compose.yml" ;;
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
notifier_env=$(printf '%s' "${BOOT_NOTIFIER_ENV:-}")
notifier_env_changed=0
if [[ -n $notifier_env && $notifier_env != "$(cat "$notifier_dir/config.env" 2>/dev/null)" ]]; then
    notifier_env_changed=1
fi

if [[ -z $targets && $notifier_env_changed == 0 ]]; then
    echo "배포할 변경이 없습니다."
    exit 0
fi

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

nginx_changed=0 plist_changed=0 runner_plist_changed=0 notifier_changed=0 minecraft_changed=0 mail_changed=0
while IFS= read -r path; do
    [[ -z $path ]] && continue
    target=$(target_of "$path")
    cmp -s "$path" "$target" 2>/dev/null && continue
    if [[ -e $target ]]; then
        mkdir -p "$backup_dir/$(dirname "$path")"
        cp -p "$target" "$backup_dir/$path"
    fi
    mkdir -p "$(dirname "$target")"
    cp "$path" "$target"
    echo "반영: $path -> $target"
    case $path in
        nginx/*) nginx_changed=1 ;;
        launchd/actions.runner.*) runner_plist_changed=1 ;;
        launchd/*) plist_changed=1 ;;
        apps/boot-notifier/*) notifier_changed=1 ;;
        services/minecraft/*) minecraft_changed=1 ;;
        services/mail/*) mail_changed=1 ;;
    esac
done <<< "$targets"

if [[ $notifier_env_changed == 1 ]]; then
    if [[ -e $notifier_dir/config.env ]]; then
        mkdir -p "$backup_dir/apps/boot-notifier"
        cp -p "$notifier_dir/config.env" "$backup_dir/apps/boot-notifier/config.env"
    fi
    (umask 077 && printf '%s\n' "$notifier_env" > "$notifier_dir/config.env")
    chmod 600 "$notifier_dir/config.env"
    echo "반영: secrets.BOOT_NOTIFIER_ENV -> $notifier_dir/config.env"
    notifier_changed=1
fi

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

if [[ $mail_changed == 1 ]]; then
    (cd "$mail_dir" && docker compose up -d)
    echo "mailserver compose 적용 완료"
fi

echo "배포 완료 (백업: $backup_dir)"
