---
id: P01
title: 3계층 보고서 교차검증·버그수정·완성도 개선
status: 완료
domain: cross
created: 2026-08-17
completed: 2026-08-18
---

# P01 — 3계층 보고서 교차검증·버그수정·완성도 개선

## 목표

app/admin/backend 세 README(보고서)와 docs/API계약_v1.md를 상호 대조해 (1) 문서↔코드 불일치, (2) 계층 간 연결 누락(엔드포인트·필드명·타입), (3) 실제 코드 버그를 찾아 수정하고 보고서 완성도를 높인다. 로컬 툴체인(go 1.25.7 / Flutter 3.44.0 / node 23)으로 실빌드·테스트 검증까지 수행.

## 결정 사항

- 홀딩(P46): 설계는 "회원 신청→어드민 승인"이지만 계약에 신청 큐 엔드포인트가 없음. v1은 **회원 본인 패스 셀프 홀딩 허용 + 도메인 상한(최대 2회/총 30일 — 목업 문구를 정책으로 승격)**으로 단순화. 승인 큐는 후속.
- member의 `GET /v1/members` = 본인 1건 반환(403 → 자동 스코프), `PUT /v1/members/{id}` = 본인 consent만 갱신 허용(타임스탬프 전이 서버 책임).
- PUT /v1/members/{id}는 전체 교체가 아니라 **기존 레코드 위 머지**로 변경(부분 PUT 데이터 손실 방지).
- `GET /v1/hw-checks`에 `date=` 파라미터 추가(계약 v1.1 라인 갱신) — 앱이 이미 보내고 있음.
- 앱 계약서(전자계약) 목업 → 실 API(`GET /v1/contracts`) 전환(v1.1에 엔티티·엔드포인트 존재).

## 교차검증에서 직접 확정한 연결 결함 (에이전트 결과 대기 중 선행 확인)

| # | 심각도 | 결함 | 근거 |
|---|---|---|---|
| 1 | CRITICAL | 앱 패스 목록 `GET /v1/members/{id}/passes` — 백엔드에 라우트 없음(404) → 홈·마이 즉사 | passes_api.dart:18 vs router.go |
| 2 | CRITICAL | 앱 `POST /v1/join/match` 빈 바디 — 백엔드 decodeJSON 엄격(EOF→400) + `{phone}` 필수 → 온보딩 전체 불가 | auth_remote_data_source.dart:12 vs handlers_me.go:22 |
| 3 | CRITICAL | member의 `GET /v1/members` → 403 (ListMembers가 IsMember 차단) → 마이 프로필·동의 확인·촬영 가드 불가 | member_api.dart:17 vs service.go:171 |
| 4 | CRITICAL | member의 `PUT /v1/members/{id}` consent → 403 (SaveMember가 IsMember 차단) → 동의 철회 불가(P8 위반급) | member_api.dart:30 vs service.go:218 |
| 5 | CRITICAL | 앱 셀프체크인 `{source:self_qr, booking_id}` — 백엔드는 `qr_token` 필수·booking_id 무시 → 항상 400 | home_remote_data_source.dart:48 vs service.go:745-751 |
| 6 | CRITICAL | 앱 체형사진 업로드 multipart — 백엔드 decodeJSON(JSON only) → 400 | body_check_remote_data_source.dart:28-35 vs handlers_media.go:20 |
| 7 | CRITICAL | member의 hold/resume → 403 (checkTrainerOwnsPass) → "일시정지 신청" 시트 전멸 | my_remote_data_source.dart vs service.go:342,372 |
| 8 | HIGH | `GET /v1/hw-checks` date 파라미터 무시 + 앱도 hwId로만 매칭 → 과거 체크가 오늘 완료로 표시 | home_repository_impl.dart:88-95 vs service.go:935 |
| 9 | HIGH | PUT 전체교체 시맨틱 + DisallowUnknownFields → 부분 PUT시 app_linked/last_visit_at 소실, GET 응답(passes 임베드) 재전송 시 400 | handlers_members.go:39-54 |
| 10 | MEDIUM | CORS 기본 5173 vs 어드민 5174 (프록시 우회 시 차단) | config.go:28 vs vite.config.ts:13 |
| 11 | CRITICAL | member의 refund-quote → 403 (checkTrainerOwnsPass) → 마이탭 환불 계산기 전멸 | my_remote_data_source.dart:37-41 vs service.go:401 |

## 진행 단계

- [x] 1. 병렬 검증: backend / app / admin 각 관점 에이전트 3개 (인벤토리 + 불일치 + 버그 + 실빌드)
- [x] 2. 교차검증: 3개 인벤토리 매트릭스 대조 (엔드포인트·필드·타입·역할 스코프)
- [x] 3. 자문자답 패스 (홀딩 시맨틱, PUT 머지, 통계 금액 게이팅, hw-checks date — "결정 사항" 참고)
- [x] 4-1. backend 수정 + api 통합 테스트 13케이스 신설 + 실서버 E2E (go build/vet/test 전부 통과)
- [x] 4-2. admin 수정 (신선 설치 npm run build exit 0)
- [x] 4-3. app 수정 22건 (analyze 0 issues · 테스트 37/37 · mock 삭제·실 API 전환)
- [x] 4-4. 계약 문서 v1.2 정합 패치 섹션 + backend/admin/app README 갱신
- [x] 5-1. 어드민 UI/UX 목업 대조 완료 → HIGH 1(트레이너 뷰 raw member_id 노출)·MEDIUM 7·LOW 다수
      → 수정 반영 완료(마스킹·에러 오탐 정리·폼 가드·880px 브레이크포인트·접근성) + build exit 0
- [x] 5-2. 앱 UI/UX 목업 대조 완료(HIGH 3: 본인아니에요 무반응·waitlist UI 유령·재시도 부재)
      + 앱 로직 2R 완료(HIGH 1: 지난 슬롯 예약 가능 등 10건) → 통합 수정 에이전트 가동 중
- [x] 5-3. 백엔드 로직 2R 완료(HIGH 4: 홀딩 시간축 무검증·재취소 이중차감·Firestore 구정책 상한 해제·
      ID유출+confirm 무검증 탈취 체인) → 전부 수정 + 회귀 테스트 6개 추가(총 19케이스) + go test 그린
      → 계약 v1.3 정합 패치 섹션 + backend README 갱신
- [x] 5-4. 앱 통합 수정 24항목 완료(analyze 0 · 45/45) + confirmJoin phone 후속 반영
- [x] 6. 3라운드(수렴 확인): 전 계층 재빌드·재테스트 + v1.3 E2E 스모크 → 신규 발견 1건
      (HwItem.reps int↔string 불일치 — R1 어드민 검증이 "대조 필요"로 남겼던 항목 실측 확정)
      즉시 수정·검증. 이후 신규 발견 0 → 수렴 종료.

## 변경 파일

- backend: internal/api/{service,service_stats,service_test,util,handlers_members,handlers_homework}.go ·
  internal/domain/{pass,pass_test,policy,booking,homework}.go · internal/store/{errors,memory,firestore}.go ·
  internal/config/config.go · .env.example · README.md (+ api 통합테스트 19케이스·domain 테스트 신설)
- app: lib 60여 파일(연결 수정 9·기능 12·UX 15·표기 10) · test 6파일(45케이스) · README.md ·
  contracts mock 삭제 → 실 API
- admin: src 12파일(빌드 수정·유예 버튼 제거·이중 발급 방지·마스킹·에러 오탐 정리·폼 가드·접근성) ·
  package.json/tsconfig* · .env.example · README.md
- docs/API계약_v1.md: v1.2·v1.3 정합 패치 섹션 추가(단일 진실 갱신)

## 검증

- backend: `go build`/`go vet`/`go test ./...` 전부 통과(api 19 + domain 50여 케이스) + 실서버 E2E
  (온보딩 phone 재대조 → 패스 → 동의 게이트 → 셀프 홀딩 상한·시간축 → 환불 골든 550,000 →
  지난 슬롯 거부 → 선예약 허용 → 재취소 가드 → hw-checks date → 홈워크 reps 문자열·명단 제거 →
  에러 한국어) 실측 통과
- app: `flutter analyze` No issues · `flutter test` 45/45 · build_runner 정상
- admin: 신선 설치 `npm install && npm run build` exit 0
- 문서: 계약 v1.1/v1.2/v1.3 ↔ 3계층 코드 ↔ README 4종 상호 대조 일치

## 후속 작업

- Firebase 실연동(Auth 전화 인증 → join/match·confirm의 phone을 토큰 phone_number로 대체, Storage 업로드)
- 대기(waitlist): 알림톡/푸시 어댑터와 함께 생성·자동 승격 구현(계약 v1.3에 예약어로 유지)
- WorkoutLog 엔티티(운동 세트/코치 코멘트 — 앱 records 탭 mock 대체), 체형사진 서명 URL API(실이미지 렌더)
- 어드민: 미수금 KPI·고정 스케줄 관리 UI·CSV 일괄 등록, complete/noshow의 store 레벨 expectedStatus 파라미터화(현재 confirmed 고정)
- dev 스태프 시딩 수단(현재 인메모리 수동 불가 — DEV_SEED 환경변수 또는 스태프 생성 API)

## 변경 파일

- (진행하며 기록)

## 검증

- (진행하며 기록)

## 후속 작업

- (진행하며 기록)

## 참조

- docs/API계약_v1.md (단일 진실)
- app/README.md · admin/README.md · backend/README.md
- PT데스크_설계_03_라이즈_v1확정_DB백엔드_2026-08-14.md
