# HANDOFF

## 2026-03-11

### 작업 요약
- `acs/board.html`, `acs/script.js`의 `현재 입영자`, `현재 퇴영자` 동작을 로그 필터에서 현재 인원 전체 목록 보기로 변경함.
  - `전체` 선택 시에는 기존처럼 날짜 기반 로그 표를 유지함
  - `현재 입영자` / `현재 퇴영자` 선택 시에는 사람 단위 목록 표로 전환함
  - 현재 인원 목록 컬럼은 `군번`, `이름`, `최근 위치`, `최근 시각`으로 고정함
- 현재 인원 목록 계산 기준을 명확히 함.
  - `logs/access-log.csv` 전체 기준으로 군번별 마지막 로그 1건을 계산함
  - 마지막 `type`이 `entry`면 현재 입영자, `exit`면 현재 퇴영자로 간주함
  - 로그가 한 번도 없는 인원은 현재 목록에서 제외함
- 현재 인원 목록 모드에서는 날짜 필터를 숨기고 사용하지 않도록 조정함.
- `acs/SPEC.md`를 새 조회 계약에 맞게 갱신함.

### 다음 세션 인계 포인트
- `전체`는 로그 모드, `현재 입영자`와 `현재 퇴영자`는 현재 인원 목록 모드다.
- 현재 인원 목록은 로그 행이 아니라 사람 명단 전체를 보여준다.
- 현재 인원 목록은 `location.json` 표시 제한 없이 마지막 로그가 있는 전체 인원을 기준으로 계산한다.
- 검색은 현재 인원 목록에서도 `군번`, `이름`, `최근 위치` 기준으로 동작한다.

### 검증 내역
- `node --check /workspaces/mil/acs/script.js`
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/acs/server.ps1' -Raw)); 'PARSE_OK'"`

### 작업 요약
- `acs/server.ps1`의 `Send-BytesResponse`에서 `ContentLength64` 설정을 주석 처리함.
  - PowerShell 5 환경에서 해당 속성 설정 중 오류가 발생하는 문제를 우선 회피함
  - 응답 종료는 기존처럼 `OutputStream.Close()`에 맡김

### 다음 세션 인계 포인트
- PowerShell 5 호환성 때문에 현재는 `Content-Length`를 명시하지 않는다.
- 정적 파일/JSON 응답은 스트림 write 후 close로 마무리한다.

### 검증 내역
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/acs/server.ps1' -Raw)); 'PARSE_OK'"`

### 작업 요약
- `acs/server.ps1`에서 `GET /status`와 location 기반 현재 상태 메모리 관리 로직을 제거함.
  - `Set-CurrentStatus`, `Get-CurrentStatus`, `Get-AllCurrentStatus`, `Import-CurrentStatus`를 제거함
  - 서버 책임은 `POST /access`와 정적 파일 서빙만 남김
- `acs/board.html`, `acs/script.js`를 로그 전용 화면으로 단순화함.
  - `현황 보기` 전환 버튼과 상태 카드 영역 제거
  - 로그 필터에 `전체 / 현재 입영자 / 현재 퇴영자` 선택 추가
- `acs/script.js`의 로그 처리 방식을 바꿈.
  - `logs/access-log.csv` 전체를 먼저 읽고 파싱함
  - CSV 전체 기준으로 군번별 마지막 `type` 맵을 계산함
  - 선택 날짜의 로그에 대해 현재 상태 필터를 교집합으로 적용함
- `acs/SPEC.md`를 현재 계약 기준으로 다시 정리함.
  - 서버 API에서 `GET /status` 제거
  - FE 로그 필터 규칙에 현재 입영자/퇴영자 계산 기준 추가

### 다음 세션 인계 포인트
- 현재 ACS 서버 API는 `POST /access`만 남는다.
- `location`은 이제 기록용 필드와 로그 검색용 컬럼으로만 사용한다.
- `현재 입영자/현재 퇴영자`는 선택 날짜 기준이 아니라 CSV 전체의 마지막 로그 타입 기준이다.
- 로그 화면에는 선택 날짜의 행만 보이고, 현재 상태 필터는 그 행들에만 추가 적용된다.
- 반영 확인 시에는 실행 중인 `acs/server.ps1`를 재시작해야 한다.

### 검증 내역
- `node --check /workspaces/mil/acs/script.js`
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/acs/server.ps1' -Raw)); 'PARSE_OK'"`

### 작업 요약
- `acs/server.ps1`에서 동적 조회 API를 줄이고, 서버 책임을 `POST /access`, `GET /status`, 정적 파일 서빙으로 축소함.
  - `GET /members`, `GET /locations`, `GET /logs`를 제거함
  - `list.json`, `location.json`, `logs/access-log.csv`를 정적 파일로 직접 서빙하도록 확장함
- `acs/server.ps1`의 `POST /access` 성공 응답을 다시 `{status:"logged"}`로 단순화함.
- `acs/script.js`를 수정해 FE가 `/list.json`, `/location.json`, `/logs/access-log.csv`를 직접 읽도록 변경함.
  - 로그 날짜 필터링, 검색, 정렬은 전부 브라우저에서 처리함
  - 스캐너 성공 메시지 이름은 서버 응답이 아니라 `list.json` 캐시에서 가져오도록 바꿈
- `acs/SPEC.md`를 현재 계약에 맞게 전면 정리함.
  - 정적 리소스 기반 조회 구조와 최소 API 계약만 남김

### 다음 세션 인계 포인트
- 현재 서버 API는 `POST /access`, `GET /status`만 남는다.
- FE 데이터 소스는 `/list.json`, `/location.json`, `/logs/access-log.csv`다.
- 현황판 로그 뷰는 더 이상 서버에 날짜별 로그 API를 호출하지 않는다.
- `POST /access` 성공 응답에는 더 이상 `id`, `name`이 없다.
- 반영 확인 시에는 `acs/server.ps1` 재시작이 필요하다.

### 검증 내역
- `node --check /workspaces/mil/acs/script.js`
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/acs/server.ps1' -Raw)); 'PARSE_OK'"`
- `curl -sS http://127.0.0.1:8899/location.json`
- `curl -sS http://127.0.0.1:8899/list.json`
- `curl -sS http://127.0.0.1:8899/logs/access-log.csv`

### 작업 요약
- `acs/server.ps1`에 `GET /members`를 추가해 `list.json`의 `id,name,unit` 명단을 FE로 그대로 반환하도록 확장함.
- `acs/board.html`, `acs/script.js`를 수정해 현황판 카드에 이름을 함께 표시하고, 로그 표에 이름 컬럼과 이름 검색을 추가함.
- `acs/server.ps1`의 `POST /access` 성공 응답에 `name`을 추가함.
  - 응답 형식이 `{status:"logged",id:"...",name:"..."}`가 되도록 확장함
- `acs/script.js`의 스캐너 성공 메시지가 서버 응답의 `name`을 우선 사용하도록 조정함.
  - 예: `김일병님 퇴영입니다`
- 스캐너 화면에 임시로 붙였던 별도 군번/이름 확인 패널은 제거함.
- `acs/index.html`, `acs/board.html`, `acs/script.js`, `acs/style.css`의 셀렉터를 `loc-*`, `msg-*`, `bd-*`, `log-*` 축약형으로 정리함.
- `acs/SPEC.md`를 현재 계약에 맞게 보정함.
  - `GET /members` API와 FE 명단 조회 흐름을 문서화함
  - 현재 상태 규칙을 실제 구현 기준(`entry`만 현재 상태에 남김)으로 정리함

### 다음 세션 인계 포인트
- `list.json`은 이제 허용 군번 검증과 FE 명단 조회의 공용 소스다.
- `GET /members`는 서버 시작 시 읽은 명단 배열을 그대로 반환한다.
- 현황판 로그 검색은 군번, 이름, 위치를 기준으로 수행한다.
- 스캐너 성공 메시지용 이름은 `POST /access` 응답의 `name`에서 받는다.
- 스캐너 페이지에는 더 이상 별도 명단 조회 패널이 없다.
- 서버 재시작 전에는 기존 응답 형식이 남아 있을 수 있으므로, 반영 확인 시 `acs/server.ps1` 재시작이 필요하다.

### 검증 내역
- `node --check /workspaces/mil/acs/script.js`
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/acs/server.ps1' -Raw)); 'PARSE_OK'"`

### 작업 요약
- `acs/board.html`, `acs/script.js`에서 현황판 기본 진입 뷰를 `현황 보기`에서 `로그 보기`로 변경함.
  - 초기 활성 전환 버튼을 `로그 보기`로 바꿈
  - 초기 hidden 상태를 로그 테이블 기준으로 맞춤
  - 보드 페이지 초기화 시 첫 조회 API가 `/status`가 아니라 `/logs`가 되도록 조정함

### 다음 세션 인계 포인트
- `board.html` 기본 진입 화면은 이제 로그 뷰다.
- 상태 카드는 여전히 같은 페이지에 남아 있으며, `현황 보기` 버튼으로 즉시 전환된다.
- polling 구조는 유지되고, 최초 진입 시점과 현재 활성 뷰 기준만 로그 쪽으로 바뀌었다.

### 검증 내역
- `node --check /workspaces/mil/acs/script.js`

### 작업 요약
- `acs/server.ps1`의 현재 상태 갱신 로직을 수정함.
  - 기존에는 `Set-CurrentStatus`가 `entry`/`exit`를 구분하지 않고 항상 해당 location에 `id`를 다시 넣었음
  - 이제는 모든 location에서 해당 `id`를 먼저 제거하고, `type`이 `entry`일 때만 요청 location에 다시 추가함
- 이 수정으로 `EN` 직후 `EX`를 같은 location에서 수행한 경우 현황표에 인원이 남아 있던 문제가 해소됨.
- CSV 재복원(`Import-CurrentStatus`)도 같은 함수를 사용하므로, 서버 재시작 후 현황표도 동일하게 바로잡힘

### 다음 세션 인계 포인트
- `GET /status`의 기준은 여전히 "마지막 entry location"이다.
- `exit`는 현재 상태에서 `id`를 제거만 하고, 어떤 location에도 남기지 않는다.
- 실사용 확인 시에는 서버 프로세스를 재시작해야 수정된 `acs/server.ps1`이 반영된다.

### 검증 내역
- `pwsh -NoLogo -NoProfile -Command '...Set-CurrentStatus...Import-CurrentStatus...'`
  - `entry` 후 `{"location":"위병소","ids":["a25-76000001"]}` 확인
  - 직후 `exit` 후 `{"location":"위병소","ids":[]}` 확인
  - `entry -> exit` CSV 재복원 후에도 `{"location":"위병소","ids":[]}` 확인

### 작업 요약
- `acs/index.html`, `acs/script.js`, `acs/style.css`의 스캐너 진입 방식을 입력형 `prompt`에서 `select` 기반 모달로 변경함.
  - 진입 시 `/locations` 후보 목록을 채운 모달을 자동으로 열어 location을 선택하게 함
  - 선택 UI는 브라우저 입력창이 아니라 `select` 드롭다운만 사용함
  - 선택 완료 전에는 기존처럼 스캐너 패널에 진입하지 않음
  - 취소하거나 모달을 닫은 경우에는 스캐너 진입을 막고, 페이지의 `위치 선택` 버튼으로 다시 열 수 있게 함
- 기존 바코드 처리 흐름은 유지함.
  - 선택된 location은 세션 동안 고정되어 `POST /access`에 포함됨
  - 선택 후 바코드 입력 포커스 유지, 중복 스캔 억제, 결과 메시지 표시는 그대로 유지함

### 다음 세션 인계 포인트
- 현재 스캐너 진입 UX는 `dialog` + `select` 기반 모달이다.
- location 선택 실패나 취소 시 위치 선택 패널은 남아 있고, `위치 선택` 버튼으로 모달을 다시 열 수 있다.
- location 후보는 항상 `GET /locations` 응답으로 `select`에 다시 채운다.

### 검증 내역
- `node --check /workspaces/mil/acs/script.js`
- `curl -sS http://127.0.0.1:8888/`
  - 위치 선택용 `dialog`, `select`, `선택 완료` 버튼이 정적 HTML에 포함되는 것 확인
- `curl -sS http://127.0.0.1:8888/script.js`
  - `populateLocationSelect`, `openLocationDialog`, `dialogForm` submit 처리 코드가 서빙되는 것 확인
- `curl -sS http://127.0.0.1:8888/locations`
  - location 후보 응답 확인

### 작업 요약
- `acs/location.json`을 추가하고, 서버가 시작 시 location 후보 배열을 읽도록 확장함.
  - 구조는 `[{"location":"gate-1"}]` 고정
  - `acs/server.ps1`에 `GET /locations`를 추가해 이 배열을 그대로 반환함
- `acs/index.html`, `acs/script.js`, `acs/style.css`를 수정해 스캐너 진입 시 location을 먼저 선택하도록 변경함.
  - 자유 입력 `location` 필드를 제거함
  - `/locations` 응답으로 select 후보를 채움
  - location 선택 전에는 바코드 스캔을 시작하지 않음
  - 선택 후에는 해당 location을 고정값으로 사용해 `POST /access`를 보냄
- `acs/script.js`의 현황판 렌더링을 `location.json` 기준 노출 구조로 조정함.
  - `/status` 전체 응답을 받더라도 `location.json`에 있는 location 카드만 그림
  - 등록된 location인데 현재 상태가 없으면 빈 카드로 유지함
  - `/logs` 응답에서도 `location.json`에 없는 location row는 화면에서 숨김
- 서버 호환성 동작은 유지함.
  - `POST /access`는 `location.json`에 없는 location도 계속 허용함
  - 미등록 location 데이터는 로그와 상태 계산에는 남지만 UI에만 표시하지 않음
- `acs/SPEC.md`를 현재 계약에 맞게 보정함.
  - `location.json` 관리와 `GET /locations` API를 추가
  - 스캐너 선택 흐름과 현황판 노출 정책을 문서화함
- `acs/server.ps1`에 `GET /logs` 일별 로그 조회 API를 추가함.
  - query `day=YYYY-MM-DD`를 선택적으로 받음
  - 값이 없으면 현재 KST 날짜를 기본값으로 사용함
  - CSV에서 해당 KST 날짜의 `time,type,location,id` 전체 로그만 추려 배열로 반환함
  - 잘못된 날짜 형식은 `400` + `{status:"rejected",message:"day must be yyyy-mm-dd"}`로 거부함
- `acs/board.html`, `acs/script.js`, `acs/style.css`를 확장해 한 페이지 전환형 현황판을 구현함.
  - `현황 보기` / `로그 보기` 전환 버튼 추가
  - 로그 보기에는 날짜 입력, 군번/위치 통합 검색, 최신순/오래된순 정렬 추가
  - 로그 검색과 정렬은 FE에서만 수행하고, 서버는 해당 날짜 전체 로그만 반환함
  - 기존 현황판 polling 구조는 유지하되 현재 활성 뷰에 맞는 API를 주기적으로 다시 조회함
- `acs/SPEC.md`를 현재 구현 기준으로 보정함.
  - `GET /logs` 계약과 KST 날짜 기준을 명시
  - 현황판 로그 뷰가 FE 필터/정렬을 수행한다는 점을 반영
- `acs/script.js`의 스캐너 입력 흐름에서 `form submit` 경로를 제거함.
  - `submit` listener를 제거함
  - Enter 입력과 CR/LF 입력 핸들러가 `requestSubmit()` 대신 `submitAccess()`를 직접 호출함
  - `submitAccess()` 내부에서 바로 `postAccess()`로 `POST /access` 요청을 보냄
- `acs/script.js`를 ES6 스타일 기준으로 다시 정리함.
  - 함수 선언을 `const` + 화살표 함수 중심으로 정리함
  - 가능한 곳에 구조분해 할당을 적용함
  - `group?.location`, `data?.message`, `loc?.value`처럼 optional chaining으로 축약함
  - 한 줄로 충분한 `if`는 중괄호 없이 정리함
  - 짧은 블록 스코프 임시 변수는 `requestError`보다 `err`처럼 짧은 이름을 우선함
  - 미사용 `catch` 바인딩은 제거하고, 지역 변수는 `response`/`payload`보다 `res`/`data`처럼 짧게 정리함
- 기존 동작은 유지함.
  - 15초 중복 스캔 억제 유지
  - 성공/오류 메시지 처리 유지
  - 보드 polling 및 수동 새로고침 유지

### 다음 세션 인계 포인트
- location 후보의 기준 데이터는 `acs/location.json` 한 곳이다.
- 서버는 시작 시 `location.json`을 1회 로드하고, `GET /locations`는 그 메모리 값을 그대로 반환한다.
- 스캐너는 이제 자유 입력이 아니라 진입 직후 location 선택 후에만 동작한다.
- 현황판은 admin용 전체 화면을 유지하지만, 카드와 로그 표시는 `location.json`에 등록된 location만 노출한다.
- 구버전/직접 호출 클라이언트가 미등록 location으로 `POST /access`를 보내도 서버는 계속 `logged` 처리한다.
- 로그 조회 API는 `GET /logs` 한 개만 추가되었고, 기존 `POST /access`와 `GET /status` 계약은 바꾸지 않았다.
- 로그 날짜 기준은 서버/클라이언트 모두 KST 고정이다.
- 로그 응답은 원본 CSV 컬럼인 `time,type,location,id`만 포함한다.
- `board.html`은 별도 로그 페이지를 만들지 않고, 같은 페이지 안에서 상태/로그 뷰를 전환한다.
- 로그 검색과 정렬은 서버가 아니라 `acs/script.js`에서 수행한다.
- 현재 스캐너 페이지는 `form` 엘리먼트를 마크업으로는 유지하지만, 요청 전송은 더 이상 submit 이벤트에 의존하지 않는다.
- 바코드 입력에서 Enter 또는 줄바꿈이 들어오면 클라이언트 핸들러가 즉시 `postAccess()`를 호출한다.
- 이번 변경은 프론트 JS 구조 정리와 요청 트리거 변경만 포함하며, 서버 API나 HTML 구조는 바꾸지 않았다.

### 검증 내역
- 실제 서버 실행 후 아래 API를 직접 호출해 확인함.
  - `GET /locations` 반환 확인
  - 등록 location `POST /access` 성공 확인
  - 미등록 location `POST /access`도 성공 확인
  - `GET /status`
  - `GET /status?location=gate-2`
  - `GET /status?location=legacy-gate-2`
  - `GET /logs?day=2026-03-11`
  - 잘못된 `day`로 `GET /logs?day=2026-13-99` 호출 시 `400` 거부 확인
- 검증 중 append된 테스트 로그 4건은 `acs/logs/access-log.csv`에서 제거해 작업 산출물에 남기지 않음.

## 2026-03-09

### 작업 요약
- `acs/index.html`, `acs/board.html`의 화면 제품명을 `ACS`에서 `7136부대 위치 정보 관리 시스템`으로 교체함.
- `acs/index.html`, `acs/board.html`의 스캐너/현황판 설명을 한국어 기준으로 정리함.
- `acs/style.css`의 전체 색상 체계를 녹색 계열에서 파랑/흰색 계열로 변경함.
  - 배경을 단색 파랑으로 변경
  - 상단 헤더를 군청색 단색 배너 스타일로 변경
  - 버튼, 패널, 현황 카드의 포인트 색을 청색 기준으로 정리
- `acs/index.html`, `acs/board.html`의 설명 문구를 제거하고 제목 중심의 단순한 헤더로 다시 정리함.
- `acs/style.css`의 그림자, 여백, 모서리, 버튼 표현을 줄여 전체 화면을 더 단순하게 조정함.
- `acs/script.js` 반복문은 `forEach`보다 `for...of`를 우선하도록 정리함.
- `acs/server.ps1`의 현재 상태 갱신을 location overwrite 구조로 조정함.
  - `entry`/`exit`와 무관하게 전체 현황의 위치는 마지막으로 입력된 `location`으로 덮어씀
  - 현황에 없던 사람이 먼저 `exit`를 보내도 성공하고, 해당 `location`이 현재 위치가 됨
- `acs/script.js`의 스캐너 중복 처리를 상태 조회 기반이 아니라 `같은 gate + 같은 바코드 + 15초` 기준으로 단순화함.
- `acs/script.js`의 `handleSubmit()` 복잡도를 줄이기 위해 중복 처리/메시지/입력 정리 로직을 helper로 분리함.
- `acs/script.js`의 비동기 흐름을 Promise chain 대신 `async`/`await` 중심으로 정리함.
- `acs/script.js`의 DOM 접근을 전역 element 캐싱 대신 `$()` 조회 방식으로 정리함.
- `acs/script.js`의 보드 렌더링에서 `innerHTML` 문자열 조합을 제거하고 DOM 생성 + `replaceChildren` 방식으로 변경함.
- `acs/script.js`의 함수 내부 지역 변수명은 짧은 이름 위주로 다시 정리함.
- `acs/board.html`, `acs/script.js`의 보드 상태 표시를 `정상`/`실패` 2개 상태로 단순화함.
  - 갱신 중에는 상태 문구를 바꾸지 않음
  - 조회 성공 시 `정상`
  - 조회 실패 시 `실패`
- `acs/server.ps1`에 `list.json` 허용 군번 검증을 추가함.
  - 서버 시작 시 `list.json`을 읽어 허용 군번 집합을 로드함.
  - `POST /access`는 `list.json`에 없는 `id`면 기록 전에 `400` + `{status:"rejected",message:"id is not allowed"}`로 거부함.
- `acs/SPEC.md`를 현재 동작에 맞게 보정함.
  - 현재 단계 포함 범위에 `list.json` 기반 허용 군번 검증 추가
  - 서버 책임과 요청 흐름에 허용 군번 검증 단계 반영

### 다음 세션 인계 포인트
- 현재 `acs` 웹 UI 노출명은 `7136부대 위치 정보 관리 시스템` 기준이다.
- 이번 변경은 사용자 요청에 맞춘 프런트 정적 화면 위주 수정이다.
  - 서버 로그 문구와 `SPEC.md` 내부의 `ACS` 명칭은 유지했다.
  - 기능 동작 로직은 변경하지 않았다.
- 현재 ACS 서버는 `type`/`location`은 기존처럼 신뢰하지만, `id`는 `acs/list.json`에 있어야만 로그에 기록한다.
- 현재 상태는 군번 기준 last write win이다.
  - `entry`/`exit`는 로그에는 남지만, 전체 현황 위치 계산은 마지막 `location`만 사용한다.
  - 현황에 없던 군번이 `exit`부터 와도 거부하지 않고 그 `location`으로 반영한다.
- `list.json`이 없거나 JSON 파싱에 실패하면 서버 시작 단계에서 예외로 종료된다. 현재 단계에서는 fallback을 두지 않았다.

### 작업 요약
- `acs/server.ps1`, `acs/index.html`, `acs/board.html`, `acs/script.js`, `acs/style.css`를 신규 구현함.
- `server.ps1`를 함수 분리 구조로 작성함:
  - `Start-AcsServer`
  - `Invoke-StaticResourceRoute`
  - `Invoke-ApiRoute`
  - `Add-AccessRecord`
  - `Set-CurrentStatus`
  - `Get-CurrentStatus`
  - `Get-AllCurrentStatus`
  - `Import-CurrentStatus`
- 중앙 서버가 정적 파일 서빙, `POST /access`, `GET /status`, `GET /status?location=...`를 제공하도록 구현함.
- 로그를 `logs/access-log.csv`에 `time,type,location,id` 형식으로 append 저장하도록 구현함.
- 서버 시작 시 기존 CSV를 읽어 현재 상태 메모리를 복원하도록 구현함.
- `index.html`을 스캐너 입력 화면으로 구현함.
  - `location` 입력칸
  - barcode 입력칸
  - 처리 결과 메시지 영역
  - `board.html` 이동 링크
- `board.html`을 전체 location 현황판으로 구현함.
  - 전체 location 현재 인원 표시
  - 수동 새로고침 버튼
  - `index.html` 이동 링크
- `script.js`를 두 페이지 공용으로 구현함.
  - 함수는 모두 top-level에 둠
  - `body` 끝에서 로드되는 전제
  - `EN`/`EX` 바코드 파싱
  - Enter/CRLF 자동 submit
  - barcode input 상시 포커스 유지
  - 클라이언트 상태 기반 중복 안내
  - board 5초 polling + 수동 새로고침
- `POST /access` 거부 시 `{status,message}` JSON 응답을 반환하고, 클라이언트는 메시지 영역에 오류를 표시한 뒤 포커스를 복귀하도록 구현함.
- strict mode에서 누락 필드 접근이 500으로 튀는 문제를 수정함.
  - 서버 요청 필드는 안전한 helper로 읽도록 변경
  - 누락 필드 요청은 `400` + `{status:"rejected",message:"type, id, location are required"}` 로 응답함
- `server.ps1`의 들여쓰기 깊이를 줄이기 위한 리팩터링을 추가로 적용함.
  - `Send-RejectedResponse`, `Send-InternalServerError`로 에러 응답을 분리
  - `New-AccessLogFile`, `New-AccessRecordLine`로 로그 초기화/레코드 문자열 생성을 분리
  - `Test-AccessRecordRow`로 CSV replay 유효행 판정을 분리
  - `Read-AccessPayload`, `Invoke-StatusRoute`, `Invoke-AccessRoute`, `Invoke-Request`를 추가해 `Invoke-ApiRoute`와 `Start-AcsServer`를 얇게 정리
  - 한 줄로 충분한 guard/dispatch는 한 줄로 축약하고, 중첩 `try/if` 블록은 helper 함수로 이동
- `GET /status`가 빈 배열일 때 `ConvertTo-Json -AsArray`가 `$null`을 반환해 500이 나는 문제를 수정함.
  - `Send-JsonResponse`에서 빈 array 응답은 `[]`로 고정
- `acs/SPEC.md`를 구현에 맞게 보정함.
  - 엔트리 파일을 `server.ps1`로 수정
  - 정적 파일 서빙 추가
  - `GET /status` 전체 현황 응답 추가

### 산출물
- `acs/server.ps1`
  - 중앙 HTTP 서버 구현
  - 정적 파일 라우팅 + API 라우팅
  - CSV append + 메모리 상태 관리 + 재시작 복원
  - request dispatch 및 에러 응답 helper로 들여쓰기 깊이 완화
- `acs/index.html`
  - 스캐너 입력 화면
- `acs/board.html`
  - 전체 현황판 화면
- `acs/script.js`
  - 공용 프론트 로직
- `acs/style.css`
  - 공용 스타일
- `acs/SPEC.md`
  - `server.ps1` 기준으로 보정
  - `GET /status` 전체 현황 응답 추가
- `acs/BARCODE_SERIAL_PLAN.md`
  - 기존 packed/decode/serial 설계는 현재 서버 범위 밖이라는 메모로 축소

### 다음 세션 인계 포인트
- 기존 HANDOFF 하단의 `ACS.ps1`/`Start-ACS`/decode 관련 이력은 과거 기록이다. 현재 구현 기준 엔트리 파일은 `server.ps1`이다.
- 구현 시 서버는 가볍게 유지해야 한다.
  - client 입력을 신뢰
  - 최소 검증만 수행
  - 기록 CSV와 메모리 상태만 관리
- 현재 상태 조회는 두 경로가 있다.
  - `GET /status?location=...`: 특정 location
  - `GET /status`: 전체 location
- 검증 완료:
  - `pwsh -NoLogo -NoProfile -File ./server.ps1`
  - `curl -sS -X POST http://127.0.0.1:8888/access ...`
  - `curl -sS http://127.0.0.1:8888/status?location=gate-1`
  - `curl -sS http://127.0.0.1:8888/status`
  - `curl -sS -X POST http://127.0.0.1:8888/access -H 'Content-Type: application/json' --data '{"id":"oops"}'`
  - `pwsh` 파서 검사: `PARSE_OK`

## 2026-03-06

### 작업 요약
- `acs/ACS.ps1`를 함수형 엔트리(`Start-ACS`) 중심으로 재구성하여, 스크립트 파일 실행이 막힌 환경에서도 복사 붙여넣기 후 수동 시작이 가능하도록 수정함.
- 전역 `param(...)`, top-level `Set-StrictMode`, top-level `$ErrorActionPreference`를 제거하여 복사 붙여넣기 시 사용자 PowerShell 세션에 불필요한 부작용이 남지 않도록 조정함.
- 스크립트 자동 시작 판정을 스크립트 로드 시점의 invocation 정보 기준으로 수정하여, 직접 실행 시에는 자동 시작되고 dot-source / 붙여넣기 로드 시에는 자동 시작되지 않도록 보강함.
- `acs/ACS.ps1`의 앱 루트 해석 로직을 수정하여, dot-source 후 `Main`을 수동 호출하는 경우에도 `$MyInvocation.MyCommand.Path` 예외가 발생하지 않도록 보강함.
- `acs/SPEC.md`를 검토하여 바코드 `serial` 요구사항(복원 가능, 결정론적 decode 결과, 15초 중복 억제)을 정리함.
- 시리얼 설계 계획 문서 `acs/BARCODE_SERIAL_PLAN.md`를 신규 작성함.
- 사용자 피드백 반영: 랜덤 발급안을 폐기하고, 군번 기반 결정론적 변환안으로 문서를 전면 수정함.
- 추가 반영: 군번 패킹(Mixed-radix), Base32/Base62 인코딩, 선택적 키 기반 난독화(XOR mask) 방식과 예시를 문서화함.
- `acs/ACS.ps1` 구현 추가: 함수 분리 + `Main` 엔트리 구조로 1단계 로컬 처리 흐름을 코드화함.
- `acs/list.json` 샘플 데이터 추가: `a25-76000001`, `a01-123456` 기준 장병 목록 구성.
- 짧은 꼬리번호 군번도 처리 가능하도록 `Unpack-Id`가 tail 선행 0을 제거하도록 조정함.

### 산출물
- `acs/BARCODE_SERIAL_PLAN.md`
  - 단축 바코드 포맷 `A1+T+ENC_ID+CHK` 정의
  - 군번 패킹/복원 수식 및 Base32(권장), Base62(압축) 표현 규칙
  - 선택적 원문 숨김(키 기반 마스킹) 규칙
  - `serial = SHA1(\"ACS1|T|ID_UPPER\")` 앞 10 hex 파생 규칙
  - 체크코드(ASCII 합 % 97), decode 절차, 테스트 시나리오
- `acs/ACS.ps1`
  - `Load-SoldierList`, `Decode-Barcode`, `Should-IgnoreSerial`, `Write-AccessLog`, `Process-Barcode`, `Main` 구현
  - `Start-ACS` 공개 엔트리 추가, `Main`은 호환용 래퍼로 유지
  - 도트소싱/복사 붙여넣기 시 자동 실행되지 않고, 스크립트 직접 실행 시에만 시작
  - 앱 루트는 로드 시점에 `$PSScriptRoot`/`$PSCommandPath` 우선으로 고정하고, 인터랙티브 세션에서는 현재 작업 디렉토리로 폴백
  - 다른 작업 디렉토리에서도 시작할 수 있도록 `-AppRoot` 지원
  - 현재 구현은 문서의 기본 경로대로 Base32 `ENC_ID`(8자) decode 기준
- `acs/SPEC.md`
  - 파일 직접 실행 외에 `Start-ACS -Place ...` 복사 붙여넣기 실행 모드와 `-AppRoot` 사용 예시 추가
- `acs/list.json`
  - 샘플 장병 2건 포함

### 다음 세션 인계 포인트
- 실제 `ACS.ps1` 구현 시 문서의 9장(구현 순서)을 기준으로 함수 단위 반영 권장:
  - 현재 `Decode-Barcode`/`Unpack-Id`/`Get-SerialFromTypeAndId`/`Should-IgnoreSerial`/`Process-Barcode`는 구현 완료
  - 필요 시 다음 단계에서 `Encode-Barcode` 또는 Base62 decode 경로 추가 가능
- 로그 CSV 컬럼은 스펙 유지(`time,type,place,id,name`), `serial`은 중복 판정/디버깅용 내부 값으로만 사용.
- 실행 전 `acs/list.json` 필요. 없거나 파싱 실패 시 시작 단계에서 종료.
- 현재 decode 결과의 tail은 선행 0 제거 문자열로 정규화되므로 `a01-123456` 같은 목록과 직접 매칭된다.
- 검증 완료:
  - `pwsh -File ./ACS.ps1 gate-1`
  - `pwsh -Command ". ./ACS.ps1; Main -Place 'gate-1'"`
  - `pwsh -Command "$src = Get-Content ./ACS.ps1 -Raw; Invoke-Expression $src; Start-ACS -Place 'gate-1' -AppRoot '/workspaces/mil/acs'"`
  - 위 세 경로 모두 정상 시작 후 `exit` 종료 확인.
