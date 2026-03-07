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
- `server.ps1` 의 `Get-WorkerScript` 는 `${function:name}` 방식 대신 `Get-Item Function:<name>` 으로 함수 정의를 읽도록 수정했다. 기존 방식은 null 을 반환해 실행 시 실패했다.
- `Remove-CompletedWorkers` 는 빈 worker 목록도 허용하도록 수정했다. 기존 선언은 시작 직후 빈 컬렉션에서 바인딩 오류를 냈다.
- `BindAddress` 가 `SERVER_IP` placeholder 인 상태로 실행되면 시작 전에 명확한 오류 메시지를 내도록 수정했다.
- `chat/index.html`, `chat/app.js`, `chat/style.css` 를 추가했다.
- `chat/client.ps1` 를 추가했다.
- HTML은 연결 폼, 메시지 전송 폼, 채팅 목록 화면으로 구성했다.
- JS는 전역 변수와 top-level 함수만 사용하며, `handleConnectSubmit`, `handleMessageSubmit`, `handleSocketOpen`, `handleSocketMessage`, `handleSocketClose`, `handleSocketError` 같은 named handler를 소켓 이벤트에 직접 연결했다.
- DOM 조회는 `function $id(id) { return document.getElementById(id); }` 헬퍼를 사용하도록 정리했다.
- element cache 전역 변수는 제거하고, DOM 접근은 필요한 시점에 `$id()`를 직접 호출하는 형태로 단순화했다.
- 서버 주소 설정은 사용자 입력이 아니라 `app.js` 상단의 하드코딩 상수로 고정했다.
- 클라이언트 브라우저 전제는 최신 Chrome 으로 보고 `app.js` 는 `const` / `let` 을 사용하도록 정리했다.
- `client.ps1` 는 helper 함수 분리를 줄이고, 파일 매핑 hashtable + 단일 listener loop만 남긴 초단순 정적 파일 서버로 다시 압축했다.
- `client.ps1` 는 스크립트 위치를 기준으로 하지 않고, 실행 시 넘기는 정적 파일 절대경로를 그대로 루트로 사용하도록 수정했다.
- CSS는 블루 톤 기반의 단순한 카드형 레이아웃으로 구성했다.

## Next Session Notes

- 현재 `server.ps1` 는 존재한다.
- `BindAddress` 는 `SERVER_IP` placeholder 이므로 실제 내부망 IP로 먼저 수정해야 한다.
- 클라이언트는 `file://` 로 바로 열 수 있게 정적 파일만 사용한다.
- `client.ps1` 를 쓰려면 `http://localhost:3000/` 으로 접속하면 된다.
- `client.ps1` 실행 시에는 정적 파일이 있는 절대경로를 인자로 넘겨야 한다.
- 다음 작업은 실제 내부망 환경에서 `server.ps1` 와 브라우저 클라이언트를 함께 열어 WebSocket 연결과 브로드캐스트를 확인하는 것이다.
- 구현 시 핵심은 "최소 기능의 WebSocket 연결 테스트용 채팅"이며, 불필요한 validation 과 기능 확장은 넣지 않는 것이다.
