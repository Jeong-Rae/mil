# HANDOFF

## 2026-03-08

### 작업 요약
- `/chat` 신규 구현.
- `eX-chat`의 WebSocket 경로에서 드러난 Codespaces/Linux 호환성 문제를 피하기 위해 HTTP-only 채팅 방식으로 전환함.
- `/chat/SPEC.md` 신규 작성: long polling 기반 단일 채팅방, 최근 200개 메모리 보존, `lastId` 기준 조회 흐름을 명시함.
- `chat/server.ps1` 신규 작성: `HttpListener` 기반 정적 파일 서빙 + JSON API 구현.
- `chat/index.html`, `chat/script.js`, `chat/style.css` 신규 작성: HTTP polling 기반 채팅 UI 구현.
- 후속 수정: `Cleanup-RequestHandlers`가 시작 직후 빈 `ArrayList`를 받을 수 있도록 `AllowEmptyCollection`을 추가함.
- 후속 수정: `GET /messages`가 메시지 1건일 때도 항상 JSON 배열을 반환하도록 보정함.
- 후속 수정: 프론트 `pollLoop`도 단일 객체 응답을 배열로 정규화하도록 방어 코드를 추가함.

### 산출물
- `chat/SPEC.md`
  - HTTP-only 단일 채팅방 스펙
  - `GET /messages/latest`, `GET /messages?after=...`, `POST /messages` 정의
  - 최근 200개 메모리 보존, 15초 long polling, 초기 히스토리 미표시 정책 포함
- `chat/server.ps1`
  - `http://+:8888/` 고정 바인드
  - 정적 파일 서빙
  - 최신 ID 조회 API
  - `after` 기준 long polling 메시지 조회 API
  - JSON POST 메시지 등록 API
  - 요청별 runspace 처리로 long polling 요청과 다른 요청을 동시에 처리
  - 빈 handler 목록으로도 시작 가능하도록 바인딩 보정
- `chat/index.html`
  - 단일 채팅 UI
- `chat/script.js`
  - `GET /messages/latest`로 초기 기준점 설정
  - `GET /messages?after=...` long polling 반복
  - `POST /messages` 전송
  - 서버 `createdAt` 표시
  - polling 응답을 배열 기준으로 정규화
- `chat/style.css`
  - 단순 패널형 채팅 UI

### 다음 세션 인계 포인트
- 현재 구현은 WebSocket/SSE 없이 순수 HTTP만 사용한다.
- 초기 페이지 로드 시 과거 메시지는 가져오지 않고, `/messages/latest`를 기준으로 이후 새 메시지만 본다.
- 서버 메모리에는 최근 200개만 남는다.
- long polling 대기 시간은 15초, 내부 대기 루프는 250ms sleep polling 방식이다.
- 발신자 표시는 요청 IPv4 마지막 두 옥텟 `C.D`이며, 파싱 실패 시 `unknown`.
- 실제 Windows PowerShell 환경에서 `HttpListener`의 `+` 바인딩 권한 또는 URL ACL 이슈가 있을 수 있다.
