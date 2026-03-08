# HANDOFF

## 2026-03-08

### 작업 요약
- `eX-chat/SPEC.md` 신규 작성.
- `eX-chat`을 내부망용 임시 단일 채팅방 프로그램으로 정의하고, 서버 최소 책임 원칙을 명시함.
- `index.html`, `script.js`, `style.css`를 별도 파일로 두는 구조를 스펙과 구현에 반영함.
- 사용자 식별 규칙을 요청 IPv4 마지막 두 옥텟 `C.D` 사용으로 고정함.
- 빈 문자열 차단, timestamp 표시, 메시지 렌더링은 클라이언트 JS 책임으로 명시하고 구현함.
- `server.ps1` 신규 작성: `HttpListener` 기반 정적 파일 서빙 + `/ws` WebSocket 브로드캐스트 서버 구현.
- 서버는 메시지를 저장하지 않고, 접속/종료 시스템 메시지와 일반 채팅 메시지를 JSON 텍스트 프레임으로 브로드캐스트함.

### 산출물
- `eX-chat/SPEC.md`
  - 임시성/내부망/단일방/무저장 정책 정의
  - 서버 책임과 클라이언트 책임 분리
  - WebSocket 메시지 형식과 최소 검증 시나리오 포함
- `eX-chat/server.ps1`
  - `/`, `/index.html`, `/script.js`, `/style.css` 정적 파일 서빙
  - `/ws` WebSocket 연결 수락
  - 접속 IP 기반 `C.D` 표기 생성
  - 전체 접속자 브로드캐스트
  - 접속/종료 시스템 메시지 전송
- `eX-chat/index.html`
  - 단일 채팅 화면 구성
- `eX-chat/script.js`
  - WebSocket 연결/재연결
  - 빈 문자열 전송 방지
  - 클라이언트 기준 timestamp 표시
  - 시스템/일반 메시지 렌더링
- `eX-chat/style.css`
  - 간단한 패널형 채팅 UI 스타일

### 다음 세션 인계 포인트
- 현재 서버는 `HttpListener` 기반이며 기본 바인드는 `http://+:8888/`.
- IPv6는 스펙 범위 밖이고, 현재 구현도 `ipv6` 대체 문자열로만 처리함.
- timestamp는 서버가 아니라 브라우저 수신 시점 기준으로 표시됨.
- WebSocket 브로드캐스트는 단일 방 전제의 간단한 runspace 기반 구현이다.
- 실제 Windows PowerShell 환경에서 `HttpListener`의 `+` 바인딩 권한 또는 URL ACL 이슈가 있을 수 있으므로, 필요 시 `BindAddress`를 `localhost` 또는 특정 IP로 바꿔 검증하면 된다.

### 추가 검토 메모
- `2026-03-08` 추가 리뷰에서 `server.ps1`은 "HTML/JS 단일 클라이언트만 존재" 전제 대비 방어 로직이 과한 편으로 확인됨.
- 특히 브로드캐스트 로직이 `Broadcast-Bytes`와 handler 내부 `Send-BroadcastFromHandler`로 중복되어 있어 최소 구현 원칙에서 벗어난다.
- 각 클라이언트마다 `SemaphoreSlim` 전송 게이트를 두는 구조도 현재 단일 브라우저 JS 클라이언트 전제에서는 과도한 동시성 방어로 판단됨.
- `script.js`는 서버 메시지를 항상 JSON으로 받는 구조가 고정인데도 JSON 파싱 실패 시 raw 텍스트를 시스템 메시지로 렌더링하는 fallback을 갖고 있어 최소 검증 원칙과 맞지 않는다.
- `script.js`의 자동 재연결도 스펙의 최소 검증 시나리오에는 없으므로, 유지 목적이 없다면 제거 후보로 본다.
