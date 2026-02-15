 HXRM-5VA64아래는 “FE는 표 중심 + 코플루언스(Atlassian) 느낌의 UI 스타일” 요구를 반영해 AI Agent에게 전달 가능한 최종 Markdown 프롬프트이다.

---

# PowerShell Ping Monitor Server + FE Table UI (Confluence-like) – Implementation Specification

## 1. Goal

PowerShell 기반의 백그라운드 서버를 구현한다.

* 서버는 `config.json`의 hosts 목록에 대해 **10초마다 ping**을 수행한다.
* 각 host에 대해 **최신 ping 결과 1건만 메모리에 유지**한다.
* 로컬에서 `file://`로 실행되는 프론트엔드(`index.html`)는 **10초마다 fetch polling**으로 서버에서 최신 결과를 가져와 표(Table)를 갱신한다.
* FE 디자인은 **표 중심**이며, **Confluence(Atlassian) 스타일**(밝은 톤, 카드/패널 느낌, 정돈된 표, 은은한 경계선, 상태 배지)로 구현한다.

---

## 2. Project Structure

```
/project-root
 ├─ index.html
 ├─ script.js
 ├─ style.css
 ├─ server.ps1
 └─ config.json
```

---

## 3. config.json

```json
{
  "hosts": [
    "a.b.c.d",
    "x.y.z.w"
  ]
}
```

요구사항:

* `hosts`: 문자열 배열
* 서버 시작 시 로드 (핫리로드 필수 아님)

---

## 4. Data Model (In-Memory Only)

각 host에 대해 최신 1건만 저장한다.

```json
{
  "dest": "string",
  "rtt": number | null,
  "status": "success" | "timeout" | "error",
  "successedAt": "ISO8601 timestamp | null"
}
```

규칙:

* host당 record 1개만 유지
* 새 결과로 덮어쓰기
* 파일/DB 저장 금지

---

## 5. server.ps1 Requirements

### 5.1 Core Behavior

1. `config.json`에서 hosts 로드
2. **10초마다** 모든 host ping 수행
3. 결과를 host별 최신 1건으로 메모리에 갱신
4. HTTP 서버 제공 (`HttpListener`)
5. 백그라운드 실행 가능

### 5.2 Scheduler

* ping 주기: 10초 고정
* HTTP 요청 처리가 ping 루프에 의해 블로킹되지 않도록 설계

### 5.3 HTTP API

#### Endpoint

* 전체 목록 조회(필수):

```
GET /pings
```

* 단일 host 조회(유지, 선택):

```
GET /ping?host={hostname}
```

#### Response

* `GET /pings` 는 hosts 전부에 대한 최신 결과 배열을 반환한다.
* hosts는 config에 있는 순서대로 반환하는 것을 권장한다.
* Content-Type: `application/json; charset=utf-8`

예시:

```json
[
  { "dest": "a.b.c.d", "rtt": 12, "status": "success", "successedAt": "2026-02-15T12:00:00Z" },
  { "dest": "x.y.z.w", "rtt": null, "status": "timeout", "successedAt": null }
]
```

#### Status Codes

* `/pings`: 정상 시 200
* `/ping?host=`:

  * config에 없으면 404
  * 결과 없으면 204 또는 404 중 하나로 통일
  * 정상 시 200

#### CORS

`file://`에서 호출 가능해야 하므로 CORS 헤더 필수:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

* OPTIONS(preflight) 대응 포함

---

## 6. Frontend Requirements (Confluence-like Table UI)

### 6.1 Main Concept

* 화면의 메인은 **hosts 전체를 보여주는 표(Table)** 이다.
* FE는 `/pings`를 **10초마다 polling**하여 표를 갱신한다.
* Confluence 느낌:

  * 중앙 정렬된 컨테이너(너무 넓지 않게)
  * 상단에 페이지 타이틀과 설명(작게)
  * 표는 가독성 좋은 헤더, 얇은 경계선, hover 강조
  * 상태는 “pill/badge” 형태로 표시
  * 전체 레이아웃은 “카드/패널” 느낌의 박스(white surface + subtle border)

### 6.2 index.html

구성 요소:

* Header 영역:

  * 제목: “Ping Monitor”
  * 보조 텍스트: “Updates every 10 seconds”
  * 서버 상태 표시(예: last updated time, fetch error 표시)
* Controls(선택):

  * “Refresh now” 버튼(즉시 fetch)
  * “Auto refresh” 토글(기본 on)
* Main Table:

  * columns:

    1. Destination (dest)
    2. Status (badge)
    3. RTT (ms)
    4. Succeeded At (표시용 날짜/시간)
    5. Last Updated (FE가 마지막으로 데이터를 렌더링한 시각 또는 서버 응답 기준)
* Footer(선택):

  * 작은 안내문

외부 분리:

* `<script src="script.js"></script>`
* `<link rel="stylesheet" href="style.css" />`

### 6.3 script.js

* 기본 엔드포인트:

  * `GET http://localhost:{port}/pings`
* 동작:

  * 페이지 로드 즉시 1회 fetch 후 렌더
  * `setInterval(fetchAndRender, 10000)` 로 10초마다 갱신
  * “Refresh now” 클릭 시 즉시 fetch
  * “Auto refresh” 토글 off 시 interval 중지
* 렌더링:

  * 배열 데이터를 받아 표의 tbody를 갱신
  * status별 badge 클래스 적용:

    * success / timeout / error
  * rtt가 null이면 “—” 표시
  * successedAt이 null이면 “—” 표시
* 오류 처리:

  * 네트워크/서버 오류 시 상단 상태 영역에 표시
  * 마지막 정상 갱신 시각은 유지

---

## 7. style.css (Confluence-like)

요구 스타일 요소:

* 전체 배경: 아주 옅은 회색 계열
* 컨테이너: 흰 배경 + 얇은 border + radius + padding
* 타이포그래피: 시스템 폰트 스택, 적절한 line-height
* 테이블:

  * 헤더는 약간 진한 텍스트, 옅은 배경
  * row hover 시 미세한 배경 강조
  * 셀 padding 넉넉하게
* Badge:

  * 둥근 pill 형태
  * success/timeout/error 각각 시각적 차별
* 버튼/토글:

  * 단정한 기본 버튼 스타일
  * focus outline 고려(접근성)

주의:

* 외부 CDN, 외부 폰트 import 없이 순수 CSS로 구현

---

## 8. Constraints

* DB 사용 금지
* 결과 파일 저장 금지
* host당 최신 1개 record만 유지
* 서버 ping 갱신: 10초 고정
* FE fetch polling: 10초 고정
* 파일 분리는 반드시 다음 4개로:

  * index.html
  * script.js
  * style.css
  * server.ps1

---

## 9. Deliverables

다음 파일의 “전체 코드”를 생성하라.

* `server.ps1` (HTTP 서버 + ping 스케줄러 + 메모리 저장 + CORS)
* `index.html` (표 중심 UI)
* `script.js` (10초 polling + 렌더링 + 토글/즉시 갱신)
* `style.css` (Confluence-like look & feel)
* `config.json` 예시

또한 포함:

* 실행 방법:

  * 서버 실행 커맨드(포트 포함)
  * `index.html` 로컬 실행 방법

---
