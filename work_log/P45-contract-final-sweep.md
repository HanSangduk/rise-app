---
id: P45
title: 계약 축 마감 스윕 — 최종 적대 리뷰 2건 + 확정분 수리
status: 완료
domain: cross
created: 2026-08-30
completed: 2026-08-30
---

# P45 — 계약 축 마감 스윕 (P36→P44 아크의 최종 게이트)

## 목표

람 지시("마지막으로 교차 검증·검토·자문자답으로 완성도 높여 마무리"). 직전 적대 리뷰(P37/P38) 이후 랜딩분 — P39 시트·P42 변형·P43 데모·P44 서명 — 을 백엔드/앱 2방향 최종 적대 리뷰로 걸고, 확정분을 즉시 수리. 오케스트레이터는 문서·계층 정합(제18조 3자, v2.15→v2.21 체인, README 인덱스, 어드민 타입 갭)을 직접 검사.

## 결정 사항

- 어드민 Contract 타입의 v2.18/v2.21 필드 부재는 **의도적 유지** — 모르는 필드 무시라 무해하고, 표시 UI 없이 타입만 추가하면 죽은 타입. 어드민 계약 열람 화면 후속(P36 H의 어드민 반절)과 함께 간다.
- 계약서doc 마스터와 자산의 제18조② 줄바꿈 차이는 수용 — 마스터는 76자 랩 관례, 렌더러는 소프트랩 병합이라 렌더 동일. 자산 2종끼리는 바이트 동일이 불변식.
- 가로 회전 게이트 고착(M)·Android 뒤로가기 시트 닫힘(관찰)은 후속 — 세로 복귀로 회복 가능 + 정식 경로(다시 보기) 존재. 성급한 화면 잠금보다 UX 관찰 후 결정.

## 진행 단계

- [x] 백엔드 최종 적대 리뷰 — **SHIP**: 발행 래치 OFF 배포·데모 훅 Firestore 도달 불가·2해시 분리(골든 python 독립 재현)·void↔sign 경합·merge-write 절 보존·변형 선택 합성 게이트 전부 CONFIRMED. 검증 게이트 실측 공격(url-safe·data URI·무패딩·0치수·64KB·MIME 개행) 전부 방어. 비차단 1건 발견 → 아래 수리
- [x] 앱 최종 적대 리뷰 — **FIX-FIRST(H 1)**: 상태기계·래치·wire·자산 패리티·골든 실효성은 견고. H 1·M 2·L 3 발견 → 아래 수리/이월
- [x] 오케스트레이터 정합 검사: 제18조② 자산 2종 바이트 동일(마스터는 랩만 다름)·버전 체인 v2.15→v2.21 무결(v2.20 위치 역전은 재번호 사건의 기록물)·README P36~P44 전부 등재
- [x] 확정분 수리 + 재검증(아래)

## 변경 파일 (수리분)

- `app/lib/features/my/presentation/contract_body.dart` — **[H] {{계약 체결일}} KST 접기** — 서버 증적은 UTC 순간이라 KST 00~09시 서명(하루의 37.5%)은 UTC 날짜가 전날: 법적 문서의 체결일과 바로 아래 체결 정보(toKst 적용)가 하루 모순이었다
- `app/lib/features/my/presentation/widgets/contract_detail_sheet.dart` — 발송일·서명일 행, `_headline` KST 통일(한 시트 두 시간축 혼재 해소) + **[M] 서명 도킹 블록 signed 게이트**(DTO 관용 파싱이라 손상·적대 응답이 미체결 문서에 "회원 서명"을 그릴 수 있었다 — 거짓 신호 금지)
- `app/lib/features/my/presentation/widgets/contract_sign_sheet.dart` — 발송일 KST + **[L] `_submit` 재진입 가드**(이중 탭 방지가 버튼 리빌드 1프레임 창에만 의존)
- `app/test/.../contract_detail_body_test.dart` — **KST 자정 경계 픽스처**(UTC 8/29 22:00 = KST 8/30): 문서 체결일 08-30 · 08-29 잔재 시트 전체 0 단언
- `backend/internal/api/handlers_contracts.go` — **[L→수리] IEND 접미 검사**: DecodeConfig는 IHDR만 읽어 절단 PNG(렌더 불가)가 증거로 저장될 수 있었다. IEND 12바이트 접미 검사로 절단본+IEND 뒤 쓰레기 동시 차단(압축 해제 없음 — 폭탄 표면 불변). 크기 검사 **뒤** 배치로 기존 픽스처 메시지 보존
- `backend/internal/api/service_contract_sign_test.go` — 깨진 헤더 픽스처에 유효 IEND 부착(DecodeConfig 층 검증 보존, 층별 한 행) + 절단 PNG·IEND 뒤 쓰레기 신규 2행 + `signPadPNGTruncated` 헬퍼

## 검증

- 백엔드: build·vet·`go test -count=1 ./...` 전건 그린(-race 포함, 리뷰어 독립 실행 + 오케스트레이터 재실행). IEND 뮤테이션: 검사 제거 → 6건 발화 → 원복 ok
- 앱: analyze 무결 · **전체 1,132 전건 통과**(+1 경계 테스트). 리뷰어도 독립 실행으로 1,131 확인(수리 전)
- 리뷰가 공허성 스팟체크한 강한 주장 6건(2해시 골든 python 재현·latch-off 카운트 대조군·unknown 스킵 구분·enableDrag 실속성·도킹 실좌표·제출 바디 PNG 매직 검증) 전부 비공허 판정
- 범위 밖 보고: 에뮬레이터 CenterIdentity FAIL은 P41 소관(Normalize 케이싱 드리프트 — 근본 원인 진단을 피어 세션에 전달), gofmt 미준수 2파일도 타 세션분

## 후속 작업

- (M) 서명 시트 가로 회전 시 읽기 게이트 고착(비-flex 콘텐츠 450dp+ > 가로 높이 → 문서 영역 0 붕괴) — 세로 복귀로 회복. 회전 잠금 vs 리뷰 단계 전체 스크롤 중 UX 관찰 후 결정
- (L) 병리적 초과 서명(40KB 축소 바닥 후에도 초과)은 그대로 전송 → 64KB 초과 시 서버 400 무한 재시도 경로 — 실측 도달 불가(최대 4.1KB)라 관찰만
- Android 뒤로가기 = 2단에서 시트 전체 닫힘(획·동의 유실) — 다시 보기 버튼이 정식 경로, PopScope 매핑은 UX 후속
- 상세 시트 로딩 지연 번들 게이트 테스트 공백(로직은 확인됨 — Loading 중 서명하기 진입 불가)
- P44 이월분 그대로: 열람 이벤트 서버 기록·감사추적 PDF·센터 직인·검증 UI·지침 예규 원문 확인

## 참조

- 아크: [P36](P36-admin-contract-audit.md) → [P37](P37-contract-transition-atomicity.md)·[P38](P38-admin-contract-journey.md) → [P39](P39-contract-document-machinery.md)·[P40](P40-withdrawal-contract-closure.md) → [P42](P42-contract-template-variants.md)·[P43](P43-contract-demo-preview.md) → [P44](P44-esign-ux.md) → 본 P
