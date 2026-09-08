---
id: P57
title: 백엔드 결함 5+2건 수리 — 승인 후 잔류 개인정보 · installments null · 파기 경계 조용한 강등 · 철회 후 삭제 403 · 라우터 404 구분 (계약 v2.28)
status: 완료
domain: backend
created: 2026-09-04
completed: 2026-09-04
---

# P57 — 백엔드 결함 수리 (P56 감사 후속, 백엔드 갈래)

## 목표
P56 감사가 남긴 백엔드 항목 중 "저장소가 다른 곳에서 이미 내린 판단과 어긋나는 자리" 5건 + 어드민
갈래(P58)가 요청한 완결 항목 2건(잠긴 목록 메타 · include_deleted)을 닫는다. `backend/` ·
`docs/API계약_v1.md`만 만졌다(`app/`·`admin/`은 다른 갈래가 동시 편집 — 무접촉).

| # | 자리 | 선례(저장소가 이미 내린 판단) |
|---|---|---|
| A5 | `JoinApprove`가 이름·번호를 남긴다 / `DoneConsultRequest`가 note를 남긴다 | 3줄 옆 `JoinReject`는 *"처리 목적이 끝난 개인정보"*라며 비운다. P53: 상담 요청은 5년 보존 대상 아님 |
| A3 | `installments: null` — 어드민 `Members.tsx:726` `.filter` 무가드 | `Flags`·`Holds`는 *"JSON null 방지(어드민 크래시)"* 주석까지 달고 정규화 |
| A4 | 파기 경계 강등 4곳이 `ListObjects → nil,nil` → reconcile 항상 "고아 0건" | 같은 파일 `unconfiguredUploader`는 *"조용한 성공을 절대 만들지 않는다"* — 503 |
| B1 | `DeleteBodyPhoto`가 열람용 동의 게이트를 재사용 → 철회 후 스태프 삭제 403 | 형제 `DeleteInbody`: *"삭제는 동의 철회 이후에 더 필요한 동작"* — 동의 안 봄 |
| B12 | 라우터 404와 리소스 404가 status·body 동일 | 어드민 "404=미배포" 규약이 원리적으로 성립 불가 → B6 위험 지시의 뿌리 |
| B1완결 | 철회 상태 `GET /v1/body-photos` 403 → 스태프가 지울 id를 못 얻음 | "서버만 열린 절반 수리"(P56 메타 발견) |
| v2.14완결 | `include_deleted` 없음 → 어드민 휴지통이 세션 한정 | v2.14 "30일 안에 복원" 약속 |
| L11 | 계약 v2.11 절 "404 미연결"이 v2.27 이후 스테일 | P53이 v2.11 절을 개정한 방식 그대로(옛 절에 개정 표시) |

## 결정 사항

### A5 — 승인도 거절과 동형. "누구였는지"는 회원 레코드가 답한다
승인은 이름·번호를 회원 레코드로 **옮기는** 동작이지 복사하는 동작이 아니다. SaveMember가 끝난 순간
요청 문서의 값은 처리 목적을 잃고, 그 사본은 개명·정정을 따라가지 않아 남길수록 틀려진다. 남기는 것은
`{uid, center_id, status=approved, created_at}` — /v1/me의 join_request(status·created_at)와 감사 추적에
필요한 전부다. 순서는 **SaveMember 뒤**(mem이 jr.Name을 복사한다) — 뮤테이션 M2가 그 순서를 고정한다.
`DoneConsultRequest`도 같은 판단으로 note를 비우고 행은 남긴다(done→done 멱등 유지).

### A3 — 쓰기+읽기 이중 방어. nil이 의미를 갖는 배열은 제외
읽기 정규화 헬퍼 3개(`service_wire_normalize.go`)를 목록·단건 응답의 관문(`hydratePassRemaining` ·
`stampPassStatus` · `ListMembers` 두 분기 · `ListPayments`)과 쓰기 관문(`CreatePayment` · `UpdateMember`
저장 직전 — PUT이 null 문서를 **치유**)에 걸었다. `Member.BodyPoses`는 nil="센터 기본"이라 제외.
`PayInstallment`의 읽기 정규화는 **뺐다** — 인덱스 가드가 `len(nil)==0`으로 먼저 400을 내 응답에 nil이
실릴 수 없다(뮤테이션 M6가 등가로 살아남아 확인). 죽일 수 없는 코드는 두지 않는다.

### A4 — 두 동사의 실패 모양을 일부러 다르게
`devMediaPurger` → `unconfiguredPurger{reason}`. `ListObjects`는 `ErrMediaListUnavailable`(503 +
`code:"media_not_configured"`), `DeleteObjects`는 종전 no-op 유지. 훑기는 조회라 크게 실패해도 잃는 것이
없고 조용히 성공하면 "버킷이 깨끗하다"는 거짓 보고가 된다. 탈퇴는 §36 삭제 요구권이라 배포 설정 하나에
막히면 그쪽이 더 큰 거짓이다(P51 결정 유지). 4개 강등 경로마다 reason이 다르다 — 503 본문이 무엇을
설정해야 하는지 말해야 고칠 사람이 원인에 도달한다(uploader와 같은 규율).

### B1 — 파기 동사만 풀고, 목록은 403 대신 "잠긴 메타"
`DeleteBodyPhoto`: `checkBodyPhotoAccess` → `checkMemberScope`(스코프 유지, 동의 제거). Restore·List의
열람 게이트는 그대로. 그런데 목록이 403이면 스태프는 지울 id를 못 얻는다(어드민 갈래 지적) →
`BodyPhotoListing{Locked, Full, Meta}`: 스태프+스코프 안+동의 무효 → `BodyPhotoMeta[]`(id·member_id·
pose·direction·date·deleted_at? — storage_path·blurred 없음). 배열은 유지(회원 앱이 배열을 읽는다).
`include_deleted=true`는 스태프 전용, 회원은 **403**(조용히 무시하지 않는다 — 그 파라미터를 보내는 회원
앱은 버그).

### B12 — code는 라우터 404에만
`errBodyWithCode{error, code}` 신설. 라우터 404 = `route_not_found`, 리소스 404 무변경(code 없음), 405
무변경. 어드민 상수와 글자 단위 일치 — 계약에 "바꾸지 말 것" 명시.

## 자문자답
1. **approve 시 이름을 비우면 어드민 승인 큐 이력에서 누구였는지 못 보게 되는데 괜찮은가?** 괜찮다 —
   큐는 pending만 보여주고(v2.27) 이력 뷰는 없다. 있더라도 "누구"는 회원 레코드(uid→UserIndex→member)가
   답하고, 요청 문서의 이름은 그 레코드와 같은 값의 사본이다. 이력이 필요해지면 v2.27 남은 갭 ④(status
   파라미터)로 열되 uid로 회원을 조인하면 된다.
2. **A4에서 탈퇴 파기와 reconcile을 왜 다르게 다루나?** 실패의 대가가 반대다. 훑기는 조회 — 실패해도
   잃는 것이 0, 조용한 성공은 고지와 어긋난 잔존(고아 50개의 실사고). 탈퇴는 §36 — 실패하면 개인정보를
   지울 권리가 배포 설정에 막히고, 파기의 본체(메타·계정·인덱스)는 버킷 없이도 된다. 같은 인터페이스의
   두 동사가 다른 모양으로 실패하는 것이 어색하지만, 타입 주석에 이유를 못 박았다.
3. **DeleteBodyPhoto에서 동의를 빼면 남의 회원 사진을 지울 수 있게 되나?** 아니다 — `checkMemberScope`가
   owner=전체·trainer=담당·member=본인을 그대로 강제한다. 뮤테이션 M15 + `TestDeleteScope`(담당 아닌 코치
   403)가 고정한다. 동의 게이트가 막던 것은 "담당인데 철회한 회원"뿐이고, 그것이 정확히 방침이 안내하는
   경로였다.
4. **PayInstallment에서 읽기 정규화를 빼도 계약("항상 배열")이 깨지지 않나?** 안 깨진다 — installments가
   null인 결제에 PayInstallment를 부르면 인덱스 가드가 400을 내 그 응답에 결제 본문이 실리지 않는다.
   200 응답의 installments는 인덱스가 유효했으므로 최소 1개 원소가 있다.
5. **잠긴 목록이 같은 엔드포인트의 원소 모양을 바꾸는 것이 "자기모순"(P56 클래스 2) 아닌가?** 판별자가
   하나(회원의 consent + storage_path 유무)이고 두 상태를 동시에 말하지 않는다. 배열을 객체로 감싸면 회원
   앱이 깨지고, 별도 엔드포인트는 같은 목록의 두 번째 진입점을 만든다. 남은 갭 ④에 적어 두었다.
6. **holds 단건 응답 결함이 왜 Memory 테스트로 안 잡혔나?** Memory의 `UpdatePassWithLedger*`가 롤백 안전을
   위해 `append([]Hold{}, cur.Holds...)`로 새 슬라이스를 만든다 — Firestore의 fromDoc(JSON)과 다른 모양.
   래퍼 스토어로 Firestore 모양을 흉내 내 M11을 죽였다. P49·P53의 "에뮬레이터 전용 자리"와 같은 계열.

## 진행 단계
- [x] P 클레임 · 코드 읽기 · 베이스라인 그린 확인
- [x] A5 · A3 · A4 · B1 · B12 코드 + 어드민 갈래 요청 4건(잠긴 메타 · include_deleted · 503 code · 문서 명시)
- [x] 테스트(뮤테이션 표적 명시) 12개 신설 · 기존 3개 갱신
- [x] 계약 문서 v2.28 + 직렬화 규약 줄 + v2.11 절 현행화(L11)
- [x] 검증(build · vet · test · -race · 뮤테이션 24건)

## 변경 파일
| 파일 | 변경 |
|---|---|
| `backend/internal/api/service.go` | JoinApprove name·phone 비움 / ListMembers·UpdateMember flags 정규화 / hydratePassRemaining·stampPassStatus holds 정규화 / CreatePayment·ListPayments installments 정규화 / DeleteBodyPhoto 스코프만 / ListBodyPhotos → `BodyPhotoListing`(잠긴 메타 · include_deleted) / NewService 기본 purger |
| `backend/internal/api/service_wire_normalize.go` **신설** | nil→[] 헬퍼 3개 + 왜(읽기 쪽 바닥 · body_poses 제외) |
| `backend/internal/api/service_consult.go` | DoneConsultRequest note 비움 |
| `backend/internal/api/provision.go` | `devMediaPurger` → `unconfiguredPurger{reason}` · `ErrMediaListUnavailable` · 강등 4곳 reason |
| `backend/internal/api/util.go` | `errBodyWithCode` · `codeRouteNotFound` · `codeMediaNotConfigured` · 503 매핑 분리 |
| `backend/internal/api/router.go` | 라우터 404에 code |
| `backend/internal/api/handlers_media.go` | ListBodyPhotos: include_deleted 파싱 · Locked면 Meta 응답 |
| `backend/internal/api/service_wire_null_test.go` **신설** | 와이어 테스트 9개(installments/flags/holds null 부재 · Firestore 모양 래퍼 · 404 code · 503 code · 메타 키 집합 · 잠긴 목록 · include_deleted) |
| `backend/internal/api/service_join_lobby_test.go` | `TestJoinApproveClearsNameAndPhone` |
| `backend/internal/api/service_consult_test.go` | `TestDoneConsultRequestClearsNote` |
| `backend/internal/api/service_body_photo_delete_test.go` | `TestDeleteScope` 동의 서브테스트 → 스코프 서브테스트 / `TestDeleteBodyPhotoAllowedAfterConsentWithdrawal` / 호출부 시그니처 |
| `backend/internal/api/service_body_photo_reconcile_test.go` | `TestReconcileRefusesWhenPurgerUnconfigured` · `TestUnconfiguredPurgerDoesNotBlockWithdrawal` · 빈 버킷 테스트 주석 |
| `docs/API계약_v1.md` | v2.28 절 신설 · 직렬화 규약 줄(installments + 읽기 정규화) · v2.11 절 개정 2곳(미연결 404 → v2.27 200 · 재시도 404 → 200 멱등) |

## 검증
- `go build ./...` · `go vet ./...` · `go test ./...` · `go test -race ./...` — 4패키지 전건 그린(베이스라인 대비 회귀 0)
- 스토어 인터페이스·구현 무변경 → 에뮬레이터 적합성 신규 케이스 없음
- 뮤테이션 24건 — 23 KILLED · 1 등가(제거):

| # | 지운 가드 | 죽인 테스트 | 결과 |
|---|---|---|---|
| M1 | JoinApprove `jr.Name/Phone = ""` 제거 | TestJoinApproveClearsNameAndPhone | KILLED |
| M2 | 비우기를 SaveMember 앞으로 이동 | 〃(회원 레코드 이름 검사) | KILLED |
| M3 | DoneConsultRequest `cr.Note = ""` 제거 | TestDoneConsultRequestClearsNote | KILLED |
| M4 | CreatePayment 쓰기 정규화 제거 | TestPaymentInstallmentsNeverNullOnWire | KILLED |
| M5 | ListPayments 읽기 정규화 제거 | 〃(레거시 null 문서) | KILLED |
| M6 | PayInstallment 읽기 정규화 제거 | — | **등가**(인덱스 가드가 먼저 400) → 코드 제거 |
| M7 | ListMembers self 분기 flags 정규화 제거 | TestMemberFlagsNeverNullOnWire | KILLED |
| M8 | ListMembers owner 목록 flags 정규화 제거 | 〃 | KILLED |
| M9 | UpdateMember 저장 전 flags 정규화 제거 | 〃(치유 검사) | KILLED |
| M10 | hydratePassRemaining holds 정규화 제거 | TestPassHoldsNeverNullOnWire | KILLED |
| M11 | stampPassStatus holds 정규화 제거 | Memory로는 **생존** → Firestore 모양 래퍼 `TestRefundResponseHoldsNeverNullWithFirestoreShapedStore` | KILLED |
| M12 | `ListObjects` → `nil, nil` 복원 | TestReconcileRefusesWhenPurgerUnconfigured · …Is503OnWire | KILLED |
| M13 | 503 매핑 제거(500으로) | TestReconcileUnconfiguredIs503OnWire | KILLED |
| M14 | `DeleteObjects`를 에러로 | TestUnconfiguredPurgerDoesNotBlockWithdrawal | KILLED |
| M15 | DeleteBodyPhoto 동의 게이트 복원 | TestDeleteBodyPhotoAllowedAfterConsentWithdrawal | KILLED |
| M16 | 라우터 404 code 제거 | TestRouterNotFoundCarriesCode | KILLED |
| M17 | 리소스 404에 code 부착 | 〃(리소스 404 무변경 검사) | KILLED |
| M18 | BodyPhotoMeta에 storage_path 추가 | TestBodyPhotoMetaWireKeys · …LockedIsMetaOnlyOnWire | KILLED |
| M19 | 잠긴 분기 제거(403 복원) | …LockedIsMetaOnlyOnWire · …AllowedAfterConsentWithdrawal | KILLED |
| M20 | 핸들러가 Locked에도 Full 응답 | …LockedIsMetaOnlyOnWire | KILLED |
| M21 | include_deleted 회원 가드 제거 | TestBodyPhotoIncludeDeletedIsStaffOnly | KILLED |
| M22 | 삭제분 필터 항상 거름 | 〃 | KILLED |
| M23 | 삭제분 필터 항상 포함 | 〃 | KILLED |
| M24 | 503 code 제거 | TestReconcileUnconfiguredIs503OnWire | KILLED |

## 후속 작업
1. **과거 승인분 마이그레이션(람 결정)** — 이미 `approved`인 join_requests의 name·phone은 이번 수리로
   비워지지 않는다. Firestore 콘솔/스크립트 1회성.
2. 어드민 갈래: `code === "route_not_found"` 분기 · `media_not_configured` 503 안내 · 잠긴 목록(BodyPhotoMeta)
   렌더 · `include_deleted` 휴지통 — 서버는 준비됨(계약 v2.28).
3. 업로드 503(`ErrUploadUnavailable`)에 code 부착 여부 — 어드민이 원하면 추가적 변경.
4. 법정 문서(L3/L4/L5)는 P56 소유 — 이번 서버 변경으로 *"처리 완료 시 파기"* · *"철회 후 삭제 요청"*
   두 문장이 참이 됐다는 사실을 문서 담당이 반영할 것.

## 참조
- P56(감사 원본) · P53(파기·보존 판정) · P51(업로드 경계 503 선례) · P55(v2.27 대기실) · P58(어드민 갈래)
