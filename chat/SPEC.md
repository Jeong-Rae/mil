# chat Spec

## 1. 개요

`chat`은 내부망에서 임시로 사용하는 단일 채팅방 프로그램이다.

- 장기 유지보수를 목표로 하지 않는다.
- Codespaces/Linux/PowerShell 환경에서도 안정적으로 동작하는 것을 우선한다.
- WebSocket은 사용하지 않는다.
- 순수 HTTP 요청/응답만으로 채팅을 구현한다.

---

## 2. 기술 기준

- 서버: PowerShell 스크립트 (`server.ps1`)
- 프론트엔드: `index.html`, `script.js`, `style.css`
- 포트: `8888`
- 바인드: `+:8888`
- 통신:
  - HTTP GET
  - HTTP POST

---

## 3. 시스템 범위

### 3.1 포함 범위

- 단일 채팅방 1개 제공
- 정적 파일 HTTP 서빙
- 메시지 전송 HTTP POST
- 메시지 조회 HTTP GET
- long polling 기반 새 메시지 대기
- 최근 메시지 200개 메모리 보관

### 3.2 제외 범위

- WebSocket
- SSE
- 파일/DB 저장
- 인증/인가
- 닉네임 입력
- 입장/퇴장 시스템 메시지
- 온라인 사용자 목록
- 다중 채팅방
- 파일 업로드

---

## 4. 구조

프로젝트 파일은 아래와 같다.

- `server.ps1`
- `index.html`
- `script.js`
- `style.css`

브라우저는 아래 주소로 접속한다.

```text
http://<host>:8888/
```

---

## 5. HTTP 인터페이스

### 5.1 정적 파일

- `GET /`
- `GET /index.html`
- `GET /script.js`
- `GET /style.css`

### 5.2 최신 기준점 조회

```text
GET /messages/latest
```

응답:

```json
{
  "latestId": 12
}
```

메시지가 없으면 `latestId`는 `0`이다.

### 5.3 새 메시지 조회

```text
GET /messages?after={lastId}
```

- `after`는 필수 숫자 값이다.
- 해당 ID 이후 메시지가 있으면 즉시 배열 반환
- 없으면 최대 15초 대기 후 빈 배열 반환

응답 예시:

```json
[
  {
    "id": 13,
    "sender": "10.23",
    "text": "hello",
    "createdAt": "2026-03-08T12:00:00.0000000Z"
  }
]
```

새 메시지가 없으면:

```json
[]
```

### 5.4 메시지 전송

```text
POST /messages
Content-Type: application/json
```

요청 예시:

```json
{
  "text": "hello"
}
```

정상 응답은 생성된 메시지 JSON이며, 상태 코드는 `201`이다.

빈 문자열 또는 공백-only 문자열은 `400`이다.

---

## 6. 메시지 모델

서버 메시지는 아래 필드를 가진다.

```json
{
  "id": 13,
  "sender": "10.23",
  "text": "hello",
  "createdAt": "2026-03-08T12:00:00.0000000Z"
}
```

규칙:

- `id`: 서버 증가 정수
- `sender`: 요청 IPv4의 마지막 두 옥텟 `C.D`
- `text`: 메시지 본문
- `createdAt`: 서버 생성 시각

IPv4 파싱 실패 시 `sender`는 `unknown`이다.

서버는 최근 200개 메시지만 메모리에 유지한다.

---

## 7. 초기 로드 및 polling 흐름

클라이언트는 아래 순서로 동작한다.

1. 페이지 로드
2. `GET /messages/latest` 호출
3. 반환된 `latestId`를 `lastId`로 저장
4. `GET /messages?after={lastId}` long polling 시작
5. 새 메시지 배열을 받으면 렌더링 후 `lastId` 갱신
6. 다시 long polling 반복

초기 히스토리는 표시하지 않는다.
즉, 페이지 진입 이후의 새 메시지만 본다.

---

## 8. 책임 분리

### 8.1 서버 책임

- 정적 파일 서빙
- 메시지 메모리 보관
- 증가 ID 발급
- `createdAt` 생성
- `after` 기준 새 메시지 조회
- 15초 long polling 대기
- 요청 IP 기반 `sender` 계산

### 8.2 프론트엔드 책임

- 입력값 읽기
- 빈 문자열 전송 차단
- 메시지 POST 호출
- `lastId` 추적
- long polling 반복
- 서버 `createdAt` 표시 포맷
- 연결 상태 표시
- 메시지 렌더링

---

## 9. 예외 처리 원칙

- 잘못된 요청은 400 또는 404로 단순 응답
- 서버 재시작 시 메시지 버퍼는 초기화
- 복잡한 재시도, 복구, 영속 저장은 요구하지 않음
- long polling 실패 시 클라이언트는 잠시 후 다시 요청

---

## 10. 실행 방식

예시:

```powershell
pwsh -File .\server.ps1
```

또는:

```powershell
. .\server.ps1
Start-ChatServer
```

---

## 11. 최소 검증 시나리오

- 서버 실행 후 `http://<host>:8888/` 접속 가능
- 브라우저가 `GET /messages/latest`로 초기 기준점을 받음
- 한 브라우저의 메시지 POST가 다른 브라우저 long polling 결과로 표시됨
- `after` 기준으로 중복 없이 새 메시지만 반환됨
- 새 메시지가 없으면 최대 15초 후 빈 배열 반환
- 빈 문자열은 프론트에서 차단되고 서버도 400 반환
- 200개 초과 시 오래된 메시지가 제거됨
- 서버 재시작 시 메시지 목록은 초기화됨
