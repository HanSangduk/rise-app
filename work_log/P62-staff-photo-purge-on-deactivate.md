---
id: P62
title: 스태프 퇴사 시 프로필 사진 파기 — 보존 근거 없는 개인정보 잔류 수리(P56 B13)
status: 완료
domain: cross
created: 2026-09-06
completed: 2026-09-06
---

# P62 — 스태프 퇴사 시 프로필 사진 파기 (P56 B13)

## 목표
스태프 퇴사(`POST /v1/staff/{uid}/deactivate`)가 프로필 사진 파일(`staff/photos/`)을 버킷에 무기한 남기던
결함을 닫는다. 사진의 유일한 목적은 회원 앱 공개(privacy.html)이고 퇴사로 소멸하는데, 근로자 명부 3년·정산
5년 어디에도 사진은 없다(개인정보 보호법 §21① 목적 달성 시 파기). 회원 응답 마스킹(v2.0)은 화면만 감췄다.
4칸(서버·클라이언트·계약문서·법정문서)을 함께 옮긴다. 설계 `scratchpad/design_B13.md`, 적대 검토 2건
(`review_B13_0.md`·`review_B13_2.md`)이 설계의 best-effort 정책과 "어드민 무변경" 판단을 뒤집었다.

## 결정 사항
- **실패 정책 = 전파**(설계의 best-effort 기각, 검토 #2). 순서 ①DisableUser → ②UserIndex 강등 → **③ 사진 파기**
  → ④SaveStaff. ③ 시점엔 ②가 끝나 사람이 이미 잠겨 있어 500이 보안을 늦추지 않고, status가 active로 남아
  재시도가 멱등으로 수렴한다(firebaseMediaPurger는 ErrObjectNotExist를 성공으로 셈) — 기존 ④ 실패 전파와
  같은 취급. best-effort였다면 privacy.html의 "삭제됩니다"가 재시도 동사 없는 거짓 약속이 된다.
- **③이 ①② 뒤·④ 앞인 이유**: 삭제는 불가역(①② 실패 시 재직자 사진이 사라지면 안 됨) / 저장 뒤 삭제는 실패 시
  포인터 유실 → 고아(P22). 저장 앞 삭제는 ④ 실패 시 죽은 링크 창이지만 아바타 폴백 + 재시도 수렴.
- **불변식** `photo_url == ""` ⇔ 우리 파일 없음. 외부 URL은 파일도 포인터도 무변경(파기할 수 없는 것을
  "삭제됨"처럼 보이지 않게). 성공 시에만 `PhotoURL = ""`. prevPath==""면 DeleteObjects 미호출.
- **UpdateStaffProfile에도 같은 파기 판정**(검토가 잡은 두 번째 구멍): 어드민 [사진 지우기] = 빈 photo_url PUT이
  고아를 만들던 경로. `prev != "" && prev != next`면 저장 **전** 삭제, 실패 전파(프로필 무변경). 통 교체라 같은
  URL 되돌림은 prev==next → 삭제 없음.
- **UploadStaffPhoto 퇴사자 400** "퇴사 처리된 스태프의 사진은 올릴 수 없어요 — 재입사 처리 후 올려주세요"
  (업로드 전, 파일 미생성) — 파기의 역행 경로 차단.
- `deleteStaffPhotoObject(ctx, uid, path, why) error` — 로그에 uid(파기 실패 행을 좇는 유일한 키).
  ~~Upload ⑤(교체 삭제, 저장 뒤)는 best-effort 유지~~ → **검증 반영으로 뒤집음: 교체도 전파**(아래 절).
- ~~**미구성 purger 창**: no-op 성공 → URL은 비워지고 파일은 남을 수 있다~~ → **검증 반영으로 뒤집음:
  `Configured()`를 보고 파기를 건너뛰며 photo_url 유지**(아래 절).
- **어드민은 문안만이 아니다**(검토 #0·#2): 퇴사 행 ProfileModal에 `photoEditable={isStaffActive(s)}` — 눌러야
  실패하는 [사진 선택]을 만들지 않고 서버 400과 같은 문장(MyProfile owner-only 선례).
- 계약 번호는 **v2.31** — L9(P61)가 v2.30을 먼저 썼다. work_log 번호도 P61 존재 → P62.
- 복직·재고용 코드 무변경(사진은 되살릴 것이 없다). 주석만 정정.

## 검증 반영 (2026-09-06, 적대 검증 이슈 8건 전부)

검증이 초판의 구멍 8개를 잡았다. 결정 변경 2건(교체 ⑤도 전파 · 미구성 시 포인터 유지)을 포함해 전부 반영.

| # | 이슈 | 수정 |
|---|------|------|
| 1 HIGH | `staffPhotoObjectPath`가 접두 `staff/photos/`만 봐서 A의 photo_url이 재직자 B의 파일을 가리키면 A 퇴사/PUT이 **B 파일을 지움** | 업로드 명명 규칙 `staff/photos/{uid}-{난수}.{ext}`의 uid를 소유권으로: `staffOwnedPhotoPath(uid, url)`(`{uid}-` 하이픈까지 비교) + `(s *Service) ownedStaffPhotoPath`(STORAGE_BUCKET 설정 시 버킷 명의까지). 퇴사 ③·PUT·⑤ 세 자리 교체. 남의 uid·다른 버킷 = 외부 URL과 동일(파일·포인터 무변경) |
| 2 HIGH | stale PUT(업로드 2회 뒤 옛 URL 저장)이 **현재 파일을 지우고 죽은 링크를 박음** | `next != "" && next != prev` → **409** "사진이 그 사이 바뀌었어요 — 새로고침 후 다시 저장해주세요". 프로필 PUT은 우리 파일 포인터를 새로 만들 수 없다(업로드 엔드포인트만) — v1.6 통 교체의 유일한 예외로 계약에 표기. 퇴사가 파기한 URL 되살리기도 같은 409. 어드민은 서버 error 문구를 그대로 그려(api.ts req) 코드 변경 0 |
| 3 MED | 교체 ⑤ best-effort — 삭제 실패가 성공한 교체 뒤에 숨어 옛 파일이 고아 | 순서 "③ 업로드 → ⑤ prev 삭제(실패 시 새 파일 best-effort 되지우기 + 에러 전파, 프로필 무변경) → ④ SaveStaff(실패 시 새 파일 되지우기)". 공통 헬퍼 `purgeStaffPhoto`. privacy.html "교체하거나 지우면 이전 파일은 삭제되며"가 참이 됨 |
| 4 MED | privacy.html 처리위탁 표 Cloud Storage 행이 "체형사진"뿐 | "체형사진, 스태프 프로필 사진" |
| 5 MED | 미구성 purger의 no-op 성공을 믿고 photo_url을 비워 **파일은 남고 포인터만 유실** | `MediaPurger.Configured() bool` 신설(unconfigured=false, firebase=true, 테스트 대역 true). 스태프 경로 3자리는 미구성이면 파기 건너뜀 + `log.Printf("staff photo purge skipped uid=… path=…")` + photo_url 유지(퇴사·저장은 진행). 회원탈퇴 경로 종전대로. 기동 경고 3분기 문구 정정 |
| 6 MED | 어드민 퇴사 행이 값과 무관하게 "삭제됐어요"라 말하고 정리 경로가 없음 | ProfileModal에 `clearable` 프롭(기본 = photoEditable — MyProfile은 범위 밖이라 프롭 이름 유지). 퇴사 행 `photoEditable=false clearable`. 문장을 저장된 photo_url로 분기: 빈 값 "퇴사 때 업로드했던 사진 파일은 삭제됐어요" / 값 잔존 "이전 방식으로 남았거나 외부 주소인 사진이에요 — [사진 지우기] 후 저장하면 파일도 삭제돼요" + [사진 지우기] 버튼. 명사 '직원' → '스태프'(서버 400과 통일) |
| 7 MED | 배포 순서에 잔류 정리가 없음 | 서버 → 잔류 측정·정리(gcloud rm + inactive 문서 photo_url 비움, 또는 어드민 [사진 지우기]) → 어드민·privacy Hosting |
| 8 LOW | PUT 절 실패 창 미기술 | "삭제 성공 뒤 SaveStaff 실패 창(파일 없음·URL 잔존·아바타 폴백), 같은 PUT 재시도로 수렴, 같은 URL 되돌림은 창을 닫지 않음" + `TestUpdateStaffProfileSaveFailureAfterDeleteConvergesOnRetry`(hookStore SaveStaff n==2)로 고정 |

**자문자답.** (a) 트레이너 본인 편집 중 대표가 사진을 교체하면 본인 저장이 409 — 의도된 것(새로고침이 remedy,
문구가 말한다). (b) 미구성 서버에서 [사진 지우기] 저장은 사진이 그대로 보인다 — 포인터 유실보다 낫고 로그가
말한다. 그 환경은 업로더도 미구성이라 새 파일이 생기지 않는다. (c) 버킷 명의 검사는 `cfg.StorageBucket`이 비면
건너뛴다 — 그 환경의 purger는 어차피 미구성이라 실제 삭제가 없다. (d) 이 배포 이전 퇴사분은 어드민 퇴사 행의
[사진 지우기] → 저장으로 대표가 문서당 1클릭 정리 가능(서버가 파일까지 지운다) — 콘솔 작업의 대안.

신규·갱신 테스트: `TestStaffOwnedPhotoPath` · `TestOwnedStaffPhotoPathBindsBucket` · `TestDeactivateNeverDeletesForeignPhotoURL`
(표 +2: t2 명의·다른 버킷) · `TestDeactivateDoesNotDeleteAnotherStaffsUploadedPhoto` · `TestUpdateStaffProfileClearingAnotherStaffsURLDeletesNothing`
· `TestUpdateStaffProfileStaleOurURLIs409AndDeletesNothing` · `TestUpdateStaffProfileStaleURLWireIs409` ·
`TestUpdateStaffProfileSaveFailureAfterDeleteConvergesOnRetry` · `TestDeactivateWithUnconfiguredPurgerKeepsURL`(ClearsURL에서 뒤집음) ·
`TestUpdateStaffProfileWithUnconfiguredPurgerKeepsURL` · `TestStaffPhotoReplacementDeleteFailurePropagatesAndKeepsProfile`
(DoesNotFailUpload에서 뒤집음) · `TestStaffPhotoReplacementCleansUpNewObjectWhenOldDeleteFails`(recordingPurger.failOnce) ·
`TestStaffPhotoReplacementNeverDeletesForeignObjects`(표 +2). 픽스처 `seedStaffPhotoURL`(PUT은 이제 우리 파일 포인터를 못 만든다).

뮤테이션 3/3 KILLED(실제 변경 → 실행 → cmp 복원 확인):
- M-A uid 결속 제거(`staffPhotoPrefix+uid+"-"` → 접두만) → StaffOwnedPhotoPath · DeactivateNeverDeletesForeignPhotoURL ·
  DeactivateDoesNotDeleteAnotherStaffsUploadedPhoto · UpdateStaffProfileClearingAnotherStaffsURLDeletesNothing ·
  StaffPhotoReplacementNeverDeletesForeignObjects **FAIL**(5)
- M-B 409 가드 제거 → UpdateStaffProfileStaleOurURLIs409AndDeletesNothing · UpdateStaffProfileStaleURLWireIs409 **FAIL**(2)
- M-C Configured 분기 제거 → DeactivateWithUnconfiguredPurgerKeepsURL · UpdateStaffProfileWithUnconfiguredPurgerKeepsURL **FAIL**(2)

검증: `go build ./... && go vet ./internal/api/ && go test ./... -count=1` 전 패키지 ok · `cd admin && npm run build` ✓.
(무관 플레이크: `TestBodyPhotoListLockedIsMetaOnlyOnWire`가 간헐 실패 — 잠긴 목록 `rows[0]`을 지우는데 목록 순서가
비결정적이라 `keep`이 지워지는 회차가 있다. 이 체인 범위 밖 파일(service_wire_null_test.go), 미수정.)

## 진행 단계
- [x] 설계·검토 2건 읽고 최종 결정 12개 반영 계획
- [x] 서버: service_staff_photo.go(헬퍼 시그니처·uid 로그·IsActive 400·주석) · service_staff.go(③ 파기, ④ 재번호,
      Reactivate 주석) · service.go(UpdateStaffProfile 파기·rehire 주석) · provision.go(경고 3분기)
- [x] 하네스: recordingPurger.calls · recordingProvisioner.failDisable+DisableUser · hookStore.SaveUserIndex
- [x] 테스트 16건 신설(`service_staff_photo_purge_test.go`) — 전건 그린, 전 패키지 그린
- [x] 뮤테이션 5건 kill(검증 절)
- [x] 계약: v2.0 deactivate 부수효과·재고용 photo_url 예외 / v2.25 오류표 400 행·"퇴사·탈퇴와의 관계" 개정 표기 /
      파일 끝 v2.31 절
- [x] 법정: privacy.html 프로필 사진 행 1문장
- [x] 어드민: Settings.tsx photoEditable 배선 + 퇴사자 문장 + 모달 문안 4곳 — `npm run build` 통과
- [x] 검증 이슈 8건 반영(위 절) — 테스트 갱신·신설 13건, 뮤테이션 3/3, 계약 v1.6/v2.25/v2.31, privacy 처리위탁 행, 어드민 clearable
- [ ] **람**: 서버 배포 → 잔류 파일 측정·정리(gcloud rm + inactive 문서 photo_url 비움, 또는 어드민 [사진 지우기]) →
      어드민·privacy.html Hosting 배포(순서 고정 — 검증 반영으로 정리 단계가 서버 뒤·Hosting 앞에 들어감)

## 변경 파일
(검증 반영분) `backend/internal/api/provision.go` — `MediaPurger.Configured()` + 두 구현 + 경고 문구 3분기 /
`service_staff_photo.go` — `parseStaffPhotoURL`·`staffOwnedPhotoPath`·`ownedStaffPhotoPath`·`purgeStaffPhoto`, Upload ③→⑤→④ /
`service_staff.go` — ③ ownedStaffPhotoPath + Configured 분기 / `service.go` — UpdateStaffProfile 409 가드 + purgeStaffPhoto /
테스트: `service_staff_photo_purge_test.go`·`service_staff_photo_test.go`(seedStaffPhotoURL·testPhotoBucket) ·
`service_body_photo_delete_test.go`(Configured·failOnce) · `service_account_test.go`(Configured) /
`docs/API계약_v1.md` v1.6 예외·v2.25 교체 절 개정·v2.31 ③/불변식/PUT 409/⑤/미구성/법정문서/배포 순서 /
`admin/public/legal/privacy.html` 처리위탁 Cloud Storage 행 / `admin/src/features/Settings.tsx` ProfileModal clearable
- `backend/internal/api/service_staff_photo.go` — `deleteStaffPhotoObject(ctx, uid, path, why) error`(uid 로그·에러 반환),
  UploadStaffPhoto `!st.IsActive()` 400, Upload 호출부 2곳 `_ =`(초판 best-effort — 검증 반영으로 전파로 개정), staffPhotoPrefix/ObjectPath 주석
- `backend/internal/api/service_staff.go` — DeactivateStaff ③ 파기 블록(순서·전파·동시성 한계 주석), ④ 재번호,
  ReactivateStaff 주석
- `backend/internal/api/service.go` — UpdateStaffProfile prev/next 파기 판정(저장 전·전파), rehireStaff 주석
- `backend/internal/api/provision.go` — MediaPurger 강등 경고 3분기 문구
- `backend/internal/api/service_staff_photo_purge_test.go` — 신설 16건
- `backend/internal/api/service_body_photo_delete_test.go` — recordingPurger.calls
- `backend/internal/api/service_account_test.go` — recordingProvisioner.failDisable + DisableUser
- `backend/internal/api/hookstore_test.go` — SaveUserIndex 래핑(hookedOps 미포함)
- `docs/API계약_v1.md` — v2.0 :529-532·:541-545 / v2.25 :2751·:2811 / 파일 끝 v2.31 절
- `admin/public/legal/privacy.html` — :215 프로필 사진 행
- `admin/src/features/Settings.tsx` — ProfileModal 호출부 photoEditable, 읽기 전용 문장 분기(재직/퇴사), 초대·퇴사(2)·
  재입사 모달 문안
- `work_log/P62-staff-photo-purge-on-deactivate.md` · `work_log/README.md`

## 검증
- `cd backend && go build ./... && go test ./... -count=1` → api·config·domain·store **ok** · `go vet ./internal/api/` 무출력
- `cd admin && npm run build` → ✓ built
- 신규 16건: DeactivateDeletesUploadedPhotoAndClearsURL · DeactivateNeverDeletesForeignPhotoURL(3종 표) ·
  DeactivatePhotoDeleteFailurePropagates(500·active·URL 유지·UserIndex member·재시도 수렴) ·
  DeactivateWithoutPhotoCallsNoDelete(calls==0) · DeactivateSaveFailureAfterDeleteConvergesOnRetry(hookStore SaveStaff n==2,
  재시도 후 deleted 2건) · DeactivateDisableUserFailureLeavesPhotoIntact · DeactivateIndexDemotionFailureLeavesPhotoIntact ·
  DeactivateWithUnconfiguredPurgerClearsURL(초판 — 검증 반영에서 …KeepsURL로 뒤집음) · UploadStaffPhotoRejectsInactiveStaff · ReactivateDoesNotRestorePhoto(복직 후
  업로드 재개) · RehireDoesNotRestorePhoto(devUserProvisioner 해시 uid) · UpdateStaffProfileClearingPhotoDeletesObject ·
  UpdateStaffProfileSameURLDoesNotDelete(owner·trainer) · UpdateStaffProfileExternalURLReplacesAndDeletesOurs ·
  UpdateStaffProfileDeleteFailureLeavesProfileUntouched · DeactivateWireClearsPhotoURLAndBlocksReupload(newTestRouterSharing
  + uploader 주입, `"photo_url":""` 바이트·400 본문)
- 기존 회귀: TestListStaffMasksInactiveProfileForMembers · TestTransferThenDeactivateJourney · TestRehireInactiveStaffViaInvite ·
  TestStaffPhoto* 전건 그린(Upload ⑤ 반환 무시로 동작 무변경)
- 뮤테이션(실제로 바꿔 실행 후 cmp로 복원 확인 — 5/5 KILLED):
  - M1 ③ 블록 제거 → Deletes…ClearsURL · PhotoDeleteFailurePropagates · SaveFailure…Retry · Wire… · UnconfiguredPurger… ·
    Reactivate… · Rehire… **FAIL**(7)
  - M2 `PhotoURL=""` 무조건 대입 → NeverDeletesForeignPhotoURL **FAIL**(1 — 외부 URL 포인터 유지가 이 뮤턴트를 잡는 유일한 테스트)
  - M3 IsActive 가드 제거 → UploadStaffPhotoRejectsInactiveStaff · Wire… **FAIL**
  - M4 UpdateStaffProfile 삭제 제거 → ClearingPhoto… · ExternalURL… · DeleteFailure… **FAIL**
  - M5 ③을 ① 앞으로 → DisableUserFailure… · IndexDemotionFailure… · PhotoDeleteFailurePropagates **FAIL**
    (검토 #0이 "어떤 테스트도 못 잡는다"고 지적한 순서 근거가 이제 고정됨)

## 후속 작업
1. **람 — 잔류 측정**: `gcloud storage ls gs://<STORAGE_BUCKET>/staff/photos/ | wc -l` vs Firestore `staff`의
   `profile.photo_url`이 `staff%2Fphotos`인 문서 수(active/inactive 별). 0 → 할 일 없음 / 소수 → `gcloud storage rm` +
   콘솔에서 inactive 문서 photo_url="" / 재발 도구 필요 → `POST /v1/staff/photos/reconcile` 별도 P.
2. **람 — softDelete 확인**: `gcloud storage buckets describe gs://<STORAGE_BUCKET> --format='value(softDeletePolicy)'` —
   켜져 있으면 스태프·체형사진 모두 "삭제" 뒤 최대 7일 복구 가능 잔존(privacy.html 백업 콜아웃은 DB만 말한다).
3. **람 — 배포 순서(검증 반영)**: 서버(`gcloud run deploy`) → 잔류 측정·정리(1번 — 또는 어드민 퇴사 행 [사진 지우기] 후 저장)
   → 어드민+privacy.html(`deploy-hosting.sh`). 고지가 구현을 앞서면 안 되고, 어드민의 "삭제됐어요"는 잔류가 정리된 뒤에야 참이다.
4. 후속(P56 등재): 스태프 프로필 나머지 칸(직함·경력·자격·소개)의 퇴사 후 보존 근거와 privacy.html 보유기간 표의
   스태프 정보 행 부재. work_log/P56 :225 후속 4 취소선 — 이 체인의 파일 범위 밖이라 미수정.
5. 동시성 창(deactivate ③~④ 사이 업로드 → 고아)은 계약에만 적었다. 닫으려면 트랜잭션 또는 낙관적 버전.

## 참조
- 설계·검토: `scratchpad/design_B13.md` · `review_B13_0.md` · `review_B13_2.md` · 감사 `work_log/P56-broken-promises-audit.md` B13
- 계약: `docs/API계약_v1.md` v2.31(+ v2.0·v2.25 개정 표기) · 선례 v2.11(탈퇴 파기 실패 전파) · v2.25(Upload ⑤ best-effort) ·
  v2.28(unconfiguredPurger 두 동사)
- 법령: 개인정보 보호법 §21① · 근기법 §42·시행령 §20(근로자 명부 항목에 사진 없음)
