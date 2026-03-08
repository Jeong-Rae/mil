# Chat Handoff

## 2026-03-08 (session 7)

- `server.ps1` 을 실행한 작업 디렉토리를 `$StaticRoot` 로 고정해 두고, `chat/server/static.ps1` 는 정적 파일을 그 경로 기준으로 읽도록 수정했다.
- 이 변경으로 `Write-StaticResponse` 가 런타임 현재 위치가 흔들리더라도 `/`, `/index.html`, `/app.js`, `/style.css` 를 `server.ps1` 실행 위치에서 안정적으로 찾는다.

## 2026-03-08 (session 6)

- 발신자 `name` 은 클라이언트 입력값이 아니라 WebSocket 요청 IP의 마지막 두 옥텟 `C.D` 로 서버가 직접 결정하도록 바꿨다.
- `chat/server/main.ps1` 에서 `RemoteEndPoint` 기반 이름 계산을 추가하고, `chat/server/socket.ps1` 는 브로드캐스트 시 클라이언트가 보낸 `name` 을 무시한 채 서버가 저장한 이름을 다시 주입하도록 수정했다.
- `chat/index.html` 에서 수동 연결 폼을 제거하고 상태 표시만 남겼다.
- `chat/app.js` 는 페이지 로드 직후 즉시 연결을 시도하고, 연결 종료 시 2초 간격으로 계속 재시도하는 최소 자동 재연결 구조로 단순화했다.
- `chat/SPEC.md` 도 클라이언트 메시지 형식, 서버가 붙이는 `name`, 자동 연결/자동 재시도 동작 기준에 맞춰 갱신했다.

## 2026-03-08 (session 5)

- `chat/server.ps1` 의 listener 관련 설정을 조합식 상수 대신 literal 고정값으로 정리했다.
- `$Port`, `$BindAddress`, `$ApiPath` 를 제거하고 `http://+:9999/`, `http://+:9999/api/`, `ws://{server-ip}:9999/api/` 를 직접 상수로 두었다.
- `chat/server/main.ps1` 도 같은 전제에 맞춰 WebSocket 경로 비교를 `"/api/"` literal로 줄이고, 접속 안내 로그는 `$ClientConnectUrl` 만 사용하도록 정리했다.

## 2026-03-08 (session 4)

- 추가 조건(서버 ps1과 static 파일은 같은 경로, 서버 실행은 상대경로 고정)에 맞춰 경로 처리 코드를 더 단순화했다.
- `chat/server.ps1` 의 module 로드는 `$PSScriptRoot` 기반이 아니라 `./server/*.ps1` 상대경로 dot-source로 정리했다.
- `chat/server/static.ps1` 에서 `StaticRoot` 파라미터와 `Join-Path`를 제거하고, 라우팅된 파일명을 그대로 `ReadAllBytes` 하도록 줄였다.
- `chat/server/main.ps1` 에서 static root 변수와 전달 인자를 제거해 호출부를 최소화했다.

## 2026-03-08 (session 3)

- `chat/server.ps1` 를 bootstrap entrypoint로 줄이고, 실제 함수 구현을 `chat/server/main.ps1`, `chat/server/socket.ps1`, `chat/server/static.ps1` 로 분리했다.
- 실행 경로는 동일하게 유지했다. `server.ps1` 가 세 파일을 dot-source 한 뒤 `Main` 을 호출하므로 기존 실행 방식(`./server.ps1`)은 바뀌지 않는다.
- 기능 동작은 유지하면서도 파일 책임을 `main(accept loop/worker 관리)`, `socket(WebSocket receive/broadcast)`, `static(정적 파일 응답)` 으로 나눠 유지보수성을 높였다.

## 2026-03-08 (session 2)

- `chat/server.ps1` 에 정적 파일 응답 함수(`Write-StaticResponse`)를 추가해 `/`, `/index.html`, `/app.js`, `/style.css` 를 동일 프로세스에서 서빙하도록 수정했다.
- listener prefix를 `http://+:9999/`(정적) + `http://+:9999/api/`(WebSocket) 2개로 등록해 `client.ps1` 분리 실행 없이도 동작하도록 정리했다.
- WebSocket 업그레이드는 `/api/` 경로에서만 허용하도록 분기해 정적 요청과 충돌하지 않게 했다.
- WebSocket 경로 허용 조건은 `/api` 와 `/api/` 동시 허용에서 `/api/` 단일 경로 허용으로 줄여, 요구사항 기준 최소 라우팅만 남겼다.
- `chat/app.js` 는 `window.location` 기반으로 기본 host/port를 계산하도록 바꿔, 서버가 직접 서빙한 페이지에서 같은 서버의 `/api/` 로 자동 연결되게 했다.

## 2026-03-08

- `chat/server.ps1` 의 바인드 주소를 `localhost` 에서 `+` 로 변경해 IP와 무관하게 `:9999` 로 요청을 수신하도록 수정했다.
- `chat/server.ps1` 에 WebSocket/HTTP 기본 경로 상수 `$ApiPath = "/api/"` 를 추가하고 listener prefix를 `http://+:9999/api/` 로 고정했다.
- 클라이언트 접속 안내 로그도 `ws://{server-ip}:9999/api/` 형식으로 갱신했다.
- `chat/app.js` 에 `SERVER_PATH = "/api/"` 상수를 추가하고 WebSocket 연결 URL을 `ws://{server-ip}:9999/api/` 경로로 변경했다.

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
- `client.ps1` 의 `param(...)` 블록을 파일 최상단으로 옮겼다. 기존 위치는 PowerShell에서 스크립트 파라미터로 인식되지 않아 실행이 실패했다.
- 로컬 테스트용 기본 주소는 `localhost` 대신 `127.0.0.1` 로 통일했다. `localhost` 해석 차이로 브라우저 쪽에서 `ERR_CONNECTION_REFUSED` 가 날 수 있어서 IPv4 loopback으로 고정했다.
- `style.css` 는 범용 토큰/공통 규칙 위주가 아니라, 현재 HTML에 실제로 있는 `id` 와 `class` 를 직접 선택하는 방식으로 더 단순화했다.
- 디자인도 버튼, 입력창, 채팅 목록, 상태 표시 정도만 남기고 나머지 장식성은 거의 제거했다.
- `index.html` 도 더 줄여서 `Connect`, `Messages` 두 영역만 남겼다. 기존 hero 영역은 제거했다.
- 정렬은 grid보다 flex 위주로 다시 맞췄다. connect form, message form, section header 모두 flex 기준이다.

## Next Session Notes

- 현재 `server.ps1` 는 존재한다.
- `BindAddress` 는 `+` 이므로 모든 NIC에서 `:9999/`(static) 과 `:9999/api/`(WebSocket) 요청을 받는다.
- 클라이언트는 `file://` 로 바로 열 수 있게 정적 파일만 사용한다.
- 기본 사용 방식은 `server.ps1` 단독 실행 후 `http://<server-ip>:9999/` 접속이다.
- `client.ps1` 는 보조 스크립트로 남아 있으나 현재 구조에서 필수는 아니다.
- 다음 작업은 실제 내부망 환경에서 `server.ps1` 와 브라우저 클라이언트를 함께 열어 WebSocket 연결과 브로드캐스트를 확인하는 것이다.
- 구현 시 핵심은 "최소 기능의 WebSocket 연결 테스트용 채팅"이며, 불필요한 validation 과 기능 확장은 넣지 않는 것이다.
