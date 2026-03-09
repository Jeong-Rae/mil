# HANDOFF

## 2026-03-09

### 작업 요약
- `acs/server.ps1`, `acs/index.html`, `acs/board.html`, `acs/script.js`, `acs/style.css`를 신규 구현함.
- `server.ps1`를 함수 분리 구조로 작성함:
  - `Main`
  - `Route-Static-Resource`
  - `Route-API`
  - `Write-Tuple`
  - `Update-Current-Status`
  - `Get-Current-Status`
  - `Get-All-Current-Status`
  - `Restore-Current-Status`
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
- `acs/SPEC.md`를 구현에 맞게 보정함.
  - 엔트리 파일을 `server.ps1`로 수정
  - 정적 파일 서빙 추가
  - `GET /status` 전체 현황 응답 추가

### 산출물
- `acs/server.ps1`
  - 중앙 HTTP 서버 구현
  - 정적 파일 라우팅 + API 라우팅
  - CSV append + 메모리 상태 관리 + 재시작 복원
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
