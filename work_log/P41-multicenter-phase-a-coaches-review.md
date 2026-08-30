---
id: P41
title: 멀티센터 Phase A 구현(계약 v2.16) + 코치 소개 검수 반영 + PT구매요청·결제 방식 검토
status: 완료
domain: cross
created: 2026-08-29
completed: 2026-08-29
---

# P41 — 멀티센터 Phase A + 코치 소개 검수 + 구매요청·결제 검토

## 목표
1. 코치 소개(P40 신설) 적대적 검수 → 반영
2. 멀티센터 Phase A 진행(설계04): superadmin + Center 엔티티 + 센터 생성 API + storage.rules 일반화
3. 질문 답변: 회원 PT 구매 요청 가능 여부 / 어드민 결제의 실체(PG vs 수기)

## 결정 사항
### 코치 소개 검수(적대적 리뷰) 반영
- **H1**: staffMap 15분 TTL invalidateSelf가 시트 연 채 돌면 목록이 스피너/에러로 교체되던 것 → `AsyncValue(:final value?)` 값 보존 매칭(이전 값 있으면 항상 목록 유지, 재조회 실패도 덮지 않음)
- **H2**: 자작 텍스트 "다시 시도"(~28dp) → `RiseButton(small)` 표준 교체(44dp 규약)
- **M1**: role 비교 comparator를 정수 랭크로(미지 role에서 전순서 붕괴 방어) / **M2**: 이름·직함 ellipsis / **M3**: 라벨을 "센터 코치 소개"로(예약 탭 "코치 소개"=담당 1명과 대상 충돌 해소)
- **M4**: 홈 담당 코치 카드 하단에 "센터의 다른 코치 보기" 진입점 추가(같은 staffMap 캐시, 비용 0)
- 테스트 +4: TTL invalidate 중 목록 유지 / 직함 없는 코치 역할명 폴백 / 320dp 긴 이름 오버플로 / (기존 5 유지)

### 멀티센터 Phase A (계약 v2.16)
- `RoleSuperadmin` 신설 — **IsStaff 불포함**(기존 87개 가드 무변경 403) + 인증 미들웨어 관문(`/v1/admin/*`·`/v1/me` 외 전 경로 403 — CenterID="" store 호출 500 방지 겸 개인정보 최소접근)
- `domain.Center` 신설(id 슬러그 검증·name·phone·address·status) — centers/{id} 문서의 `center` 맵 네스팅(Policy·business와 동거, 3자 비덮어쓰기 conformance 고정)
- `POST /v1/admin/centers`(센터+기본정책+최초 owner 원자 순서) / `GET /v1/admin/centers`(유령 문서 제외)
- **순서 규약**: 정책 확보(GetPolicy 지연 시딩 재사용)를 센터 신원 저장보다 먼저 — 반대면 지연 시딩 영구 비활성 → 제로 정책 센터(사전조사 CRITICAL)
- **교차 센터 이메일 가드**: CreateCenter·CreateStaff 양쪽 — 다른 센터에 연결된 계정 초대 시 409(종전엔 UserIndex 덮여 원래 센터 접근 상실)
- `GET/PUT /v1/center` 응답에 `name`(하위호환, 빈 값이면 클라 하드코딩 폴백 — Phase B/C에서 연결)
- storage.rules: `centers/rise` 2곳 → `centers/$(myCenterId())`(UserIndex.center_id 경유 — Storage 경로에 센터 세그먼트가 없어 경로 변수 불가, 문서 2개 상한 유지, fail-closed)
- 최초 superadmin 1회만 콘솔 시딩(users/{uid}={role:"superadmin",center_id:""}) — README 갱신

### 질문 답변 (조사 결과, 코드 무변경)
- **결제**: 100% 수기 장부(PG 연동 0건 — `payment.go:5` "PG 연동은 v1 OUT" 명시 의도). 어드민 Members에서 회원권 발급+결제 기록(카드/현금/이체, 2회 분할, 미수 표시) → 미납 회차 "납부 처리". 앱은 조회 전용.
- **PT 구매 요청**: 없음 — 앱의 재등록 관련 문구 전부 "센터에 문의" 데드엔드(코드 주석이 자각: "회원이 앱에서 갈 경로가 없는 약속"). join_request가 정확한 선례라 최소 구현 경로 설계됨(ConsultRequest 엔티티 + 3 endpoint + 앱 데드엔드 3곳 버튼 + 어드민 해야 할 일 한 줄) — 사용자 확인 후 착수.

## 진행 단계
- [x] 1단계: 병렬 조사 3팀 (코치 소개 적대 검수 / 결제·구매요청 / Phase A 사전조사)
- [x] 2단계: 교차검증 — 사전조사가 설계04 계획의 함정 2건(지연 시딩 사망·경로 변수 불가) 정정
- [x] 3단계: 구현 (코치 소개 반영 → Phase A 백엔드 → rules → 문서)
- [x] 4단계: 검증

## 변경 파일
### 앱 (코치 소개 검수 반영)
- `app/lib/features/my/presentation/widgets/center_coaches_sheet.dart` — H1·H2·M1·M2·M3
- `app/lib/features/my/presentation/my_screen.dart` — 행 라벨 "센터 코치 소개"
- `app/lib/features/home/presentation/widgets/home_coach_card.dart` — "센터의 다른 코치 보기" 진입점
- `app/test/.../center_coaches_sheet_test.dart` — 테스트 9건(+4)
### 백엔드 (Phase A)
- `backend/internal/domain/staff.go`(RoleSuperadmin) · `center.go`(신설) 
- `backend/internal/api/auth.go`(IsSuperadmin·dev 헤더·경로 관문) · `service_admin.go`(신설) · `handlers_admin.go`(신설) · `service.go`(교차 센터 가드·CenterResponse.name) · `util.go`(ErrInvalidCenter 400) · `router.go`
- `backend/internal/store/store.go`·`firestore.go`·`memory.go`(Center 3메서드) · `conformance_test.go`(CenterIdentity 서브테스트)
- `backend/internal/api/service_admin_test.go` — 신설(생성·403·멱등 복구·409·검증·교차 센터 가드·목록·경로 관문)
- `storage.rules` — 센터 세그먼트 일반화
- `docs/API계약_v1.md` v2.16 · `backend/README.md` 부트스트랩 절차 · 설계04 Phase A 완료 표기

## 검증
- 백엔드: `go vet` 클린 · `go test ./...` 전부 그린(conformance Memory 경로 포함)
- 앱: `flutter analyze` 0 · `flutter test` **1021 pass / 0 fail** (+3)
- 자문자답: superadmin DELETE /v1/me는 member 가드로 403 확인 / 대문자 센터 ID는 Normalize 소문자 접기(거부 아님 — 이메일 규약과 동일) / 같은 요청 재호출은 멱등 복구, 이름 다른 ID는 409로 구분 / rise 센터는 신원 미등록 상태로 무변경 동작(name="")

## 후속 작업
- **[사용자 액션] storage.rules 배포 + 실 토큰 업로드 1회 실측** — TestRuleset은 firestore.get 모킹이라 이 계층을 못 잡음(파일 주석 규약). Firestore 에뮬레이터 conformance(`-tags firestore_emulator`)도 별도 실행 권장
- **[사용자 액션] 최초 superadmin 시딩**(Firestore 콘솔 1회) 후 `POST /v1/admin/centers` 실검증
- Phase B(어드민 superadmin UI·센터명 동적화) · Phase C(앱 센터명) — 설계04
- PT 구매/재등록 요청 기능 — 최소 구현안 준비됨(위 결정 사항), 사용자 승인 시 착수

## 후속 수리 (2026-08-30, 타 세션 인계)

에뮬레이터 conformance `CenterIdentityRoundTripAndCoexist` FAIL — 계약 축 세션(P42~44)의 마감
리뷰가 근본 원인을 특정해 인계, 이 블록에서 수리.

- **원인**: `Firestore.GetCenter`·`ListCenters`가 "문서 키가 진실"로 ID를 덮은 **뒤** `Normalize()`를
  태워 ToLower가 키를 변조 — 키를 그대로 돌려주는 Memory와 케이싱 드리프트. conformance 하네스의
  t.Name() 파생 혼합 케이스 centerID에서만 노출(프로덕션 키는 centerIDPattern이 소문자 강제 — 무해).
- **수리**: 두 메서드 모두 Normalize → ID 덮기로 순서 교환(firestore.go). 필드 정규화(구문서 승격)는
  보존, ID는 키 원문이 계약. 하네스 소문자화는 드리프트를 가리기만 해서 배제.
- **검증**: `go vet` 클린 · `go test ./...` 전부 그린 · 에뮬레이터 conformance 전체 그린(FAIL하던
  서브테스트 포함 — 1차 수정 후 같은 서브테스트의 ListCenters 단계가 마저 FAIL해 두 곳 모두 수리).

## 참조
- docs/API계약_v1.md v2.16 · PT데스크_설계_04 · work_log/P40
