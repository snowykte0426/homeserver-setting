# AGENTS.md: homeserver-setting

Config and run files for the home server behind `kimtaeeun.site`: nginx config, launchd agents, the `apps/boot-notifier` Python app, the minecraft, mail server, and webmail compose files, and a CD pipeline that applies them to the server. Read this file before making changes.

> **IMPORTANT: If you change server setup, containers, paths, routing, CD, or secrets, update this file in the same commit.** On push, the Deploy workflow warns when repo files change but `AGENTS.md` does not.

## Rules

- **This repo is public.** Never write passwords, tokens, webhook URLs, or other secret values anywhere in it, including this file. Secret *names* are fine.
- **Every project deployed to the server lives under `~/Downloads/<project>`.** Anything outside that is a violation. Move it, and fix that project's deploy path too.
- **Do not add Claude co-author trailers** (`Co-Authored-By: Claude ...`) to commits.
- **The repo is the source of truth for server config.** If something was edited directly on the server, sync it into the repo with `scripts/pull-from-server.sh` first, then push. Otherwise CD fails on drift.
- **Leave the `# >>> name >>>` ... `# <<< name <<<` blocks in `nginx/servers/kimtaeeun.conf` alone.** External deploy scripts (for example nxdi's `server/deploy/scripts/apply_nginx.sh`) find and replace them by these markers. Do not remove or edit the markers or the block contents. If a change is needed, change the owning project too.
- **When you add a container, add it to the `docker start` list in `scripts/docker-startup.sh`** (see [Startup](#startup-and-reboot)).
- **Containers reach mysql and redis only through `host.docker.internal:3306` and `host.docker.internal:6379`** (the published host ports). Do not use a shared Docker network or container-name addressing. Each compose project uses only its own default network.
- **Publishing mysql 3306 and redis 6379 on 0.0.0.0 is intentional** (external access through `db.kimtaeeun.site`). Do not report it as a security issue.

## Commands

```sh
# Sync server-side edits into the repo (run locally, then commit and push)
HOMESERVER=user@host scripts/pull-from-server.sh

# Rotate the boot-notifier config, then run a full deploy
gh secret set BOOT_NOTIFIER_ENV -R snowykte0426/homeserver-setting < apps/boot-notifier/config.env
gh workflow run deploy.yml -R snowykte0426/homeserver-setting

# Restart the Actions runner on the server after its plist changes (CD does not restart it)
launchctl kickstart -k gui/$(id -u)/actions.runner.snowykte0426-homeserver-setting.homeserver
```

## CD

`.github/workflows/deploy.yml` runs `scripts/deploy.sh` on the self-hosted runner (label `homeserver`) on every push to `main` and on `workflow_dispatch`.

- **Scope:** a push applies only the diff since the previous commit. A manual run (or a push whose previous commit is missing) compares every tracked file with the server.
- **Drift check:** if a server file differs from both the new version and the previous repo version, the run changes nothing and fails. Fix this with `pull-from-server.sh`. A manual run has no previous version to compare against, so any existing server file that differs from the repo counts as drift. In practice a manual run only creates missing files and applies `BOOT_NOTIFIER_ENV`.
- **Backups:** overwritten files are copied to `~/Downloads/homeserver-setting/backups/<timestamp>/`.
- **Deletions:** deleting a file from the repo does not delete it on the server. CD only prints a warning.
- **Post-deploy actions:** nginx changes run `nginx -t` and then `nginx -s reload` (if the test fails, the previous config is restored and the run fails). A docker-startup plist change re-bootstraps that LaunchAgent. boot-notifier changes rebuild and rerun its container. A minecraft, mail, or webmail compose change runs `docker compose up -d` in that directory. A runner plist change is only copied, so restart the runner manually (see [Commands](#commands)).
- The repo path to server path mapping is `target_of` in `scripts/deploy.sh`, and the reverse sync list is in `scripts/pull-from-server.sh`:

| Repo path | Server path |
| --- | --- |
| `nginx/nginx.conf`, `nginx/servers/*.conf` | `/opt/homebrew/etc/nginx/...` |
| `scripts/docker-startup.sh`, `scripts/launchd-dispatch.sh` | `~/Downloads/homeserver-setting/scripts/` |
| `launchd/actions.runner.*.plist`, `launchd/site.kimtaeeun.docker-startup.plist` | `~/Library/LaunchAgents/` |
| `apps/boot-notifier/*` (not `*.example`) | `~/Downloads/boot-notifier/` |
| `services/minecraft/docker-compose.yml` | `~/Downloads/minecraft-server/` |
| `services/mail/docker-compose.yml` | `~/Downloads/mailserver/` |
| `services/webmail/docker-compose.yml` | `~/Downloads/webmail/` |

These files are reference only and are **not deployed**: `services/infra` (a reconstructed mysql/redis compose) and `launchd/homebrew.mxcl.nginx.plist`.

## Secrets

Values live only in GitHub Secrets (`snowykte0426/homeserver-setting`) and in local gitignored files.

| Secret | Contents | Local copy | Applied by CD |
| --- | --- | --- | --- |
| `BOOT_NOTIFIER_ENV` | the whole boot-notifier `config.env` | `apps/boot-notifier/config.env` | Yes |
| `MYSQL_ROOT_PASSWORD` | mysql container root password | `services/infra/.env` | No (stored only) |
| `REDIS_PASSWORD` | redis `--requirepass` value | `services/infra/.env` | No (stored only) |
| `MAIL_ENV` | the whole mail server `.env` (Stalwart admin, `contact@` mailbox password, `RESEND_RELAY_KEY`) | `services/mail/.env` | No (stored only; server copy at `~/Downloads/mailserver/.env`) |
| `MAIL_RELAY_KEY` | Resend sending-only API key used as the SMTP relay password | `services/mail/.env` | No (stored only) |

- `BOOT_NOTIFIER_ENV`: if it differs from the server file, CD rewrites the file with mode 0600 and redeploys boot-notifier, which sends one boot notification. If the secret is empty, the server file is kept. To rotate it, see [Commands](#commands).
- Secrets for external projects (nxdi `.env`, axia `config/server.env`, claude-trigger `trigger.env`, sandrone env, and so on) are kept in each project's own GitHub Secrets and in that project's directory on the server.

## Server

- Mac mini (macOS 26, Apple Silicon), user `snowykte0426`, domain `kimtaeeun.site`.
- DNS is on Cloudflare. `kimtaeeun.site` and `www` are proxied (Flexible TLS, so the server listens on port 80 only). `mc` and `db` are DNS-only.
- It runs on a residential line, so the public IP can change. boot-notifier sends a Discord alert when it does.
- Runs Docker Desktop, Homebrew nginx (`brew services`), and Remote Login (SSH).

## macOS TCC and `~/Downloads`

- Processes started directly by launchd cannot access `~/Downloads` (`Operation not permitted`, exit 126). SSH sessions have Full Disk Access, so they can.
- As a workaround, the runner and docker-startup LaunchAgents run `ssh -i ~/.ssh/launchd_localhost localhost <runner|docker-startup>`.
- That key is registered in `authorized_keys` with `restrict,pty,from="127.0.0.1,::1",command=".../scripts/launchd-dispatch.sh"`, which allows only those two commands.
- Running `./svc.sh install` again overwrites the runner plist with the stock version. Restore it from the file in `launchd/`.

## Containers

| Name | Image | Port | Managed by |
| --- | --- | --- | --- |
| my-resume | `my-resume:latest` | 127.0.0.1:4173 | snowykte0426/my-resume CD → `~/Downloads/my-resume` |
| nxdi-server | `nxdi-server:latest` | 127.0.0.1:10104 | it-play/nxdi CD → `~/Downloads/nxdi` (compose `deploy/compose.yml`) |
| sandrone | `ghcr.io/it-play/sandrone-code-review-bot` | 0.0.0.0:10105 | it-play/sandrone-code-review-bot CD → `~/Downloads/sandrone` (compose) |
| claude-trigger | `claude-trigger` | none | it-play/claude-lniter CD → `~/Downloads/Claude-Initer` |
| boot-notifier | `boot-notifier` | none | this repo, `apps/boot-notifier` → `~/Downloads/boot-notifier` |
| minecraft | `itzg/minecraft-server` (Fabric) | 127.0.0.1:25565 | this repo, `services/minecraft` → `~/Downloads/minecraft-server` |
| mailserver | `stalwartlabs/stalwart:v0.16` | 127.0.0.1:10025/10465/10993/10443 (public 25/465/993/443 via nginx), admin 127.0.0.1:18080 | this repo, `services/mail` → `~/Downloads/mailserver` (see [Mail](#mail)) |
| webmail | `roundcube/roundcubemail:latest-apache` | 127.0.0.1:8081 | this repo, `services/webmail` → `~/Downloads/webmail` (see [Mail](#mail)) |
| mysql | `mysql:8.0` | 0.0.0.0:3306 | started manually, volume `kimtaeeun-infra_mysql_data` |
| redis | `redis:7-alpine` | 0.0.0.0:6379 | started manually, volume `kimtaeeun-infra_redis_data` |

- axia (`~/Downloads/axia`, 127.0.0.1:18080) is an external project with its own deployment. It currently has no container.
- readygsm was taken down on 2026-09-27 (container, image, and `~/Downloads/readygsm-server` deleted).

### Startup and reboot

- On boot, `scripts/docker-startup.sh` waits up to 300 s for Docker, starts every container above, and starts boot-notifier last.
- Docker does not restart an `unless-stopped` container that was stopped with `docker stop`. That is why every container must be in the script's list.
- Before rebooting, stop containers cleanly with `docker stop`, then power off.

## Mail

- Stalwart (`mailserver` container) receives mail for `kimtaeeun.site` directly on port 25 (the KT line allows inbound and outbound 25; the server has a public IP with no NAT). Hostname `mail.kimtaeeun.site`, which must be a DNS-only A record.
- Outbound mail never goes out directly (no PTR on the residential IP). All non-local mail uses the `resend` relay route (`smtp.resend.com:465`, user `resend`, password from the container env `RESEND_RELAY_KEY`). Resend signs with DKIM selector `resend` and uses `send.kimtaeeun.site` as the envelope domain.
- Stalwart's own DKIM is set to manual and its generated keys were deleted, because its automatic key rotation needs automated DNS. Do not re-enable it unless DNS automation is added.
- Docker Desktop on macOS hides the client IP on published ports, which breaks SPF, IPREV, and auth-failure bans. So nginx (native) listens on 25, 465, 993, and 443 and forwards to the container's `127.0.0.1:100xx` ports with `proxy_protocol on`. Stalwart trusts PROXY headers from `172.16.0.0/12` (the compose network gateway, `SystemSettings.proxyTrustedNetworks`). Changing that setting needs a container restart.
- The admin `http` listener (8080, published on 127.0.0.1:18080) is exempt from PROXY protocol (`overrideProxyTrustedNetworks`), so the CLI can talk to it directly.
- Stalwart settings live in its Docker volumes, not in this repo. Change them with the CLI on the server: `~/Downloads/mailserver/cli.sh <describe|query|get|update|create|delete> ...` (uses `http://host.docker.internal:18080` and the admin credentials in `.env`).
- Mailboxes: `contact@kimtaeeun.site`. Admin: `admin@kimtaeeun.site`. TLS certificates come from Let's Encrypt via TLS-ALPN-01 on port 443.
- Resend domain `kimtaeeun.site` (region ap-northeast-1) must stay verified; its DNS records are `resend._domainkey` TXT, `send` MX and TXT, `rsend` CNAME.
- Webmail is Roundcube at `webmail.kimtaeeun.site` (Cloudflare-proxied, nginx `servers/webmail.conf` → 127.0.0.1:8081). It logs in over IMAP 993 / SMTP 465 to `mail.kimtaeeun.site`. It cannot live on `mail.kimtaeeun.site` itself because Stalwart terminates TLS on that host's 443 for its ACME TLS-ALPN certificate.
- Do not add Stalwart's suggested CAA records: they would block Cloudflare's edge certificates.

## nginx routing

| Path | Upstream |
| --- | --- |
| `/` | my-resume :4173 |
| `/nxdi-api/` | nxdi-server :10104 |
| `/sandrone/` | sandrone :10105 |
| `/axia/api/` | axia :18080 |
| `webmail.kimtaeeun.site` (own server block) | webmail :8081 |
| TCP 25565 (`stream` in `nginx.conf`) | minecraft |
| TCP 25, 465, 993, 443 (`stream`, PROXY protocol) | mailserver 127.0.0.1:10025/10465/10993/10443 |

The `axia`, `nxdi-api`, and `sandrone` locations are marker blocks owned by external deploy scripts (see [Rules](#rules)).

## Known issues

- GitHub Actions in the it-play org repos (nxdi, sandrone, claude-lniter) do not run on push, and manual runs return HTTP 500.
- The redis password is in plain text in the container command.
- SSH password login is still enabled.
