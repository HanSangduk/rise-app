---
id: P23
title: 촬영 격자 촘촘화 · 목업 잔재 제거 · 계약 열람
status: 완료
domain: app
created: 2026-08-25
completed: 2026-08-25
---

# P23 — 촬영 격자 촘촘화 · 목업 잔재 제거 · 계약 열람

## 목표

람의 4개 요청 중 남은 것과, 그 과정에서 드러난 **거짓말하는 UI** 정리.

1. 격자 눈금을 더 촘촘하게 (`docs/camera.jpeg` 참고) — "나중에 분석할 때 어느정도 변했는지 더 잘 보이게"
2. 고스트 제거 (람: "고스트는 필요 없어")
3. 계약서 열람 — "계약서 들어가 있는게 있는지 볼 수 있으면 좋겠다"
4. 전체 검수: 동작 안 하거나 **사실이 아닌 것** 찾아 고치기

## 결정 사항

### 격자를 3단계 밀도 + 주선/보조선으로

`GridDensity` enum(성김 9×12 / 촘촘 18×24 / 아주 촘촘 28×36). 기본은 촘촘.

균일하게 촘촘한 격자는 오히려 판독이 어렵다 — 눈이 칸을 못 센다. 그래서 `majorEvery`
칸마다 진한 주선을 둔다(제도용 모눈지 방식). 보조선 alpha 0.16 / 0.5px, 주선 0.34 / 1px —
촘촘해질수록 선이 화면을 덮어 피사체가 안 보이는 걸 막는다.

### 수평 기준선을 끌어 옮길 수 있게

고정 높이는 키가 다르면 아무 데도 안 맞는다. 세로 드래그로 이동(0.05~0.95 clamp),
오른쪽 끝에 손잡이 원으로 어포던스 표시. **드래그 높이는 프리뷰 프레임의 constraints에서
받는다** — 화면 전체 높이로 나누면 AppBar·하단 컨트롤만큼 선이 손가락보다 덜 따라와
"끌리다 마는" 느낌이 난다.

끌 수 있게 만든 이상 되돌릴 길도 있어야 해서 `기준선 초기화` 버튼 추가.

### 「기울기 시뮬」 버튼 제거 (실기기에서 발견)

목업에서 온 버튼인데 **실기기에서는 수평계를 3.4°로 잠그는 토글**이다. 눌러 둔 채로
두면 수평이 영영 OK가 안 되고 자동촬영(정렬되면 3·2·1)이 죽는다 — 회원에게는
"카메라가 고장 났다"로 보인다. 센서 없는 환경용 폴백은 provider에 남기고 버튼만 뺐다.

### 배경 인물 배너 — 지킬 수 있는 말만

종전 문구: **"배경에 다른 사람이 감지됐어요 — 저장할 때 자동으로 흐림 처리합니다"**

둘 다 사실이 아니었다.
- `backgroundPersonDetected`는 `true`로 **고정**돼 아무도 갱신하지 않았다 (감지 없음)
- 업로드는 언제나 `blurred: false`로 나갔다 (블러 없음)

사람 많은 헬스장에서 이 문구를 믿고 찍은 사진에 남의 얼굴이 그대로 남는다 —
안내가 아예 없느니만 못하다. 문구를 "뒤에 다른 사람이 함께 찍히지 않는지 확인해주세요"로
바꾸고, danger 톤도 뺐다(지금 뭔가 잘못됐다는 뜻이 아니라 늘 붙는 주의문이다).
죽은 상태 필드는 삭제.

### 계약 열람 — 서명하면 다시 못 보던 것

`sent` 행만 서명 시트로 열리고 `signed`·`draft`·`voided`는 배지만 붙은 죽은 행이었다.
**서명하는 순간 계약을 다시 볼 길이 사라진다** — 돈이 오간 계약에서는 그냥 결함이다.

모든 행을 탭 가능하게 하되, 서명 가능한 행만 서명 시트로 보내고 나머지는 읽기 전용
상세로 보낸다(환불된 패스의 sent 계약은 서버가 서명을 400으로 막으므로 여기 포함).

`penalty_rate`는 DTO까지만 받고 `ContractItem` 매핑에서 **버려지고 있었다** — 해지 시
얼마를 떼이는지가 계약의 핵심이라 끝까지 전달해 상세에 표시한다. null은 0%가 아니라
"모름"(v1.5 이전 레거시)이라 **행을 아예 뺀다** — 0%를 그리면 "위약금 없음"이라는
없는 약속을 만든다.

계약 본문 PDF(`pdf_path`)는 서버가 아직 쓰지 않아 늘 비어 있다. **없는 걸 있는 척하지
않고** "아직 앱에 올라와 있지 않아요 — 센터에 요청하면 보내드려요"라고 적었다.
(람이 계약서 양식을 보내주면 그 자리에 본문을 붙이면 된다.)

## 진행 단계

- [x] 고스트 오버레이·테스트·버튼 삭제
- [x] `GridDensity` 3단계 + 주선/보조선 + 이동식 기준선
- [x] 격자 테스트 7건 (밀도 순서·순환·주선 간격·한국어 라벨·재그리기·범위 밖 안전)
- [x] 기울기 시뮬 버튼 제거 + 기준선 초기화 추가, 뮤테이션 검증 2건
- [x] 배경 인물 배너 정직화 + 죽은 상태 필드 삭제
- [x] 계약 상세 시트 + 모든 행 탭 가능 + `penaltyRate` 전달, 테스트 6건 / 뮤테이션 2건
- [x] 실기기 촬영 화면 육안 확인 (격자·기준선·손잡이)
- [x] 계약 상세 — 360dp 오버플로 테스트로 대체 확인(프로덕션에 되돌릴 수 없는 서명을 남기지 않으려 로컬 시드 경로 시도 → dev uid 미바인딩으로 중단)
- [x] 전체 스위트 848건 그린

## 변경 파일

**app**
- `lib/features/bodycheck/presentation/widgets/grid_overlay.dart` — `GridDensity`, 주선/보조선, 이동식 hLine
- `lib/features/bodycheck/presentation/camera_view_model.dart` — `gridDensity`/`hLine`/`resetHLine`, `backgroundPersonDetected` 삭제
- `lib/features/bodycheck/presentation/camera_screen.dart` — 격자 밀도·기준선 초기화 버튼, LayoutBuilder 드래그, 고스트 제거
- `lib/features/bodycheck/presentation/widgets/background_person_banner.dart` — 문구 정직화
- `lib/features/my/presentation/widgets/contract_detail_sheet.dart` (신규)
- `lib/features/my/presentation/widgets/contracts_row.dart` — 전 행 탭 가능
- `lib/features/my/presentation/my_screen.dart` — `onDetailTap` 연결
- `lib/features/my/domain/my_models.dart` · `lib/features/my/data/my_repository_impl.dart` — `penaltyRate` 전달
- 삭제: `widgets/ghost_overlay.dart`, `test/.../ghost_overlay_test.dart`

**test**
- `test/features/bodycheck/presentation/grid_density_test.dart` (신규 7건)
- `test/features/my/presentation/widgets/contract_detail_test.dart` (신규 6건)
- `test/features/bodycheck/presentation/camera_view_model_test.dart` — 기준선 2건 추가
- `test/features/bodycheck/presentation/camera_screen_permission_test.dart` — 기울기 시뮬 부재 단언
- `test/features/my/presentation/widgets/hold_precheck_test.dart` — `onDetailTap` 반영

## 검증

- `flutter analyze` 0 issues
- 뮤테이션 검증 4건 (되돌리면 실패 → 복구 확인)
  - `resetHLine`을 no-op으로 → 실패
  - `moveHLine`의 clamp 제거 → 실패
  - 서명 완료 행을 다시 죽은 행으로 → 실패
  - `penaltyRate` null을 0%로 그리기 → 실패
- 실기기(Galaxy) 촬영 화면 캡처 확인: 격자 촘촘·주선 구분·빨간 기준선·오른쪽 손잡이
- 실기기 드래그 실측: 기준선 y=1151 → **619** (스와이프 종점 620) — 손가락에 정확히 붙는다.
  절대 위치로 바꾸기 전에는 같은 스와이프에서 1151→1037밖에 안 움직였다(델타 유실)
- 실기기 격자 밀도 순환 확인: 촘촘 → 아주 촘촘 (버튼 라벨·선 간격 모두 변화)
- 프리뷰 픽셀 (1,1,1) ≠ 그라데이션 (67,70,79) → 프리뷰는 정상 렌더링, 어두운 장면일 뿐
  (logcat: ExynosCamera AF 동작 중, 에러 없음)

## 후속 작업

- 계약 본문(PDF) 연동 — 람이 계약서 양식 전달 예정. `pdf_path`/`sha256` 자리는 이미 있다
- 배경 인물 실감지·블러 — 붙이는 날 배너를 감지 상태에 다시 연결(그때는 danger 톤이 맞다)

## 참조

- `docs/camera.jpeg` (람이 준 격자 예시)
- `docs/API계약_v1.md` v1.5 (penalty_rate 스냅샷), v2.10 (회원별 포즈)
