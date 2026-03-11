# AccessControll Service Spec

## 1. 개요

ACS는 군부대 장병의 입영 및 퇴영 기록을 중앙에서 수집하고 조회하는 가벼운 PowerShell 서버이다.

현재 단계에서 ACS는 다음 원칙으로 동작한다.

- 중앙 서버 1개가 모든 gate 요청을 받는다.
- 각 gate의 client가 바코드를 읽고 입영/퇴영을 판별한다.
- client가 `type`, `id`, `location`을 서버로 전송한다.
- 서버는 요청을 신뢰하고 기록과 현재 상태만 관리한다.

본 단계는 내부 시스템의 단순 작업용을 전제로 하며, 외부 조작이 없는 안전한 환경을 가정한다.

---

## 2. 개발 기준

- 구현 언어: PowerShell
- 실행 환경: Windows PowerShell 5.x
- 엔트리 파일: `server.ps1`
- 문서 기준: 본 Spec은 중앙 서버 기준의 최소 구현을 정의한다.
- 구현 원칙:
  - `AUDIT.md`의 최소 구현, 최소 검증 원칙을 따른다.
  - 서버는 가볍게 유지한다.
  - 복잡한 validation, decode, dedupe는 서버에 넣지 않는다.
  - 기록용 데이터와 현재 상태 데이터를 분리해서 관리한다.

---

## 3. 목적

ACS의 목적은 다음과 같다.

- client가 보낸 입퇴영 요청을 중앙에서 기록한다.
- location별 마지막 기록 위치 현황을 조회할 수 있게 한다.
- 기록과 현재 상태를 분리하여 단순하게 유지한다.

---

## 4. 시스템 범위

### 4.1 현재 단계 포함 범위

- 중앙 HTTP 서버 1개 실행
- 정적 웹 파일 서빙(`index.html`, `board.html`, `script.js`, `style.css`)
- `location.json` 기반 location 후보 관리
- 입퇴영 요청 수신
- `list.json` 기반 허용 군번 검증
- CSV append-only 기록 저장
- 메모리 기반 현재 위치 상태 유지
- 특정 location의 마지막 기록 위치 조회
- 서버 재시작 시 CSV를 다시 읽어 현재 상태 복원

### 4.2 현재 단계 제외 범위

- 서버 측 바코드 decode
- 서버 측 entry/exit 판별
- 서버 측 location별 중복 예외 처리
- 이름 조회
- 인증/인가
- 외부 공개 운영
- DB 연동
- GUI

---

## 5. 책임 분리

### 5.1 Client 책임

- 바코드 입력 수신
- 바코드에서 입영/퇴영 구분
- 바코드에서 군번 `id` 추출
- 스캐너 진입 시 `location.json` 후보 중 하나 선택
- 요청에 `location` 포함
- location별 중복 예외 처리
- 중앙 서버로 HTTP 요청 전송
- 현황판과 로그에서 `location.json`에 있는 location만 표시

### 5.2 Server 책임

- HTTP 요청 수신
- `location.json`에서 location 후보 로드
- location 후보 조회 응답
- 요청 본문에서 `type`, `id`, `location` 읽기
- `list.json`에 있는 군번인지 확인
- 기록 CSV에 append
- 현재 상태 메모리 갱신
- location별 마지막 기록 위치 조회 응답

---

## 6. 신뢰 및 검증 원칙

현재 단계에서 client와 server는 내부 안전 환경에서 동작한다고 가정한다.

따라서 서버는 아래 원칙을 따른다.

- client가 보낸 `type`, `location`은 신뢰한다.
- `id`는 `list.json`에 있는 군번만 허용한다.
- `location.json`에 없는 `location`도 거부하지 않는다.
- 과도한 형식 검증을 하지 않는다.
- 복잡한 복구, fallback, 방어 로직을 넣지 않는다.
- 요청 처리 실패가 전체 서버 종료로 이어지지 않도록 얇은 보호만 둔다.

서버는 정상 경로 기준으로 아래 값만 기대한다.

- `type`: `entry` 또는 `exit`
- `id`: 군번 문자열
- `location`: gate 식별 문자열

---

## 7. 데이터 관리 원칙

ACS는 기록용 데이터와 현재 상태 데이터를 분리해서 관리한다.

### 7.1 기록용 데이터

- 목적: 영구 보관 및 사후 확인
- 저장 방식: CSV append-only

### 7.2 현재 상태 데이터

- 목적: 군번별 마지막 location 조회
- 저장 방식: 서버 프로세스 메모리

### 7.3 분리 이유

- 기록은 누적 이력을 보존해야 한다.
- 현재 위치 상태는 빠르게 조회되어야 한다.
- `GET` 요청 때마다 CSV 전체를 다시 읽지 않도록 한다.

---

## 8. HTTP 인터페이스

ACS는 현재 단계에서 아래 API를 제공한다.

### 8.1 location 후보 조회

```text
GET /locations
```

정상 응답 예시:

```json
[
  {
    "location": "gate-1"
  },
  {
    "location": "gate-2"
  }
]
```

규칙:

- 서버 시작 시 읽은 `location.json` 배열을 그대로 반환한다.
- 스캐너의 location 선택과 현황판 표시 기준에 사용한다.

### 8.2 입퇴영 요청

```text
POST /access
Content-Type: application/json
```

요청 예시:

```json
{
  "type": "entry",
  "id": "a25-76046946",
  "location": "gate-1"
}
```

정상 응답 예시:

```json
{
  "status": "logged"
}
```

### 8.3 location별 현재 인원 조회

```text
GET /status?location=gate-1
```

정상 응답 예시:

```json
{
  "location": "gate-1",
  "ids": ["a25-76046946", "a01-1234567"]
}
```

규칙:

- 특정 location만 조회한다.
- 응답은 마지막 기록 location이 해당 값인 군번 `id` 목록을 반환한다.

### 8.4 전체 현황 조회

```text
GET /status
```

정상 응답 예시:

```json
[
  {
    "location": "gate-1",
    "ids": ["a25-76046946", "a01-1234567"]
  },
  {
    "location": "gate-2",
    "ids": []
  }
]
```

규칙:

- 모든 location의 마지막 기록 위치 현황을 반환한다.
- `board.html`은 이 응답을 사용한다.
- `board.html`은 `location.json`에 있는 location만 화면에 표시한다.

### 8.5 일별 로그 조회

```text
GET /logs?day=2026-03-11
```

정상 응답 예시:

```json
[
  {
    "time": "2026-03-11T00:15:00.0000000Z",
    "type": "entry",
    "location": "gate-1",
    "id": "a25-76046946"
  }
]
```

규칙:

- 특정 KST 날짜의 전체 입퇴영 로그를 반환한다.
- `day`는 `YYYY-MM-DD` 형식 문자열이다.
- `day`가 없으면 서버는 현재 KST 날짜를 사용한다.
- 검색, 추가 필터링, 정렬은 `board.html`이 수행한다.
- `board.html`은 `location.json`에 없는 location 로그는 표시하지 않는다.

---

## 9. 요청 처리 흐름

### 9.1 `GET /locations`

1. 서버가 시작 시 읽은 `location.json` 배열을 그대로 반환한다.

### 9.2 `POST /access`

1. client가 `type`, `id`, `location`을 전송한다.
2. 서버가 요청 값을 읽는다.
3. 서버가 `id`가 `list.json`에 있는지 확인한다.
4. 서버가 CSV에 한 줄 append 한다.
5. 서버가 메모리의 현재 상태를 갱신한다.
6. 서버가 `logged` 응답을 반환한다.

### 9.3 상태 갱신 규칙

- `type`과 관계없이 현재 상태는 군번 기준 마지막 `location` 기록으로 덮어쓴다.
- 같은 `id` 요청이 오면 이전 `location`의 현재 상태를 지우고 새 `location` 하나만 남긴다.
- 즉 전체 현황에서 한 군번의 위치는 가장 마지막에 입력된 `location`이다.

### 9.4 `GET /status`

1. 요청 query에서 `location`을 읽는다.
2. 메모리 상태에서 해당 location의 현재 인원 목록을 조회한다.
3. JSON으로 반환한다.

### 9.5 `GET /logs`

1. 요청 query에서 `day`를 읽는다.
2. 값이 없으면 서버가 현재 KST 날짜를 사용한다.
3. CSV 전체 기록에서 해당 KST 날짜의 행만 추린다.
4. JSON 배열로 반환한다.

---

## 10. 기록 저장

입퇴영 기록은 CSV 파일로 저장한다.

### 10.1 CSV 컬럼

| 컬럼명 | 설명 |
| --- | --- |
| time | 처리 시각 |
| type | `entry` 또는 `exit` |
| location | gate 식별값 |
| id | 군번 |

### 10.2 예시

```csv
time,type,location,id
2026-03-09T08:12:11,entry,gate-1,a25-76046946
2026-03-09T17:41:53,exit,gate-1,a25-76046946
```

### 10.3 저장 방식

- 파일이 없으면 생성
- 파일이 있으면 append
- append가 쉬운 단순 구조를 유지

---

## 11. 현재 상태 관리

현재 상태는 서버 메모리에서 관리한다.

### 11.1 기본 구조

- `location`별 마지막 기록 위치 기준 `id` 목록 또는 집합

예:

```text
gate-1 -> { a25-76046946, a01-1234567 }
gate-2 -> { b12-7654321 }
```

### 11.2 서버 재시작 시 복원

- 서버 시작 시 기존 CSV를 처음부터 읽는다.
- 기록을 순서대로 적용하여 메모리 상태를 재구성한다.

### 11.3 이유

- 조회는 메모리에서 바로 처리하는 편이 단순하다.
- 기록은 CSV에 남기고, 상태는 메모리에 유지하는 편이 목적에 맞다.

## 11.4 로그 조회 방식

- 로그 조회는 메모리 캐시를 따로 두지 않는다.
- `GET /logs` 요청 때 CSV를 읽고 해당 날짜만 추린다.
- 현재 단계에서는 로그 양이 크지 않다고 가정한다.

## 11.5 location 후보 관리

- `location.json`은 `[{"location":"gate-1"}]` 구조의 배열만 사용한다.
- 스캐너는 이 목록 중 하나를 먼저 선택한 뒤 스캔을 시작한다.
- 현황판은 전체 상태를 조회하지만, 화면에는 이 목록에 있는 location만 표시한다.
- 목록에 없는 location 데이터도 서버는 기록과 상태 계산에서 계속 허용한다.

---

## 12. 오류 처리 원칙

현재 단계에서는 최소한의 오류 처리만 둔다.

- 잘못된 요청은 단순한 오류 응답으로 끝낸다.
- 한 요청 실패가 전체 서버 종료로 이어지지 않게 한다.
- CSV 저장 실패는 해당 요청 실패로 처리한다.
- 복잡한 재시도나 상세 에러 체계는 넣지 않는다.

---

## 13. 최소 구현 계약

현재 단계의 ACS는 아래를 충족해야 한다.

1. 중앙 HTTP 서버로 실행될 수 있어야 한다.
2. `GET /locations` 로 `location.json` 배열을 반환할 수 있어야 한다.
3. `POST /access` 요청을 받을 수 있어야 한다.
4. 요청의 `type`, `id`, `location`을 읽어 CSV에 기록할 수 있어야 한다.
5. 요청에 따라 location별 현재 상태를 메모리에서 갱신할 수 있어야 한다.
6. `GET /status?location=...` 로 특정 location의 현재 상태 목록을 반환할 수 있어야 한다.
7. 서버 재시작 시 CSV를 다시 읽어 현재 상태를 복원할 수 있어야 한다.
8. `GET /logs?day=...` 로 특정 KST 날짜의 전체 로그를 반환할 수 있어야 한다.

---

## 14. 예시 시나리오

### 14.1 정상 입영 요청

- 요청:

```json
{
  "type": "entry",
  "id": "a25-76046946",
  "location": "gate-1"
}
```

- 결과:
  - CSV 1건 추가
  - `gate-1` 현재 상태에 `a25-76046946` 포함

### 14.2 정상 퇴영 요청

- 요청:

```json
{
  "type": "exit",
  "id": "a25-76046946",
  "location": "gate-1"
}
```

- 결과:
  - CSV 1건 추가
  - `gate-1`이 마지막 기록 location이므로 현재 상태에 `a25-76046946` 포함

### 14.3 현재 상태 조회

- 요청:

```text
GET /status?location=gate-1
```

- 응답:

```json
{
  "location": "gate-1",
  "ids": ["a01-1234567"]
}
```

### 14.4 일별 로그 조회

- 요청:

```text
GET /logs?day=2026-03-11
```

- 응답:

```json
[
  {
    "time": "2026-03-11T00:15:00.0000000Z",
    "type": "entry",
    "location": "gate-1",
    "id": "a25-76046946"
  }
]
```

---

## 15. 구현 비고

- 현재 단계에서 서버는 client 요청을 신뢰한다.
- 서버는 바코드 원문을 알 필요가 없다.
- 서버는 현재 상태 조회와 기록 저장에만 집중한다.
- 저장은 CSV, 조회용 상태는 메모리로 분리하는 것이 현재 요구에 가장 적합하다.
- 현황판 로그 뷰는 일별 전체 로그를 받아 FE에서 검색과 정렬을 수행한다.
