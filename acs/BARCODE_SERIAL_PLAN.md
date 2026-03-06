# ACS Barcode Serial Plan (Stage 1, Packed ID)

## 1. 목표
- 바코드만으로 `type`(입영/퇴영), `id`(군번) 복원
- `serial`은 랜덤이 아닌 `type+id` 기반 결정론 값으로 계산
- 문자열 길이는 짧게 유지하고, 원문 군번 노출은 최소화
- SPEC의 15초 중복 억제(`serial` 기준) 준수

## 2. 핵심 결정
- 랜덤 시리얼 발급 방식은 사용하지 않는다.
- 바코드에는 원문 `id` 대신 패킹/인코딩한 `ENC_ID`를 넣는다.
- `serial`은 decode 후 `type`, `id`에서 파생 계산한다.

## 3. 군번 패킹 규칙
대상 군번 포맷: `영문1 + 숫자2 + '-' + 숫자8` (예: `a25-76046946`)

### 3.1 정규화/분해
- `id_upper = A25-76046946`
- `letter = A` (`A=0 ... Z=25`)
- `mid2 = 25`
- `tail8 = 76046946`

### 3.2 Mixed-radix 패킹
`packed = ((letterIndex * 100) + mid2) * 100000000 + tail8`

예시:
`packed = ((0 * 100) + 25) * 100000000 + 76046946 = 2576046946`

### 3.3 복원(언패킹)
- `tail8 = packed % 100000000`
- `tmp = packed / 100000000`
- `mid2 = tmp % 100`
- `letterIndex = tmp / 100`
- `id = letter + mid2(2자리) + "-" + tail8(8자리)`

## 4. 인코딩 선택

### 4.1 권장: Base32 Crockford (8자 고정)
- alphabet: `0123456789ABCDEFGHJKMNPQRSTVWXYZ`
- 대문자만 사용 -> 스캐너/콘솔에서 안정적
- 예: `2576046946 -> 02CRPPV2`

### 4.2 압축 우선: Base62 (7자 고정)
- alphabet: `0-9A-Za-z`
- 예: `2576046946 -> 02oKpUI`
- 주의: 대소문자 구분 필요

## 5. 원문 숨김 옵션

### 5.1 Stage 1 기본
- 패킹+Base 인코딩만 사용 (길이 단축 중심)
- 원문이 즉시 읽히진 않지만, 강한 보안은 아님

### 5.2 숨김 강화(권장 옵션)
패킹 값에 키 기반 마스킹을 적용한다.

- `mask38 = low38bits(SHA1("ACS1|K|" + secret + "|" + T))`
- `obf = packed XOR mask38`
- `ENC_ID = Base32(obf)`

복원 시 같은 `secret`, `T`로 `packed = obf XOR mask38` 수행 후 언패킹.

참고: 이 방식은 실무 난독화 용도이며, 고강도 암호가 필요하면 2단계에서 Feistel/FPE 도입.

## 6. 최종 바코드 포맷
`A1` + `T` + `ENC_ID` + `CHK`

- `A1`: 버전(2자)
- `T`: `E`(entry) 또는 `X`(exit)
- `ENC_ID`: 8자(Base32) 또는 7자(Base62)
- `CHK`: 2자리 숫자

### 6.1 CHK 계산
`raw = "A1" + T + ENC_ID`

`chk = (ASCII(raw) 합 % 97)` 을 2자리 10진수로 표현

### 6.2 예시 (Base32, 숨김옵션 OFF)
- `id = a25-76046946`
- `ENC_ID = 02CRPPV2`
- entry 바코드: `A1E02CRPPV247`
- exit 바코드: `A1X02CRPPV266`

## 7. serial 계산 규칙(중복 판정 키)
`canonical = "ACS1|" + T + "|" + ID_UPPER`

`serial = Uppercase( SHA1(canonical) 앞 10 hex )`

예시 (`id = a25-76046946`):
- entry (`T=E`): `AA93F0CC79`
- exit (`T=X`): `D0DFEF34BB`

## 8. Decode 계약
1. `A1` 확인
2. `T` 파싱 (`E/X`)
3. `CHK` 분리 및 검증
4. `ENC_ID` 디코드 (필요 시 역마스킹)
5. `packed` 언패킹으로 `id` 복원
6. `serial` 계산
7. `{ type, id, serial }` 반환

## 9. 테스트 시나리오
- 정상 entry: `A1E02CRPPV247` -> `type=entry`, `id=A25-76046946`
- 정상 exit: `A1X02CRPPV266` -> `type=exit`, `id=A25-76046946`
- 중복: 동일 입력 15초 내 재스캔 -> 무시
- 시간 경과: 16초 후 재스캔 -> 처리
- 오류: `CHK` 불일치/디코드 실패 -> 무시 + 콘솔 오류

## 10. 구현 순서
1. `Pack-Id` / `Unpack-Id` 구현
2. `Encode-Id` / `Decode-Id` (Base32 기본) 구현
3. `Decode-Barcode`를 `A1+T+ENC_ID+CHK` 기준으로 전환
4. `Get-SerialFromTypeAndId` 구현(SHA1 앞 10hex)
5. `Should-IgnoreSerial` 15초 판정 반영
