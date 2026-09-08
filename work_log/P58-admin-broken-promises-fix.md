---
id: P58
title: 어드민 결함 4건 수리 — B6 거절 404 재해석 · B3 트레이너 자기 프로필 · A2 체형사진 삭제/복원/정합 · B2 철회 잠금 범위
status: 완료
domain: admin
created: 2026-09-04
completed: 2026-09-04
---

# P58 — 어드민 결함 4건 수리 (P56 후속)

## 목표
P56 감사가 남긴 어드민 HIGH 4건을 `admin/`만 만져서 닫는다. 백엔드·앱·문서는 다른 갈래가 동시에
만진다 — 그쪽에 필요한 것은 "백엔드 갈래에 요청" 절로 넘긴다.

| # | 결함 | 한 줄 |
|---|---|---|
| B6 | 거절 404를 "미배포"로 접고 **"승인만 처리하세요"**라고 지시 | 그 404의 실제 원인은 좀비 경합이고, 지시대로 승인하면 P55 C-2 |
| B3 | 설정 탭이 `ownerOnly`라 트레이너가 자기 프로필·휴무를 못 고침 | 서버는 본인을 허용(`service.go` UpdateStaffProfile·SetOffdays) |
| A2 | `DELETE /body-photos/{id}`·`restore`·`purge`·`reconcile` 소비처 0 | v2.14가 표로 약속한 동사인데 어드민에 문이 없음 |
| B2 | 동의 철회 시 오른쪽 컬럼 **전체**(인바디 포함)를 잠금 | 서버는 인바디 목록·삭제를 열어 둠 |

## 결정 사항
- **404 두 종류를 `code`로 가른다.** 라우터 404(`code:"route_not_found"`, 백엔드 갈래가 추가)만
  "미배포"이고, 그 외 404는 리소스 부재다. `api.ts` `ApiError.code` + `isRouteNotFound()` 한 곳.
  CheckinQr·사진 업로드·거절 세 자리가 같은 판정을 쓴다.
- **B3는 설정 탭을 여는 대신 트레이너 전용 탭 "내 프로필·휴무"를 만든다.** 설정 탭의 나머지
  카드(정책·사업자·신원·가입 승인·QR·직원 생애주기)는 전부 서버가 owner 전용 — 탭을 열면
  "눌러보고 403" 카드가 7개 생긴다. 사진 업로드는 서버가 **owner 전용**(`service_staff_photo.go`
  `!p.IsOwner()`)이라 트레이너 창에서는 업로드 컨트롤을 빼고 그 사실을 문장으로 말한다.
- **A2 삭제는 라이트박스 안에서만.** 타임라인 타일은 사진이 아니라 아이콘+날짜라 **보지 않은
  사진을 지우는 UI**가 된다. 원본이 보이는 자리에서 2단 인라인 확인(집안 관례 — InbodyList·
  CheckinQr) — 승인 모달만큼 무겁게 하지 않는다(스태프 삭제는 30일 복원 가능한 소프트 삭제).
- **복원 목록은 서버 휴지통(v2.28 `include_deleted=true`).** 1차 구현은 세션 휴지통("새로고침하면
  사라져요")이었는데 백엔드 갈래(P57)가 같은 날 `include_deleted`를 열어 서버 목록 기반으로 바꿨다 —
  타임라인·잠긴 목록·휴지통이 **조회 하나·캐시 키 하나**에서 `deleted_at`·`storage_path`로 갈라진다.
- **잠긴 회원(철회·미동의)에도 목록이 있다(v2.28 `BodyPhotoMeta[]`).** 서버가 403 대신 6키(`id·
  member_id·pose·direction·date·deleted_at?`)만 주고 `storage_path`는 없다. 응답 모양(`isFullBodyPhoto` —
  `storage_path` 유무)으로 잠금을 판정하고, 잠긴 카드 안에 날짜·포즈 행 + [삭제]를 둬 스태프가 삭제
  요청을 처리한다. 사진의 **존재 사실**과 **내용**을 가른 것.
- **503 판정은 `code:"media_not_configured"`로만**(api.ts `isMediaNotConfigured`) — "비-transport 503"
  추정을 버렸다(`isRouteNotFound`와 같은 규약).
- **정합 검사·파기는 설정이 아니라 체형 분석 탭의 대표 전용 카드.** reconcile이 `member` 필수라
  회원 선택이 있는 화면이 맞다.
- **B2: 잠그는 것은 사진 열람·복원과 인바디 *입력*뿐.** 서버 사실 그대로 — `CreateInbody`는
  동의 필수(400), `ListInbody`·`DeleteInbody`는 스코프만.

## 진행 단계
- [x] P 클레임(P57은 백엔드 갈래가 먼저 잡아 P58로 재번호) + 서버 가드 코드 재확인
      (프로필·휴무 self OK / 사진 owner 전용 / 인바디 create는 동의 필수·list·delete는 스코프만)
- [x] api.ts `ApiError.code` · `isRouteNotFound()` · 체형사진 4동사(delete·restore·purge·reconcile)
- [x] Settings 거절 404 재해석 + "승인만 처리" 제거 · 승인 404도 같은 재해석 · CheckinQr/사진 업로드 규약 통일
- [x] MyProfile 탭(트레이너 전용) + App 네비 `trainerOnly` + ProfileModal `photoEditable`
- [x] BodyPhotos 재구성(잠금 범위 · 라이트박스 삭제 · 휴지통 복원 · 대표 점검 카드)
- [x] 검증(tsc 2종 · build · 번들 grep · 로즈 hex 0 · 새 코드 하드코딩 hex 0)
- [x] **v2.28 후속 배선**(코디네이터 요청) — 서버 휴지통(`include_deleted`) · 잠긴 회원 Meta 목록 + [삭제] ·
      `media_not_configured` code 분기 · 재검증

## 변경 파일 (전부 `admin/`)
| 파일 | 무엇을 |
|---|---|
| `src/lib/api.ts` | `ApiError.code`(응답 `code` 파싱) · `isRouteNotFound()`/`isMediaNotConfigured()`(둘 다 code만) · `bodyPhotos(member, {includeDeleted})` → `BodyPhotoListItem[]` · `deleteBodyPhoto`·`restoreBodyPhoto`·`purgeBodyPhotos`·`reconcileBodyPhotos` |
| `src/lib/types.ts` | `BodyPhoto.deleted_at` · **`BodyPhotoMeta`(v2.28 6키) · `BodyPhotoListItem` · `isFullBodyPhoto`(storage_path 유무)** · `BODY_PHOTO_PURGE_AFTER_DAYS`/`bodyPhotoPurgeDaysLeft({deleted_at})` · `BodyPhotoReconcileResult` |
| `src/lib/queries.ts` | `useBodyPhotos`는 항상 `include_deleted=true`(어드민=스태프) · 체형사진 4훅(`useDeleteBodyPhoto`의 `storagePath?`는 Meta엔 없음) · `useApproveJoin`/`useRejectJoin` `onError`에서 리소스 404·409면 큐 재조회 |
| `src/lib/bodyPhotoBlob.ts` | `evictBodyPhotoBlob(path)` — 삭제 성공 시 한 장만 비움(계약 v2.14 앱 요구와 동형) |
| `src/features/Settings.tsx` | 거절 404 두 갈래(라우터/리소스) + "승인만 처리" 삭제 · 승인 404 재해석(`JoinRequestGoneNotice`) · 사진 업로드 404 → `isRouteNotFound` · `OffdaysModal`/`ProfileModal`/`StaffAvatar`/`isProfileEmpty` export · `ProfileModal photoEditable` |
| `src/features/CheckinQr.tsx` | `isNotDeployed` → `isRouteNotFound` |
| `src/features/MyProfile.tsx` **신설** | 트레이너 전용 "내 프로필·휴무" 탭 — Settings 모달 2종 재사용, 대표만 바꿀 수 있는 값은 문장으로 |
| `src/App.tsx` | Section `me` · NAV `trainerOnly` · 필터/리셋 |
| `src/features/BodyPhotoLightbox.tsx` | `footer` 슬롯(삭제 컨트롤 자리) |
| `src/features/BodyPhotos.tsx` | 조회는 회원만 고르면 나감(잠긴 회원=Meta 200) · 잠금 판정은 응답 모양 · 잠금은 타임라인 카드 안으로 · **`LockedPhotoList`**(날짜·포즈 행 + [삭제] 2단) · 인바디 폼만 잠그고 목록·삭제 유지 · `PhotoDeleteConfirm`(라이트박스 footer·잠긴 목록 공용) · **`TrashCard`(서버 휴지통 — `deleted_at` 있는 것, 새로고침 유지)** · `OwnerPhotoTools`(정합 검사·apply 파기·기한 지난 사진 파기 · `media_not_configured` → "파기 경계가 설정되지 않았어요") |
| `README.md` | 역할별 탭 · 404 판정 규약 2절 |

## 검증
- (v2.28 후속 재검증) `tsc` 2종 0 · `build` 그린 · **번들 grep**(`index-Y1vwcVY6.js`): `include_deleted` 1 ·
  `media_not_configured` 1 · `route_not_found` 1 · "사진 목록 — 날짜·포즈만" 1 · "열람 잠김" 1 · "일 안에 복원 가능" 1 ·
  "새로고침하거나 다른 기기에서 열어도 같은 목록이 보여요" 1 · "회원이 다시 동의한 뒤에만" 1 · "다시 눌러도 달라지지
  않아요" 1 · **"새로고침하면 이 목록은 사라져요" 0 · "이 화면을 열어 둔 동안만" 0** · "승인만 처리" 0 · 로즈 hex 0
- 백엔드 실물 대조(읽기 전용): `handlers_media.go ListBodyPhotos`가 `include_deleted` 파싱 + `Locked`면 `Meta`
  응답 · `service.go BodyPhotoMeta` 6키 · `util.go` `ErrMediaListUnavailable → 503 errBodyWithCode{Code:
  codeMediaNotConfigured}` — 어드민 상수 `MEDIA_NOT_CONFIGURED_CODE`와 글자 단위 일치
- (1차) `npx tsc --noEmit`(tsconfig · tsconfig.node) 0 · `npm run build` 그린(1679 modules)
- **프로덕션 번들 grep(P50·P52 방식)** — 신규 문구 실재: `route_not_found` 1 · "이미 처리됐거나 회원이 그 사이
  앱에서 직접 연결됐어요" 1 · "승인도 거절도 더 필요 없어요" 1 · "내 프로필·휴무" 2 · "대표만 올리거나 바꿀 수
  있어요" 1 · "최근 삭제 — 이 화면에서 지운 사진" 1 · "일 뒤 완전 파기" 1 · "파기 경계가 설정되지 않았어요" 1 ·
  "정합 검사" 2 · "고아 파일 없음" 1 · "새 인바디 기록은 저장할 수 없어요" 1 · "사진 열람은 잠겼지만 삭제 요청은
  처리할 수 있어요" 1 · `body-photos/purge`·`/reconcile`·`/restore` 각 1
- **제거 확인**: "승인만 처리"·"그동안은 승인만" **0** · 옛 로즈 `f43f5e`/`e11d48` **0**(js·css) · `text-accent` 0
- 새 코드 하드코딩 hex 0(MyProfile·BodyPhotos)
- 백엔드 갈래(P57) 실물 대조: `router.go` NotFound가 `errBodyWithCode{Code: "route_not_found"}` — 어드민 상수와
  **글자 단위 일치**. `DeleteBodyPhoto`가 `checkMemberScope`로 바뀜(B1 반영) → 잠금 문구 "삭제는 막히지 않아요"가 참.
  `ErrMediaListUnavailable` → 503(util.go:102) → 어드민 `isMediaNotConfigured`(비-transport 503)가 그 자리를 받는다.

## 자문자답
1. **B3에서 왜 설정 탭을 여는 대신 별도 탭인가?** 설정 탭의 카드 7개 중 서버가 트레이너 본인에게 허용하는 동사는
   프로필 PUT·휴무 POST 둘뿐이고(`service.go` `!p.IsOwner() && p.UID != uid`), 나머지(정책·사업자·신원·가입 승인·
   QR·초대·정정·이관·퇴사)는 전부 owner 403이다. 탭을 열고 카드마다 `isOwner` 게이트를 달면 트레이너에겐 빈 화면
   + "직원 표에 내 행 하나"가 남는데, 그 표의 [정정][이관][퇴사]도 다 숨겨야 해서 결국 다른 화면이 된다. 그럴 바엔
   **허용된 두 동사만 가진 화면**을 하나 두고 모달을 공유하는 편이 코드도 문장도 정직하다. 헤더 진입점(이름 클릭)은
   발견성이 낮아 기각 — 사이드바 탭 5개뿐인 트레이너에게 탭 하나는 싸다. 대표에겐 숨긴다(설정 탭 직원 표가 같은 문).
2. **사진 업로드도 열어야 하나?** 열면 안 된다 — `UploadStaffPhoto`는 `!p.IsOwner()`로 403이고 그 이유가 코드에
   적혀 있다(공용 버킷 쓰기·비용·되돌리기 수단이 대표에게). 그래서 `photoEditable=false`로 컨트롤을 빼고 "대표에게
   파일을 보내주세요"를 적었다. 단 통 교체 PUT이라 `photo_url`은 손대지 않은 값을 그대로 다시 싣는다(빼면 지워진다).
3. **A2 삭제 확인이 승인 모달만큼 무거워야 하나?** 아니다. 승인·거절은 되돌릴 수 없어 창 하나를 더 두는 값어치가
   있었지만, 스태프의 사진 삭제는 소프트 삭제(30일 복원)다. 되돌릴 수 있는 동사에 같은 무게를 얹으면 대표는 두 확인을
   똑같이 습관으로 눌러 넘기고 정작 무거운 쪽 확인이 무의미해진다(RejectJoinModal 주석의 같은 논거). 대신 **자리**로
   안전을 산다: 삭제 버튼은 원본이 보이는 라이트박스 footer에만 있다 — 타임라인 타일은 아이콘+날짜라 거기에 달면
   "보지 않은 사진을 지우는 UI"가 된다.
4. **휴지통을 서버 목록으로 바꿀 때 조회를 둘로 쪼개야 하나(살아 있는 것/삭제분)?** 아니다. `include_deleted=true`
   하나로 받아 `deleted_at`으로 가르면 캐시 키가 하나라 삭제·복원 무효화 한 번에 타임라인·휴지통이 같이 맞고, 두 조회가
   서로 다른 시점을 가리키는 일이 없다. 어드민은 늘 스태프라 이 파라미터가 403이 날 일도 없다(회원만 403). v2.28 이전
   서버는 파라미터를 모른 채 살아 있는 것만 주므로 깨지지 않고 휴지통이 비어 보일 뿐이다.
5. **철회 회원의 메타 목록에 날짜·포즈가 보이는 것 자체가 민감정보 노출인가?** 아니다 — **사진의 존재 사실과 내용은
   다르다.** 메타에는 사진 바이트에 닿는 값(`storage_path`·URL)이 없고 Storage 규칙도 여전히 막는다. 이 목록을 볼 수
   있는 사람은 스코프 안 스태프(담당 코치·대표)뿐이라(스코프 밖은 그대로 403) 그들은 그 사진을 찍은 당사자로 존재
   사실은 이미 안다. 동의 철회가 거두는 것은 "내용을 계속 보는 처리"이고, 삭제는 정보주체의 요청을 **이행하는** 처리라
   동의와 별개로 정당하다 — 오히려 목록 없이는 철회한 회원의 삭제 요청을 스태프가 이행할 수 없다는 게 더 큰 문제였다.
   그래서 목록에 `direction`·`blurred`도 그리지 않고 대상을 고르는 데 필요한 날짜·포즈만 보여준다. 한 가지 정직하게 적은
   한계: 스태프 삭제는 30일 유예(소프트)라 "지체 없이 파기"가 필요하면 회원 본인의 앱 삭제(즉시 파기)가 확실하다고
   문장으로 말한다.
6. **정합 검사를 왜 설정이 아니라 체형 분석 탭에?** reconcile은 `member` 필수(회원 한 명의 폴더). 회원 셀렉트가 있는
   화면이 맞고, 설정에 두면 같은 셀렉트를 하나 더 만든다. purge는 센터 전체지만 같은 주제라 한 카드.
7. **인바디를 "그대로" 두면 되나?** 아니다 — `CreateInbody`만 동의 필수(400)라 폼을 그대로 두면 저장에서 400을 받는
   UI가 된다. 폼만 잠그고 목록·삭제는 열었다(서버 `ListInbody`·`DeleteInbody`는 스코프만).
8. **404 규약 변경으로 손해 보는 창은?** 백엔드보다 어드민이 먼저 배포되는 창에서 진짜 라우터 404가 `code` 없이 오면
   미배포 안내 대신 "이미 처리됐거나…"(거절)·"찾을 수 없음"(QR·사진)이 뜬다. 셋 다 **다음 행동이 안전**(재조회·
   재시도)하고 P57이 이미 `code`를 심었으니 그 창은 배포 순서로 닫힌다. 반대 방향(리소스 404를 미배포로 오독)이
   위험했던 것이고, 그쪽은 닫혔다.

## 백엔드 갈래에 요청한 것 → 전부 반영됨(P57 · 계약 v2.28), 어드민 배선 완료
1. `GET /v1/body-photos?member=&include_deleted=true` — 반영. 어드민 `useBodyPhotos`가 항상 켠다 → `TrashCard` 서버 기반.
2. 철회 회원의 삭제 대상 선택 수단 — `BodyPhotoMeta[]`(200)로 반영. 어드민 `LockedPhotoList` + [삭제].
3. 503 `code:"media_not_configured"` — 반영. 어드민 `isMediaNotConfigured`가 code만 본다.
4. `route_not_found`·`media_not_configured` 문자열 고정 — 계약 v2.28 절에 "어드민 상수와 글자 단위로 맞춰져 있으므로
   바꾸지 말 것" 명시됨(확인).

## 후속 작업
- 잠긴 회원의 스태프 삭제는 30일 유예(소프트)다 — 철회 회원의 "지체 없이 파기" 요청을 스태프가 즉시 이행할 동사는
  아직 없다(어드민 `purge`는 유예 지난 것만). 필요하면 백엔드에 "정보주체 요청 대리 즉시 파기" 플래그를 제안.
- 대시보드 "해야 할 일"에 트레이너의 "프로필 미등록" 항목(→ 내 프로필 탭 링크)은 이번에 넣지 않았다 — 탭 하나로
  충분한지 실사용 뒤 판단.
- 배포는 람이 한다(백엔드 P57과 같은 배포 창에 — 8번 자문자답의 순서 이유. v2.28 응답 모양은 구서버에서도
  깨지지 않게 짰다: `include_deleted` 무시 → 휴지통만 비어 보임 / 잠긴 회원 403 → 잠긴 목록 자리에 ErrorState+재시도).

## 참조
- P56(감사) · P55(C-2 좀비 경합) · P50/P52(번들 grep 검증 방식) · 계약 v2.14(체형사진 삭제 분기)
