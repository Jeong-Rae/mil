# Simple LAN Chat (PowerShell 5, WebSocket) - SPEC

## 1. Goal

내부 단독망(LAN)에서 동작하는 가장 단순한 공용 채팅을 구현한다.

- 서버: `server.ps1`
- 클라이언트: `index.html` (`file://`로 직접 열기)
- 연결 방식: WebSocket
- 채팅방: 단일 공용 room 1개
- 메시지 저장: 없음
- 과거 메시지 복구: 없음

이 구현은 "WebSocket 연결 테스트가 실제로 되는지"를 확인할 수 있는 수준의 최소 기능만 제공한다.

## 2. Files

```text
/chat
 ├─ server.ps1
 ├─ client.ps1
 ├─ index.html
 ├─ app.js
 ├─ style.css
 ├─ SPEC.md
 └─ HANDOFF.md
```

필요 시 파일 수는 더 줄일 수 있다. 다만 기본 문서 기준은 위 구성을 따른다.

## 3. Network Model

- 서버와 클라이언트는 서로 같은 내부망에 있다.
- 서버는 내부망에서 접근 가능한 `ip:port` 로 실행된다.
- 클라이언트는 별도 HTTP 서버로 제공되지 않는다.
- 사용자는 브라우저에서 `file:///.../index.html` 을 직접 연다.
- 필요 시 `client.ps1` 로 정적 파일을 `http://localhost:3000/` 에서 열 수 있다.
- 클라이언트는 브라우저 내 WebSocket API로 `ws://{server-ip}:{port}/` 에 직접 연결한다.
- `localhost` 고정 구성을 기본 전제로 삼지 않는다.

## 4. Design

- 서버는 현재 연결된 WebSocket 세션 목록만 메모리에 유지한다.
- 서버는 메시지를 저장하지 않는다.
- 서버는 history, cursor, DB, 파일 저장을 사용하지 않는다.
- 어떤 클라이언트가 메시지를 보내면 서버는 즉시 현재 연결된 모든 클라이언트에 브로드캐스트한다.
- 클라이언트가 끊겨 있던 동안의 메시지는 유실된다.
- 서버 코드는 가능한 validation 을 수행하지 않는다.
- 서버는 올바른 입력이 주어졌다고 가정하고 처리한다.
- 실행 인자는 최소화하거나 사용하지 않는다.
- 포트, 바인드 주소 같은 값은 파일 상단 고정값으로 두는 방식을 우선한다.

## 5. Fixed Values

### `server.ps1`

- port: `9999`
- bind address: 내부망에서 접근 가능한 고정 IP 또는 `0.0.0.0`
- max clients/workers: 구현에 필요한 최소 수준만 사용

### `index.html`

- default server ip: 사용자가 직접 입력하거나 `app.js` 상수로 수정
- default server port: `9999`
- reconnect delay: `2` seconds (선택)

### `client.ps1`

- static file port: `3000`
- static host: `localhost`
- static root: 실행 시 전달하는 절대경로
- served files: `/`, `/index.html`, `/app.js`, `/style.css`

`client.ps1` 는 정적 파일이 있는 절대경로를 실행 시 인자로 받는다.

## 6. WebSocket Contract

### Connect

클라이언트는 아래 주소 형식으로 연결한다.

```text
ws://{server-ip}:{port}/
```

서버는 단일 엔드포인트만 제공한다.

### Client -> Server message

클라이언트는 아래 JSON 형식의 텍스트 메시지를 전송한다.

```json
{
  "text": "hello"
}
```

Rules:

- `text` 는 올바른 값이 들어온다고 가정한다.
- 서버는 길이, null, 형식에 대한 과도한 검증을 하지 않는다.
- 서버는 발신자 식별값을 요청 IP 기준으로 직접 붙이고, 메시지를 저장하지 않은 채 바로 브로드캐스트한다.

### Server -> Client message

서버는 브로드캐스트 시 아래 형식의 JSON 텍스트 메시지를 보낸다.

```json
{
  "name": "0.12",
  "text": "hello",
  "sentAt": "2026-03-07T12:00:00Z"
}
```

Rules:

- `name` 은 클라이언트의 요청 IP 마지막 두 옥텟 `C.D` 문자열을 사용한다.
- `sentAt` 은 서버 시각 기준 ISO8601 문자열을 사용한다.
- 서버는 수신 메시지에 `name`, `sentAt` 을 덧붙여 전달한다.
- 별도의 ack, delivery id, error code 계약은 두지 않는다.

## 7. HTTP Scope

이 스펙의 핵심 통신은 WebSocket 하나만 사용한다.

- `POST /send` 없음
- `GET /stream` 없음
- SSE 없음
- 메시지 전송용 REST API 없음

필요하다면 서버 프로세스 확인용 최소 HTTP 응답을 추가할 수 있으나, 기본 스펙 필수 항목은 아니다.

## 8. Server Behavior

- 서버 시작 시 지정된 `ip:port` 에 바인드한다.
- 새 WebSocket 연결이 들어오면 세션 목록에 추가한다.
- 세션이 닫히면 목록에서 제거한다.
- 어떤 세션에서든 메시지를 받으면 즉시 현재 열린 모든 세션에 브로드캐스트한다.
- 브로드캐스트 중 일부 세션 전송 실패가 발생하면 해당 세션만 정리하고 나머지는 계속 처리한다.
- 입력 데이터가 정상이라는 전제이므로 복잡한 오류 응답을 설계하지 않는다.
- 인증, 권한, room 분리, 사용자 목록, 닉네임 중복 처리, 메시지 수정/삭제는 범위 밖이다.

## 9. Client Behavior

- 사용자는 `index.html` 을 브라우저에서 직접 연다.
- 또는 `client.ps1` 실행 후 `http://localhost:3000/` 으로 연다.
- `client.ps1` 실행 예시: `.\client.ps1 C:\chat`
- 화면에는 최소한 아래 요소만 둔다.
  - connection status
  - message list
  - text input
  - send button
- 페이지 진입 직후 WebSocket 연결을 연다.
- 사용자가 입력한 텍스트는 JSON 메시지로 서버에 전송한다.
- 수신한 메시지는 즉시 화면 목록에 추가한다.
- 연결 상태는 단순 텍스트로 표시한다.
- 연결 실패나 종료 뒤에는 고정 지연 기반의 가장 단순한 자동 재연결을 계속 시도한다.

## 10. Non-Goals

아래 항목은 구현 범위에서 제외한다.

- 메시지 저장
- 최근 메시지 조회
- 재접속 후 누락 메시지 복구
- 로그인/인증
- TLS (`wss://`)
- 파일 업로드
- 멀티 room
- 복잡한 validation
- 상세 오류 계약
- 운영용 수준의 보안/감사 기능

## 11. Test Checklist

1. 브라우저에서 `file://` 로 `index.html` 을 직접 열어도 동작한다.
2. `client.ps1` 실행 후 `http://localhost:3000/` 으로 열어도 동작한다.
3. 서로 다른 브라우저 창 또는 다른 장치 2개 이상이 같은 `ws://ip:port` 서버에 연결된다.
4. A가 보낸 메시지가 서버 저장 없이 A/B 모두에게 즉시 표시된다.
5. 연결이 끊긴 동안 발생한 메시지는 복구되지 않는다.
6. 서버는 최소 검증만 수행하고 정상 입력 기준으로 계속 처리한다.
7. 내부망 다른 장치에서 서버 `ip:port` 로 접속 가능하다.

## 12. Implementation Notes

- 구현은 Windows PowerShell 5.x 기준을 우선한다.
- 서버 코드는 실사용 최소 동작을 우선하고, 방어적 추상화는 과도하게 넣지 않는다.
- 클라이언트 UI도 테스트용 수준의 단순한 형태를 유지한다.
- "잘 동작하는 가장 단순한 구조"가 이 스펙의 핵심 기준이다.
