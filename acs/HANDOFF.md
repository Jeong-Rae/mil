# HANDOFF

## 2026-03-06

### 작업 요약
- `acs/SPEC.md`를 검토하여 바코드 `serial` 요구사항(복원 가능, 결정론적 decode 결과, 15초 중복 억제)을 정리함.
- 시리얼 설계 계획 문서 `acs/BARCODE_SERIAL_PLAN.md`를 신규 작성함.
- 사용자 피드백 반영: 랜덤 발급안을 폐기하고, 군번 기반 결정론적 변환안으로 문서를 전면 수정함.
- 추가 반영: 군번 패킹(Mixed-radix), Base32/Base62 인코딩, 선택적 키 기반 난독화(XOR mask) 방식과 예시를 문서화함.

### 산출물
- `acs/BARCODE_SERIAL_PLAN.md`
  - 단축 바코드 포맷 `A1+T+ENC_ID+CHK` 정의
  - 군번 패킹/복원 수식 및 Base32(권장), Base62(압축) 표현 규칙
  - 선택적 원문 숨김(키 기반 마스킹) 규칙
  - `serial = SHA1(\"ACS1|T|ID_UPPER\")` 앞 10 hex 파생 규칙
  - 체크코드(ASCII 합 % 97), decode 절차, 테스트 시나리오

### 다음 세션 인계 포인트
- 실제 `ACS.ps1` 구현 시 문서의 9장(구현 순서)을 기준으로 함수 단위 반영 권장:
  - `Decode-Barcode`
  - `Pack-Id` / `Unpack-Id`
  - `Encode-Id` / `Decode-Id`
  - `Get-SerialFromTypeAndId`
  - `Should-IgnoreSerial`
  - `Process-Barcode`
- 로그 CSV 컬럼은 스펙 유지(`time,type,place,id,name`), `serial`은 중복 판정/디버깅용 내부 값으로만 사용.
