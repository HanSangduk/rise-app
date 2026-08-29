---
id: P02
title: UI/UX 여정 검수 + 기능 갭 리서치 + v1.4 기능 추가
status: 완료
domain: cross
created: 2026-08-22
completed: 2026-08-22
---

# P02 — UI/UX 여정 검수 + 기능 갭 리서치 + v1.4 기능 추가

## 목표

P01(3계층 정합·버그 수렴) 이후, ① 사용자 여정 축의 UX 검수(회원/트레이너/대표 각 여정의 마찰·데드엔드), ② 설계 문서 IN/OUT 결정과 현 시장 기준으로 기능 갭을 리서치·분석, ③ 선정된 기능을 v1.4로 구현한다.

## 결정 사항

- **v1.4 세트(8건)**: WorkoutLog(코어 루프 유일 구멍 — 시장에서도 1:1 PT 제품군의 존재 이유) ·
  미수금 KPI(Stats 서버 집계 채택) · 정책 편집(PUT /v1/center + member 조회 공개, 금액 제외) ·
  고정 스케줄 관리(GET /v1/recurrings + UI) · 환불 실행(원장 refund 마감 — P3 원칙) ·
  계약 자체서명(sent→signed, UX 검수의 "영원한 미서명" 쳇바퀴 해소) · 트레이너 sessions 통계
  (내 정산 총액 근거) · DEV_SEED(영업 데모 전제).
- 편입 보류(근거와 함께): waitlist(알림 선행 — v1.3 결정 유지) · 3안 리텐션 엔진(데이터 축적 후,
  P29) · Firebase 실연동(별도 배포 트랙) · 알림 실발송(외부 계약 미완) · 스태프 생성 API(DEV_SEED가
  dev 갭 해소, 1호 고객은 수동 1회) · 사전 문진·퍼스널 리포트(시장 실존이나 설계 결정 없음 — 후보 풀).
- reps=string 규약을 WorkoutLog.exercises에도 적용, weight_kg는 숫자(진행 그래프 후속 대비).
- "짐데스크·펫네스"는 한국 서비스로 확인 안 됨 — 시장 비교 대상에서 제외(실존 확인: 바디코디·
  다짐매니저·포인티·더잘·하이코치·WYT 등).

## 진행 단계

- [x] 1. 병렬 리서치: 기능 갭(내부 19건 인벤토리 + 시장 검증) / UX 여정 검수(J1~J4, 상위 5 단절)
- [x] 2. 교차검증 + 기능 선정 — 두 보고 상위권 5건 일치, UX 추가 2건(서명·정산) 편입
- [x] 3-1. backend v1.4 구현 완료: 엔드포인트 7 + Stats 필드 3 + 휴무일 거부 + DEV_SEED
      (go build/vet/test 그린 — api 통합 26케이스) + 실서버 E2E 전 플로우 실측 통과
- [x] 3-2. admin v1.4(파일 11 — 수업기록 입력/조회·미수금 KPI·정책 편집 폼·고정 스케줄 패널·
      환불 처리·정산 실데이터·카피 정정) / app v1.4(신규 9·수정 20·mock 삭제 — 기록 탭 실데이터·
      계약 서명 시트·정책 실값·여정 마감 9건)
- [x] 4. 최종 재검증 전부 그린 + README 3종 + 계약 v1.4 섹션

## 변경 파일

- backend: domain/{workout,policy,stats}.go · store/{store,memory,firestore,seed(신규)}.go ·
  api/{service,service_stats,handlers_workout(신규),handlers_me,handlers_passes,handlers_contracts,
  handlers_bookings,router,util}.go · config·main·.env.example·README (통합 테스트 26케이스)
- admin: lib 3(types/api/queries) + features 6(Schedule/Members/Sales/Dashboard/Settings/Homework)
  + App·auth (Center 타입을 실응답으로 교체 포함)
- app: 신규 9(workout_log_dto·center_api/policy·contract_sign_sheet·homework_week_rules 등) +
  수정 20 + mock 1 삭제 (테스트 49케이스)
- docs/API계약_v1.md: "v1.4 기능 패치" 섹션(엔티티 1·엔드포인트 6·계약 변경 3·DEV_SEED)

## 검증

- 리서치: 내부 갭 19건 인벤토리 + 한국 시장 6회 검색 교차검증(바디코디·다짐·포인티·더잘 등 실존
  확인, "짐데스크·펫네스"는 비실존으로 제외) / UX 여정 4종(J1~J4) 코드 추적
- backend: go build/vet/test 그린 + DEV_SEED 실서버 E2E(미수금 250,000·정책 전파·서명 403/200·
  환불 55,000 골든·트레이너 sessions·member PUT 403)
- admin: 신선 build exit 0 + 실서버 연동 확인(정책 400 메시지·refund 재시도 400 포함)
- app: analyze 0 · 49/49 · member1 데모 계정으로 workout-logs/center/sign 실연동 확인
- 최종 매트릭스(3계층 동시): go test ok · flutter 49/49 · npm build ✓ — FINAL_EXIT=0

## 후속 작업

- 알림 어댑터(Notifier 인터페이스 + 예약 리마인드·만료 D-30 훅포인트) — 시장 표준 1순위 잔여,
  실발송은 알림톡 채널·딜러사 계약 후
- waitlist(알림 선행 후) · 3안 리텐션 엔진(수업기록 데이터 4~8주 축적 후 — 이제 데이터 쌓이기 시작)
- Firebase 실연동 배포 트랙(Auth 전화인증·Storage 업로드·체형사진 서명 URL)
- 계약 실PDF 생성(sha256·pdf_path 채우기) · 스태프 생성 API · CSV 일괄 등록 · 고정 스케줄 자동
  연장 크론 · 통계 정밀화(결제일 귀속·registered) · 후보 풀(사전 문진 설문·퍼스널 리포트 — 설계
  결정 필요)

## 참조

- work_log/P01-cross-verify-reports.md (후속 작업 목록이 후보 풀)
- PT데스크_설계_00~03 (IN/OUT 결정로그), 목업 2안·3안(후보 소스)
- docs/API계약_v1.md (v1.1~v1.3)
