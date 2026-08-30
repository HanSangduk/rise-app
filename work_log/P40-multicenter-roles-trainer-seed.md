---
id: P40
title: 멀티센터·롤 계층 준비도 점검 + 테스트 트레이너 시드 + 코치 소개 목록 + 회원-센터 정책 검토
status: 완료
domain: cross
created: 2026-08-29
completed: 2026-08-29
---

# P40 — 멀티센터·롤 준비도 + 테스트 트레이너 시드 + 코치 소개

## 목표
1. 회원 앱에서 담당 외 트레이너를 볼 수 있는지 사실 확인 → 갭이면 보완
2. 프로필 이미지 등록된 테스트 트레이너 시드 (앱 다중 시나리오 테스트)
3. 슈퍼어드민 → 센터장 계층·멀티센터 등록 준비도 점검
4. 회원-센터 정책(자동 귀속 vs 앱에서 센터 선택) 의견

## 결정 사항 (3팀 병렬 조사 교차검증)
- **앱 트레이너 노출**: UI는 담당 코치만(디렉토리 없음), API(GET /v1/staff)는 회원에게 센터 전체 스태프+프로필을 이미 내려줌(퇴사자 profile만 마스킹) → **추가 네트워크 0으로 "코치 소개" 목록 신설 가능** — 마이 탭 센터 카드에 진입점, staffMap 캐시 재사용, 현직만 필터(퇴사자는 이름 해석용으로만 잔존 — staff_directory 규약), 관장 우선+이름순 고정 정렬, 행 탭 → 기존 프로필 시트.
- **시드**: t1(정혜린)·t2(김태오)에 photo_url 추가 + 사진·풀프로필 신규 트레이너 t3(이수민, 모빌리티) + **김민지 두 번째 패스(모빌리티 8회, t3 담당)** — member1 계정 하나로 패스 전환 칩·코치 카드 전환·"내 회원권 전체" 예약(코치 2명)·사진 아바타·프로필 시트·코치 소개 목록이 전부 테스트됨. owner1은 일부러 사진 없음(이니셜 폴백 경로 재현). 오프라인이면 TrainerAvatar가 색+이니셜 폴백이라 무해 — API계약_v1.md의 "시드는 photo_url 빈 값" 문구를 이 근거로 갱신.
- **멀티센터 준비도**: 데이터 평면(센터 스코프 격리·롤 게이트 87곳)은 준비됨. **관리 평면 부재** — superadmin 롤 0건, 센터 생성 API 없음(최초 owner는 Firestore 콘솔 수작업), Center 엔티티 없음(센터명 어드민 3곳+앱 상수 하드코딩), storage.rules `centers/rise` 하드코딩(2호점부터 깨짐), 가입 요청 DEFAULT_CENTER_ID 고정. → 코드로 지를 규모가 아니라 **설계 문서로 확정**: `PT데스크_설계_04_멀티센터_롤계층_2026-08-29.md` (Phase A 백엔드 관리평면 → B 어드민 → C 앱 → D 보류, 결정 포인트 3개).
- **회원-센터 정책 권고**: v1은 어드민 등록→전화번호 자동 매칭 유지, 앱 내 센터 검색/선택 안 만듦(오선택 경로·타 센터 노출·복구 플로우 비용 > 이득). 멀티센터 실가동 시 **초대 코드/QR** 방식(센터를 "고르는" 게 아니라 "서 있는 센터에 연결")으로 확장 — 설계04 §4.

## 진행 단계
- [x] 1단계: 병렬 조사 (앱 트레이너 노출 / 백엔드 롤·멀티센터 / 어드민 롤·센터 UI)
- [x] 2단계: 교차검증 + 갭 우선순위 (설계04 §1 표)
- [x] 3단계: 실행 — 시드 확장 + 코치 소개 목록 + 설계 문서
- [x] 4단계: 검증

## 변경 파일
- `backend/internal/store/seed.go` — t1·t2 photo_url, t3 신규(사진+풀프로필), 김민지 모빌리티 8회 패스(t3)
- `docs/API계약_v1.md` — DEV_SEED 시드 명세 갱신(스태프 4·사진 방침·member1 패스 2개)
- `app/lib/features/my/presentation/widgets/center_coaches_sheet.dart` — 신설(코치 소개 목록 시트)
- `app/lib/features/my/presentation/my_screen.dart` — 센터 카드에 "코치 소개" 행
- `app/test/features/my/presentation/widgets/center_coaches_sheet_test.dart` — 신설 5건(현직 필터·정렬 고정·프로필 시트 연계·실패 재시도·빈 상태) — Riverpod 3 기본 재시도(backoff)가 에러 UI 검증을 비결정적으로 만들어 테스트 스코프에서 retry 차단
- `PT데스크_설계_04_멀티센터_롤계층_2026-08-29.md` — 신설(진단·목표 구조·Phase 계획·정책 권고·결정 포인트)

## 검증
- 백엔드: `go build ./...` · `go vet` · `go test ./...` 전부 그린 (gofmt 무변경)
- 앱: `flutter analyze` 0 issues · `flutter test` **1018 pass / 0 fail** (+5)
- 자문자답: 코치 소개는 시트 위 시트(스택)로 목록 복귀 동선 유지 / 퇴사자 제외 근거를 staff_directory 규약에 연결 / 시드 사진은 외부 URL이지만 아바타 폴백으로 오프라인 데모 무해 / member1 dev uid(`dev-member-uid-001`)와 시드 member1 불일치는 기존 상태 그대로(온보딩 매칭 경로가 처리)

## 후속 작업
- 설계04 Phase A 착수 전 결정 3개: ① superadmin의 센터 내부 열람 범위(권고: 안 봄) ② 센터 과금 모델 필요 여부 ③ Firebase 프로젝트 단일 유지(권고: 유지)
- Phase A 첫 항목이 storage.rules `centers/rise` 하드코딩 해소 — 2호점 생성 전 필수
- 스태프 사진 서버 업로드 API는 Phase D 보류(URL 방식으로 충분)

## 참조
- PT데스크_설계_04_멀티센터_롤계층_2026-08-29.md
- work_log/P05-trainer-profile.md · P07-staff-onboarding-hosting.md · P08-staff-lifecycle.md
