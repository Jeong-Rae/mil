# ACS Barcode Plan Note

이 문서는 이전 로컬 스캐너/서버 측 decode 설계 메모였다.

현재 ACS 기준에서는 아래 이유로 적용하지 않는다.

- 바코드 해석은 client 책임이다.
- 서버는 `type`, `id`, `location`만 받는다.
- 서버는 `serial` 계산이나 중복 판정을 하지 않는다.
- 서버는 기록과 현재 상태 관리만 담당한다.

따라서 packed ID, Base32/Base62, checksum, server-side decode 절차는 현재 SPEC 범위 밖이다.

후속 단계에서 client 측 바코드 포맷을 별도 정의할 필요가 생기면, 이 문서를 새 client 문맥에 맞춰 다시 작성한다.
