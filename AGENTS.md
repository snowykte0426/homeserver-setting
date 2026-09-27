# 홈서버 운영 노트

작업 전에 읽을 것. 공개 저장소이므로 비밀번호, 토큰, 웹훅 URL 은 여기에도 적지 않는다.

**서버 구성, 컨테이너, 경로, 라우팅, CD, 시크릿 중 하나라도 바꾸면 같은 커밋에서 이 문서도 반드시 갱신한다.** 저장소 파일을 바꾸면서 이 문서를 건드리지 않으면 Deploy 워크플로가 경고를 남긴다.

## 서버

- Mac mini (macOS 26, Apple Silicon), 사용자 `snowykte0426`, 도메인 `kimtaeeun.site`
- DNS 는 Cloudflare. `kimtaeeun.site`, `www` 는 프록시(Flexible TLS, 서버는 80 만 받음), `mc`, `db` 는 DNS 전용
- 가정용 회선이라 외부 IP 가 바뀔 수 있다. 바뀌면 boot-notifier 가 Discord 로 알린다
- Docker Desktop, Homebrew nginx(`brew services`), 원격 로그인(SSH) 사용

## 규칙

- 서버에 배포하는 모든 프로젝트는 `~/Downloads/<project>` 아래에 둔다. 그 밖에 있으면 규칙 위반이므로 옮기고 해당 프로젝트의 배포 경로도 고친다
- 커밋에 Claude co-author 트레일러를 넣지 않는다
- 이 저장소가 서버 설정의 기준이다. 서버에서 직접 고쳤다면 `scripts/pull-from-server.sh` 로 먼저 반영한 뒤 push 한다

## CD

- `.github/workflows/deploy.yml`: `main` push 또는 `workflow_dispatch` 시 self-hosted runner(`homeserver` 라벨)에서 `scripts/deploy.sh` 실행
- push 는 이전 커밋과의 diff 만, 수동 실행은 전체 파일을 서버와 비교해 다른 것만 반영
- 서버 파일이 저장소 직전 버전과 다르면(드리프트) 아무것도 바꾸지 않고 실패한다
- 덮어쓴 파일은 `~/Downloads/homeserver-setting/backups/<시각>/` 에 백업
- 저장소 경로와 서버 경로 대응은 `scripts/deploy.sh` 의 `target_of`, 동기화는 `scripts/pull-from-server.sh` 참고
- runner plist 가 바뀌면 복사만 하고 재시작은 서버에서 `launchctl kickstart -k gui/$(id -u)/actions.runner.snowykte0426-homeserver-setting.homeserver`
- `services/infra`(mysql/redis compose 재구성본)와 `launchd/homebrew.mxcl.nginx.plist` 는 참고용이라 배포하지 않는다

## 시크릿

값은 GitHub Secrets(`snowykte0426/homeserver-setting`)와 로컬의 gitignore 된 파일에만 둔다.

| Secret | 내용 | 로컬 사본 | CD 반영 |
| --- | --- | --- | --- |
| `BOOT_NOTIFIER_ENV` | boot-notifier `config.env` 전체 | `apps/boot-notifier/config.env` | O |
| `MYSQL_ROOT_PASSWORD` | mysql 컨테이너 root 비밀번호 | `services/infra/.env` | X (보관만) |
| `REDIS_PASSWORD` | redis `--requirepass` 값 | `services/infra/.env` | X (보관만) |

외부 프로젝트의 시크릿(nxdi `.env`, axia `config/server.env`, claude-trigger `trigger.env`, sandrone env 등)은 각 저장소의 GitHub Secrets 와 서버의 해당 프로젝트 디렉터리에 있다.

- `BOOT_NOTIFIER_ENV`: 값이 서버 파일과 다르면 0600 으로 다시 쓰고 boot-notifier 재배포(부팅 알림 1회 발송). 비어 있으면 서버 파일 유지
- 변경: `gh secret set BOOT_NOTIFIER_ENV -R snowykte0426/homeserver-setting < apps/boot-notifier/config.env` 후 `gh workflow run deploy.yml -R snowykte0426/homeserver-setting`

## macOS TCC 와 ~/Downloads

- launchd 가 직접 띄운 프로세스는 `~/Downloads` 에 접근하지 못한다(`Operation not permitted`, exit 126). SSH 세션은 전체 디스크 접근 권한이 있어 가능
- 그래서 runner 와 docker-startup LaunchAgent 는 `ssh -i ~/.ssh/launchd_localhost localhost <runner|docker-startup>` 로 실행한다
- `authorized_keys` 에 `restrict,pty,from="127.0.0.1,::1",command=".../scripts/launchd-dispatch.sh"` 로 등록되어 두 명령만 허용
- `./svc.sh install` 을 다시 하면 runner plist 가 원래 형태로 덮어써지므로 `launchd/` 의 파일로 복구한다

## 컨테이너

| 이름 | 이미지 | 포트 | 관리 |
| --- | --- | --- | --- |
| my-resume | `my-resume:latest` | 127.0.0.1:4173 | snowykte0426/my-resume CD → `~/Downloads/my-resume` |
| nxdi-server | `nxdi-server:latest` | 127.0.0.1:10104 | it-play/nxdi CD → `~/Downloads/nxdi` (compose `deploy/compose.yml`) |
| sandrone | `ghcr.io/it-play/sandrone-code-review-bot` | 0.0.0.0:10105 | it-play/sandrone-code-review-bot CD → `~/Downloads/sandrone` |
| claude-trigger | `claude-trigger` | - | it-play/claude-lniter CD → `~/Downloads/Claude-Initer` |
| boot-notifier | `boot-notifier` | - | 이 저장소 `apps/boot-notifier` → `~/Downloads/boot-notifier` |
| minecraft | `itzg/minecraft-server` (Fabric) | 127.0.0.1:25565 | 이 저장소 `services/minecraft` → `~/Downloads/minecraft-server` |
| mysql | `mysql:8.0` | 0.0.0.0:3306 | 수동 실행, 볼륨 `kimtaeeun-infra_mysql_data` |
| redis | `redis:7-alpine` | 0.0.0.0:6379 | 수동 실행, 볼륨 `kimtaeeun-infra_redis_data` |

axia(`~/Downloads/axia`, 127.0.0.1:18080)는 외부 프로젝트로 별도 배포하며 현재 컨테이너는 없다.
readygsm 은 2026-09-27 에 내렸다(컨테이너와 네트워크 삭제). `~/Downloads/readygsm-server` 디렉터리와 `deploy-app` 이미지는 남아 있다.
재부팅 시 `scripts/docker-startup.sh` 가 Docker 준비(최대 300초)를 기다린 뒤 위 컨테이너를 모두 켠다. `docker stop` 으로 멈춘 `unless-stopped` 컨테이너는 Docker 가 자동으로 다시 켜지 않으므로, 컨테이너를 추가하면 이 스크립트 목록에도 넣는다. 재부팅 전에는 컨테이너를 `docker stop` 으로 정상 종료한 뒤 전원을 끈다.

## nginx 라우팅

| 경로 | 업스트림 |
| --- | --- |
| `/` | my-resume :4173 |
| `/nxdi-api/` | nxdi-server :10104 |
| `/sandrone/` | sandrone :10105 |
| `/axia/api/` | axia :18080 |
| TCP 25565 (stream) | minecraft |

`kimtaeeun.conf` 의 `# >>> name >>>` ~ `# <<< name <<<` 블록은 외부 배포 스크립트가 표식을 기준으로 교체한다(nxdi 의 `server/deploy/scripts/apply_nginx.sh` 등). 표식과 블록 내용은 지우거나 바꾸지 않는다. 바꿀 때는 해당 프로젝트 쪽도 같이 고친다.

## 남은 이슈

- it-play 조직 저장소(nxdi, sandrone, claude-lniter)의 GitHub Actions 가 push 에 실행되지 않고 수동 실행은 HTTP 500. sandrone 은 새 경로로 아직 재배포되지 않아 compose 라벨이 `/tmp/sandrone-deploy` 로 남아 있다
- mysql 3306, redis 6379 가 0.0.0.0 으로 열려 있음. redis 비밀번호가 컨테이너 command 에 평문으로 있음. SSH 비밀번호 로그인 사용 중
