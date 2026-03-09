# HANDOFF

## 2026-03-09

### 작업 요약
- `acs/SPEC.md`를 현재 합의된 중앙 서버 구조에 맞게 전면 수정함.
- ACS를 gate별 개별 실행형 로컬 스캐너 서비스가 아니라, 요청을 수집하는 가벼운 중앙 PowerShell 서버로 재정의함.
- 역할 분리를 문서에 명시함:
  - client가 바코드를 읽고 `type`, `id`, `location`을 만든다.
  - client가 location별 중복 예외 처리를 담당한다.
  - server는 요청을 신뢰하고 기록과 현재 상태만 관리한다.
- 필요 API를 두 개로 고정함:
  - `POST /access`
  - `GET /status?location=...`
- 기록용 데이터와 현재 상태 데이터를 분리한다고 문서화함:
  - 기록은 CSV append-only
  - 현재 상태는 서버 메모리
  - 재시작 시 CSV를 읽어 메모리 상태 복원
- `acs/BARCODE_SERIAL_PLAN.md`를 현행 서버 범위 밖 문서로 축소 정리함.
- 이번 세션에서는 코드 구현을 하지 않았고, 문서만 갱신함.

### 산출물
- `acs/SPEC.md`
  - 중앙 HTTP 서버 기준으로 전면 재작성
  - 서버 측 decode, server-side dedupe, `list.json`, 이름 조회, `serial`, `-Place` 실행 전제 제거
  - `POST /access`, `GET /status?location=...` 계약 추가
  - 기록 CSV(`time,type,location,id`)와 메모리 상태 분리 규칙 추가
- `acs/BARCODE_SERIAL_PLAN.md`
  - 기존 packed/decode/serial 설계는 현재 서버 범위 밖이라는 메모로 축소

### 다음 세션 인계 포인트
- 다음 구현 단계는 문서 기준으로만 진행한다. 기존 HANDOFF 하단의 `ACS.ps1`/`Start-ACS`/decode 관련 이력은 과거 기록으로 남아 있지만, 현재 SPEC 기준 구현 대상으로 보면 안 된다.
- 구현 시 서버는 가볍게 유지해야 한다.
  - client 입력을 신뢰
  - 최소 검증만 수행
  - 기록 CSV와 메모리 상태만 관리
- 현재 상태 조회는 특정 `location`의 현재 입영 인원 `id` 목록 반환만 요구된다.
- 코드 구현은 아직 시작하지 않았다.

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
