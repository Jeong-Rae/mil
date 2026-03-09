# HANDOFF

## 2026-03-09

### 작업 요약
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
- `acs/list.json` 샘플 데이터 추가: `a25-76046946`, `a01-123456` 기준 장병 목록 구성.
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
