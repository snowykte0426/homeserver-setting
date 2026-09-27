# homeserver-setting

`kimtaeeun.site` 홈서버(Mac mini) 설정 저장소. nginx, launchd, boot-notifier 등 자체 저장소가 없는 설정과 구동 파일을 관리한다.

`main` 에 push 하거나 Actions 에서 수동 실행하면 서버의 self-hosted runner 가 `scripts/deploy.sh` 로 변경분을 반영한다.
시크릿은 GitHub Secrets 로 관리하고 저장소에는 올리지 않는다. 운영 정보는 `AGENTS.md` 참고.
