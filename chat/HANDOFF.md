# Chat Handoff

## 2026-03-07

- `chat/SPEC.md` 를 기존 `SSE + client.ps1` 구조에서 `PowerShell WebSocket 서버 + file:// index.html 클라이언트` 구조로 전면 개정했다.
- 서버는 메시지 저장 없이 즉시 브로드캐스트만 수행한다는 점을 명시했다.
- 서버와 클라이언트가 같은 내부망에 있으며, `ip:port` 로 직접 접근한다는 전제를 문서에 고정했다.
- 클라이언트는 별도 HTTP 서버 없이 브라우저에서 `file://` 로 직접 여는 방식으로 정의했다.
- 서버 validation 을 최소화하고 올바른 입력을 가정하는 방향으로 스펙을 단순화했다.
- 기존 `GET /stream`, `POST /send`, `GET /health`, SSE, `tiktok-*` 관련 내용은 제거했다.
- `chat/server.ps1` 를 새로 작성했다.
- 구현은 `Add-Type` 없이 순수 PowerShell 스크립트와 .NET 타입 호출만 사용한다.
- 서버는 `HttpListener` 로 WebSocket 업그레이드를 받고, 클라이언트별 수신 루프는 runspace pool에서 처리한다.
- 수신 JSON은 PowerShell의 `ConvertFrom-Json` / `ConvertTo-Json` 으로 `sentAt` 만 덧붙여 현재 연결된 모든 세션에 즉시 브로드캐스트한다.
- `server.ps1` 구조를 top-level 함수 정의들 + `Main` 엔트리 형태로 재정리했다.
- runspace worker도 중첩 함수 대신 top-level 함수 소스를 조합해 실행하도록 바꿨다.

## Next Session Notes

- 현재 `server.ps1` 는 존재한다.
- `BindAddress` 는 `SERVER_IP` placeholder 이므로 실제 내부망 IP로 먼저 수정해야 한다.
- 다음 작업은 `SPEC.md` 기준으로 `index.html`, 필요 시 `app.js`, `style.css` 를 실제 구현하는 것이다.
- 구현 시 핵심은 "최소 기능의 WebSocket 연결 테스트용 채팅"이며, 불필요한 validation 과 기능 확장은 넣지 않는 것이다.
