# AccessControll Service Spec

## 1. 개요

ACS는 군부대 장병의 입영 및 퇴영 기록을 중앙에서 수집하고 조회하는 가벼운 PowerShell 서버이다.

현재 단계에서 ACS는 다음 원칙으로 동작한다.

- 중앙 서버 1개가 모든 gate 요청을 받는다.
- 각 gate의 client가 바코드를 읽고 입영/퇴영을 판별한다.
- client가 `type`, `id`, `location`을 서버로 전송한다.
- 서버는 요청을 신뢰하고 로그 기록과 정적 파일 서빙만 담당한다.
- 조회 가공은 브라우저가 `list.json`, `location.json`, `logs/access-log.csv`를 직접 읽어 처리한다.

---

## 2. 개발 기준

- 구현 언어: PowerShell
- 실행 환경: Windows PowerShell 5.x
- 엔트리 파일: `server.ps1`
- 구현 원칙:
  - `AUDIT.md`의 최소 구현, 최소 검증 원칙을 따른다.
  - 서버는 `POST /access`와 정적 파일 서빙에 집중한다.
  - 복잡한 validation, decode, dedupe는 서버에 넣지 않는다.
  - 현재 인원 상태판용 서버 메모리 상태는 두지 않는다.
  - 로그 조회 가공은 FE 브라우저에서 처리한다.

---

## 3. 목적

ACS의 목적은 다음과 같다.

- client가 보낸 입퇴영 요청을 중앙에서 기록한다.
- FE가 정적 자원을 직접 읽어 명단 조회, location 선택, 로그 조회를 수행할 수 있게 한다.
- 조회 화면에서 현재 입영자/현재 퇴영자를 브라우저 계산으로 전체 명단 확인할 수 있게 한다.

---

## 4. 시스템 범위

### 4.1 현재 단계 포함 범위

- 중앙 HTTP 서버 1개 실행
- 정적 웹 파일 서빙(`index.html`, `board.html`, `script.js`, `style.css`)
- 정적 데이터 파일 서빙(`list.json`, `location.json`, `logs/access-log.csv`)
- 입퇴영 요청 수신
- `list.json` 기반 허용 군번 검증
- CSV append-only 기록 저장
- FE 로그 조회와 현재 인원 명단 조회

### 4.2 현재 단계 제외 범위

- 서버 측 바코드 decode
- 서버 측 entry/exit 판별
- 서버 측 location별 중복 예외 처리
- 서버 측 현재 상태 관리 API
- 서버 측 로그 검색, 정렬, 날짜 필터링
- 인증/인가
- DB 연동
- GUI

---

## 5. 책임 분리

### 5.1 Client / FE 책임

- 바코드 입력 수신
- 바코드에서 입영/퇴영 구분
- 바코드에서 군번 `id` 추출
- 스캐너 진입 시 `location.json` 후보 중 하나 선택
- 요청에 `location` 포함
- `list.json`을 직접 읽어 군번/이름 표시
- `location.json`을 직접 읽어 스캐너 location 후보와 로그 표시 기준 구성
- `logs/access-log.csv`를 직접 읽어 로그 추출
- 로그 날짜 필터링, 검색, 정렬 수행
- `현재 입영자`, `현재 퇴영자` 전체 목록 계산

### 5.2 Server 책임

- HTTP 요청 수신
- 정적 파일 서빙
- 요청 본문에서 `type`, `id`, `location` 읽기
- `list.json`에 있는 군번인지 확인
- 기록 CSV에 append

---

## 6. 신뢰 및 검증 원칙

현재 단계에서 client와 server는 내부 안전 환경에서 동작한다고 가정한다.

- client가 보낸 `type`, `location`은 신뢰한다.
- `id`는 `list.json`에 있는 군번만 허용한다.
- `location.json`에 없는 `location`도 거부하지 않는다.
- 과도한 형식 검증을 하지 않는다.
- 복잡한 복구, fallback, 방어 로직을 넣지 않는다.
- 요청 처리 실패가 전체 서버 종료로 이어지지 않도록 얇은 보호만 둔다.

정상 경로 기준 기대값:

- `type`: `entry` 또는 `exit`
- `id`: 군번 문자열
- `location`: gate 식별 문자열

---

## 7. 데이터 관리 원칙

### 7.1 기록용 데이터

- 목적: 영구 보관 및 사후 확인
- 저장 방식: CSV append-only

### 7.2 정적 조회 데이터

- `list.json`: FE 명단 조회와 이름 표시용
- `location.json`: FE location 선택과 로그 화면 노출 기준용
- `logs/access-log.csv`: FE 로그 조회용 원본

### 7.3 분리 이유

- 기록은 누적 이력을 보존해야 한다.
- 조회 가공은 브라우저에서 처리하는 편이 PowerShell 서버보다 유리하다.
- 현재 입영/퇴영 목록은 로그 원본 전체 기준 최종 타입 계산으로 충분하다.

---

## 8. 인터페이스

### 8.1 정적 리소스

```text
GET /index.html
GET /board.html
GET /script.js
GET /style.css
GET /list.json
GET /location.json
GET /logs/access-log.csv
```

규칙:

- 서버는 위 파일을 그대로 서빙한다.
- FE는 `list.json`, `location.json`, `logs/access-log.csv`를 직접 읽어 필요한 가공을 수행한다.
- `logs/access-log.csv`는 원본 CSV 전체를 그대로 내려준다.

### 8.2 입퇴영 요청

```text
POST /access
Content-Type: application/json
```

요청 예시:

```json
{
  "type": "entry",
  "id": "a25-76000001",
  "location": "gate-1"
}
```

정상 응답 예시:

```json
{
  "status": "logged"
}
```

규칙:

- 서버는 `type`, `id`, `location`만 읽는다.
- 서버는 `id`가 `list.json`에 없으면 거부한다.
- 서버는 CSV에 로그를 append한다.

---

## 9. 요청 처리 흐름

### 9.1 정적 리소스 조회

1. FE가 필요한 정적 파일을 직접 요청한다.
2. 서버는 대응 파일을 그대로 응답한다.
3. FE가 JSON/CSV를 읽어 필요한 화면 로직을 수행한다.

### 9.2 `POST /access`

1. client가 `type`, `id`, `location`을 전송한다.
2. 서버가 요청 값을 읽는다.
3. 서버가 `list.json` 기준으로 `id` 허용 여부를 확인한다.
4. 허용되면 CSV에 한 줄 append한다.
5. `{status:"logged"}`를 응답한다.

---

## 10. 로그 저장 형식

입퇴영 기록은 CSV 파일로 저장한다.

### 10.1 컬럼

| 컬럼 | 의미 |
| --- | --- |
| time | UTC ISO 8601 시각 |
| type | `entry` 또는 `exit` |
| location | gate 식별값 |
| id | 군번 |

### 10.2 헤더

```text
time,type,location,id
```

---

## 11. FE 조회 처리 규칙

- FE는 `logs/access-log.csv` 전체를 읽는다.
- FE는 CSV 전체에서 군번별 마지막 로그 1건을 계산한다.
- `전체` 모드에서는 각 행의 `time`을 KST 기준 날짜로 변환한다.
- `전체` 모드에서는 선택한 날짜의 로그만 화면에 남긴다.
- `전체` 모드에서는 군번, 이름, 위치 기준 검색을 수행한다.
- `전체` 모드에서는 최신순/오래된순 정렬을 수행한다.
- `전체` 모드에서는 `location.json`에 없는 location 로그는 표시하지 않는다.
- `현재 입영자` 모드에서는 마지막 로그의 `type`이 `entry`인 사람 전체를 표시한다.
- `현재 퇴영자` 모드에서는 마지막 로그의 `type`이 `exit`인 사람 전체를 표시한다.
- 현재 인원 목록 모드에서는 날짜 선택을 사용하지 않는다.
- 현재 인원 목록 모드에서는 `군번`, `이름`, `최근 위치`, `최근 시각`을 표시한다.
- 로그가 한 번도 없는 명단 인원은 현재 입영/퇴영 목록에 포함하지 않는다.

---

## 12. 오류 처리 원칙

- 잘못된 요청은 단순한 오류 응답으로 끝낸다.
- 한 요청 실패가 전체 서버 종료로 이어지지 않게 한다.
- CSV 저장 실패는 해당 요청 실패로 처리한다.
- 복잡한 재시도나 상세 에러 체계는 넣지 않는다.

---

## 13. 최소 구현 계약

현재 단계의 ACS는 아래를 충족해야 한다.

1. 중앙 HTTP 서버로 실행될 수 있어야 한다.
2. `list.json`, `location.json`, `logs/access-log.csv`를 정적 파일로 서빙할 수 있어야 한다.
3. `POST /access` 요청을 받을 수 있어야 한다.
4. 요청의 `type`, `id`, `location`을 읽어 CSV에 기록할 수 있어야 한다.
5. `id`가 `list.json`에 없으면 요청을 거부할 수 있어야 한다.
6. FE 조회 화면이 CSV 전체를 읽어 로그 모드와 현재 입영/퇴영 전체 목록 모드를 처리할 수 있어야 한다.

---

## 14. 예시 시나리오

### 14.1 정상 입영 요청

- 요청:

```json
{
  "type": "entry",
  "id": "a25-76000001",
  "location": "gate-1"
}
```

- 결과:
  - CSV 1건 추가
  - 응답 `{status:"logged"}`

### 14.2 정상 퇴영 요청

- 요청:

```json
{
  "type": "exit",
  "id": "a25-76000001",
  "location": "gate-1"
}
```

- 결과:
  - CSV 1건 추가
  - 응답 `{status:"logged"}`

### 14.3 FE 조회 화면

- FE 입력:

```text
GET /logs/access-log.csv
```

- FE 처리:
  - CSV 전체 수신
  - 군번별 마지막 로그 타입 계산
  - `전체` 선택 시 KST 날짜 필터링 후 로그 표시
  - `현재 입영자` 선택 시 현재 입영자 전체 명단 표시
  - `현재 퇴영자` 선택 시 현재 퇴영자 전체 명단 표시
  - 화면 렌더링

---

## 15. 구현 비고

- 현재 단계에서 서버는 client 요청을 신뢰한다.
- 서버는 바코드 원문을 알 필요가 없다.
- 서버는 로그 저장과 정적 파일 서빙에만 집중한다.
- 현재 상태판과 상태 API는 더 이상 사용하지 않는다.
- 조회 가공을 FE로 옮겨 PowerShell 서버의 CPU 부담을 줄인다.
