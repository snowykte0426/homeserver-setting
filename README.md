# homeserver-setting

`kimtaeeun.site` 홈서버(Mac mini, macOS) 설정과 구동 파일 모음.
자체 저장소가 있는 외부 프로젝트(my-resume, readygsm-server, Claude-Initer, nxdi, axia, sandrone 등)는 여기서 관리하지 않는다.

> 공개 저장소다. 웹훅 URL, 비밀번호, `.env`, 인증서는 커밋하지 않는다. 각 디렉터리의 `*.example` 을 참고.

## 구조

| 저장소 경로 | 서버 경로 | 설명 |
| --- | --- | --- |
| `nginx/nginx.conf` | `/opt/homebrew/etc/nginx/nginx.conf` | 메인 설정 + Minecraft TCP stream(25565) |
| `nginx/servers/kimtaeeun.conf` | `/opt/homebrew/etc/nginx/servers/kimtaeeun.conf` | kimtaeeun.site 리버스 프록시 |
| `launchd/homebrew.mxcl.nginx.plist` | `~/Library/LaunchAgents/` | `brew services` 가 만든 nginx 에이전트 |
| `launchd/site.kimtaeeun.docker-startup.plist` | `~/Library/LaunchAgents/` | 로그인 시 `docker-startup.sh` 실행 |
| `scripts/docker-startup.sh` | `~/Library/Application Support/NXDI/docker-startup.sh` | Docker 준비 대기 후 컨테이너 기동 |
| `apps/boot-notifier/` | `~/Downloads/boot-notifier/` | 부팅 알림 + IP 변경 감지 → Discord 웹훅 |
| `services/minecraft/` | `~/minecraft-server/` | Fabric Minecraft 서버 (`itzg/minecraft-server`) |
| `services/infra/` | (compose 파일 없음) | mysql/redis, `docker inspect` 로 재구성 |

## 라우팅 (nginx → 컨테이너)

| 경로 | 업스트림 | 컨테이너 |
| --- | --- | --- |
| `/` | `127.0.0.1:4173` | my-resume |
| `/ready-gsm/` | `localhost:10101` | readygsm-app |
| `/nxdi-api/` | `127.0.0.1:10104` | nxdi-server |
| `/sandrone/` | `127.0.0.1:10105` | sandrone |
| `/axia/api/` | `127.0.0.1:18080` | axia server |
| TCP `25565` | `127.0.0.1:25565` | minecraft |

TLS 는 Cloudflare(Flexible)가 처리하고 서버는 80 만 받는다.

## boot-notifier

컨테이너가 뜰 때 부팅 알림을 보내고, 이후 `IP_CHECK_INTERVAL` 초마다 외부(ipify)/내부 IP를 확인해 바뀌면 알린다.

```sh
cd apps/boot-notifier
cp config.env.example config.env   # 웹훅 URL 입력
docker build -t boot-notifier .
docker run -d --name boot-notifier --restart unless-stopped boot-notifier
```

`config.env` 는 이미지에 포함되므로 이미지를 외부 레지스트리에 올리지 않는다.

## 서버 → 저장소 동기화

```sh
HOMESERVER=snowykte0426@<server-ip> ./scripts/pull-from-server.sh
git diff
```

## CD (저장소 → 서버)

`main` 에 push 하면 `.github/workflows/deploy.yml` 이 홈서버의 self-hosted runner(`homeserver` 라벨)에서
`scripts/deploy.sh` 를 실행해 바뀐 파일만 반영한다.

| 변경 | 동작 |
| --- | --- |
| `nginx/**` | 복사 → `nginx -t` → `nginx -s reload` (실패 시 백업으로 복구) |
| `scripts/docker-startup.sh` | 복사 |
| `launchd/site.kimtaeeun.docker-startup.plist` | 복사 → `launchctl bootout/bootstrap` |
| `apps/boot-notifier/**` | 복사 → 이미지 빌드 → 컨테이너 재생성 (부팅 알림이 한 번 더 감) |
| `services/minecraft/docker-compose.yml` | 복사 → `docker compose up -d` |

- `services/infra`, `launchd/homebrew.mxcl.nginx.plist` 는 참고용이라 배포하지 않는다.
- 서버 파일이 저장소의 직전 버전과 다르면(서버에서 직접 수정) 아무것도 바꾸지 않고 실패한다.
  `pull-from-server.sh` 로 서버 내용을 먼저 커밋한 뒤 다시 push 한다.
- 덮어쓴 파일은 서버의 `~/.homeserver-setting/backups/<시각>/` 에 남는다.
- 공개 저장소라 외부 기여자의 fork PR 워크플로는 승인 없이 돌지 않도록 설정돼 있다.
