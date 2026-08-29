---
id: P21
title: 체형분석 완성 — 사진 실표시 · 전체화면 촬영 · 회원별 포즈 커스텀
status: 완료
domain: cross
created: 2026-08-24
completed: 2026-08-25
---

# P21 — 체형분석 완성

## 목표

람 요청 3건 + 검수에서 드러난 미완성 1건:

| # | 요청/발견 | 상태 |
|---|---|---|
| ① | 촬영 화면을 **전체화면처럼 크게** | **완료** — 탭 브랜치 → fullscreenDialog 라우트 |
| ② | 포즈 1·2·3·4번(개발자가 임의로 정한 값)을 **어드민에서 회원별로 정하거나 커스텀** | **완료** — 서버·앱·어드민 3계층 |
| ③ | (검수) 찍은 사진이 **어디서도 안 보인다** | **완료** — 앱 타임라인·고스트·어드민 라이트박스 |

## 결정 사항

설계는 워크플로(조사 3갈래 → 교차검증)로 확정했다. 핵심만:

### nil이 의미를 갖는 필드
`Member.body_poses`는 **nil = 센터 기본 사용**이다. 그래서 다른 슬라이스처럼 nil→[] 정규화를
하지 않고, 구체화(기본값 채우기)는 **응답 사본에만** 한다. 저장 객체에 구체화하면 필드 없는
머지 PUT이 기본값을 커스텀으로 굳혀 **그 회원만 이후 센터 기본 변경을 못 따라온다** —
조용히 동작하는 것처럼 보이는 종류라 회귀 테스트로 못박았다.

### 하이픈 금지가 검증의 핵심
Storage 파일명이 `{yyyyMMdd}-{pose}-{direction}-{epochMs}.jpg`로 **'-'를 조각 구분자**로 쓴다.
커스텀 key에 '-'가 들어가면 파일명 파싱(고스트가 직전 사진을 고를 때 쓰는 epochMs 타이브레이커)이
모호해진다. `^[a-z0-9_]{1,24}$`로 막고, 레거시 4종은 통과하므로 비파괴.

### 사진 표시는 getData만 — getDownloadURL 금지
토큰 URL은 Storage 규칙을 거치지 않는 **무기한 열쇠**다. P8 민감정보는 매 호출 규칙 평가가
유일한 정답. `storage.rules`는 무변경(firestore.get 평가당 2문서 상한에 여유 없음).

### 전체화면은 QR 스캐너 패턴
rootNavigator push + fullscreenDialog. 다만 프리뷰는 **full-bleed로 안 채운다** — 3:4 원본을
cover로 채우면 좌우가 잘려 화면과 저장 사진이 어긋난다(WYSIWYG 붕괴). 전폭 + 기존 비율 유지.

## 진행 단계

- [x] 0. 조사 3갈래(포즈 배관 / 사진 표시 경로 / 촬영 화면 구조) → 교차검증 설계 확정
- [x] 1. **백엔드 + 계약** — 아래 검증 참조. 운영 배포 `rize-api-00016`
- [x] 2. 앱: 서버 주도 포즈(A) · 타임라인/고스트 실사진(B) · 전체화면 촬영(C) — 아래 검증
- [x] 3. 어드민: 사진 라이트박스 · 회원별 포즈 편집기 — 배포 완료
- [x] 4. 편집 흐름 E2E 검증 + 마감

## 변경 파일

- `backend/internal/domain/member.go` — `BodyPose{Key,Label}` · `Member.BodyPoses` ·
  `DefaultBodyPoses` · `ValidateBodyPoses` · `ValidPoseKey` · `NormalizeBodyPoses` ·
  `EffectiveBodyPoses` · `ErrInvalidBodyPoses`
- `backend/internal/api/service.go` — Create/UpdateMember 검증·정규화, ListMembers 2분기 응답
  구체화, CreateBodyPhoto pose·storage_path 검증, `slices` import
- `backend/internal/api/util.go` — **`ErrInvalidBodyPoses`를 400 매핑에 추가**(누락돼 있었다)
- `backend/internal/api/service_bodypose_test.go` — 신규 7건
- `docs/API계약_v1.md` — v2.10 절
- **앱(단계 2)**
  - `app/lib/features/bodycheck/domain/bodycheck_models.dart` — `BodyPose` enum → `PoseSpec`
    값 타입(+레거시 라벨 맵·폴백 시퀀스·`labelFor`). `BodyPhotoEntry.pose`는 **key 원문**
  - `app/lib/core/api/dto/member_dto.dart` — `body_poses`(nullable) + `BodyPoseDto`
  - `app/lib/features/bodycheck/presentation/camera_view_model.dart` — 시퀀스를
    `myProfileProvider`에서, `completed`/`pending.pose`를 key로, 인덱스 clamp
  - `app/lib/features/records/domain/records_models.dart` — 앨범 키를 String으로,
    `poseKeys(sequence)` 합집합·`defaultPose(sequence)`
  - `app/lib/features/bodycheck/data/body_photo_loader.dart` — **신규**. `getData` 전용
    (getDownloadURL 금지) + 경로 키 메모리 캐시(파일 불변이라 stale 불가) + 읽기용 에러 매핑
  - `app/lib/features/records/presentation/widgets/body_photo_timeline.dart` —
    플레이스홀더 → 로딩/실패(재시도)/`Image.memory`(cacheWidth 720) 3상태 타일
  - `app/lib/features/bodycheck/presentation/widgets/ghost_overlay.dart` — 실루엣 →
    직전 같은 포즈 사진(`BoxFit.cover`, 실패 시 실루엣 폴백)
  - `app/lib/core/router/app_router.dart` · `features/shell/app_shell.dart` —
    촬영을 탭 브랜치에서 떼어 **fullscreenDialog 라우트**로, 탭 4개로 리매핑
  - `app/lib/features/bodycheck/presentation/camera_screen.dart` — 검은 전체화면 +
    하단 컨트롤 존 + PopScope(미저장 사진 확인) + AppBar 제목 대비
  - `app/lib/core/widgets/rise_button.dart` — `onDark` 옵션(아래 참조)
  - 테스트 신규 3파일: 레거시 포즈 보존 · 셸 라우팅 · 고스트 오버레이
- **어드민(단계 3)**
  - `admin/src/lib/types.ts` — `BodyPose` union → string, `PoseSpec`·`poseLabel`(3단 폴백)·
    `DEFAULT_BODY_POSES`·서버 검증 미러 상수, `Member.body_poses`
  - `admin/src/lib/firebase.ts` — `getStorage` (getDownloadURL 금지 근거 주석)
  - `admin/src/lib/bodyPhotoBlob.ts` — **신규**. `getBlob` + 세션 캐시 + revoke,
    403/404/네트워크 3분류
  - `admin/src/features/BodyPhotoLightbox.tsx` — **신규**. 클릭 시 원본 로드(그리드 자동 로드
    금지 — no-store라 매번 수십 MB), 403은 "동의 철회일 수 있음"으로 구분
  - `admin/src/features/PoseSequenceEditor.tsx` — **신규**. 순서·추가/삭제·라벨 편집 ·
    기본으로 되돌리기(null 전송) · 서버 검증 미러(칸 단위 이유)
  - `admin/src/features/BodyPhotos.tsx` — 하드코딩 POSES 제거 → 시퀀스 ∪ 실데이터 합집합,
    타일 클릭 → 라이트박스, **거짓 문구 정정**("열람은 본인 + 담당 트레이너만" → 대표 포함)
  - Storage 버킷 **CORS 설정**(어드민 오리진 GET/HEAD) — 없으면 브라우저 getBlob이 전부 차단.
    설계가 "미확인"으로 남긴 항목이었고 실제로 비어 있었다.

## 검증

- `go build`·`go vet`·`go test ./...` 전 패키지 그린
- **뮤테이션 4/4 kill**: ① 응답 구체화 위치 ② 400 매핑 제거 ③ CreateBodyPhoto pose 검증 제거
  ④ `slices.Clone` 제거(아래)
- **작업 중 결함 2건 발견·수리**:
  - `ErrInvalidBodyPoses`가 400 매핑 목록에 없어 **검증은 도는데 응답만 500**이었다 —
    사용자가 이유를 볼 수 없는 상태. 테스트가 `writeErr`를 직접 태워 HTTP 코드를 단언한다.
  - Memory 스토어 얕은 복사 + json 언마샬의 백킹 배열 재사용 → **검증 실패(400)로 저장을
    안 했는데도 스토어 원본이 오염**됐다. 대표는 "저장 실패"를 보고 창을 닫는데 회원의 포즈
    시퀀스는 이미 잘못된 값. `slices.Clone`으로 소유권을 끊고 회귀 테스트로 고정
    (Firestore는 매번 새로 언마샬해 무관 — Memory만의 함정이라 프로덕션에선 안 터졌을 것)
- **운영 실인증 확인**: 회원 토큰으로 `GET /v1/members` → `body_poses: [차렷, T자, 전굴, OH스쿼트]`
  구체화 확인(앱이 이 경로로 시퀀스를 받는다)

### 앱(단계 2)
- `flutter analyze` 이슈 0 · `flutter test` **804건**(착수 787 → +17, 회귀 0)
- **뮤테이션 검증**
  - 합집합(`poseKeys`)을 시퀀스만으로 → 레거시 보존 테스트 4건 FAIL
  - 탭 인덱스를 예전(밀린) 값으로 → 셸 테스트 3건 FAIL
  - 촬영을 브랜치 전환으로 되돌림 → 셸 테스트 2건 FAIL
- **실기기 확인**(갤럭시 S21): 전체화면 촬영 진입·프리뷰 확대·포즈 칩 4종·수평계 동작,
  탭 4개 + 촬영 버튼 구조

### 실기기에서만 드러난 것 2건
1. **AppBar 제목이 검은 배경에 묻혔다** — 전역 `AppBarTheme.titleTextStyle`이 잉크색을
   들고 있어 `foregroundColor`만으로는 안 덮인다. 이 화면에서 명시.
2. **하단 outline 버튼 글자가 통째로 안 보였다** — `RiseButton`이 라벨 색을 **자식 Text에
   직접** 박아서 상위 `Theme` 오버라이드가 무효였다. 처음엔 Theme으로 덮으려다 실기기에서
   그대로인 걸 보고 원인을 찾았다. 공용 위젯에 `onDark` 옵션을 정식으로 추가 —
   테마 우회는 조용히 깨지지만 옵션은 호출부에서 의도가 보인다.

### 어드민(단계 3)
- `npm run build`(tsc 포함) 통과
- **편집 흐름 E2E**(로컬 DEV_SEED 서버 :8093, 어드민이 보내는 것과 같은 요청):
  ① 커스텀 저장 → `[정면 이완, 좌측면]` ② **이름만 수정해도 포즈 유지**(머지 PUT)
  ③ **앱(회원 본인) 조회가 그 시퀀스를 받음** ④ 기본으로 되돌리기 → 4종 복귀
  ⑤ 하이픈 key → 400 + 이유 문구. 서버 종료 확인.
- 회원 토큰으로 `body_poses` PUT → **400**(스태프 전용이 구조로 보장됨)

### 고스트는 "안 보이는 게 정상"이었다
실기기에서 고스트가 안 보여 결함으로 의심했는데, 직전 사진이 어두운 실내 촬영본이라
38% 투명도로 어두운 프리뷰에 겹치니 눈으로 구분되지 않은 것이었다. 카메라 프리뷰가 매
프레임 바뀌어 픽셀 비교로도 판정이 안 되므로 **위젯 테스트로 결정적으로 확인**했다
(사진 로드 성공→Image / 경로 없음→실루엣 / 실패→실루엣 + 촬영 안 막힘 / BoxFit.cover /
포즈 전환 시 재로딩 / 끄기는 투명도만 0). 화면으로 판정할 수 없는 것은 테스트로 판정한다.

## 후속 작업

- 앱·어드민 구현은 주간 한도 리셋(06:00 KST) 후 재개. 설계 전문은 워크플로 저널
  (`wf_53257abb-1e2/journal.jsonl`)과 `/tmp/design.json`에 있고, work_app·work_admin 필드가
  파일 단위 지시까지 담고 있다.
- 배포 순서 주의: **백엔드 → 앱 → 어드민 커스텀 편집 오픈**. 앱이 먼저 나가야 구버전의
  미지 key 폴백 오분류를 최소화한다.

## 참조

- work_log/P21-hollow-feature-audit.md(같은 라운드의 전수 검수) · docs/API계약_v1.md v2.10
