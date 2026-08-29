---
id: P22
title: 회원탈퇴(인앱 계정 삭제) — 파기·보존 경계 확정 + 3계층 구현
status: 완료
domain: cross
created: 2026-08-25
completed: 2026-08-25
---

# P22 — 회원탈퇴(인앱 계정 삭제)

## 목표

**서버에 삭제 경로가 단 하나도 없었다.** 58개 라우트 중 DELETE는 `bookings`·`recurrings`·
`inbody` 셋뿐이고 회원 자신을 지우는 경로는 없었다. P21 껍데기 감사가 이미 최상위 후속으로
지목한 "스토어 심사 3종(약관·처리방침·계정삭제)" 중 마지막 항목이다.

Apple App Store Review Guideline **5.1.1(v)** — 계정 생성을 지원하는 앱은 **앱 안에서**
계정 삭제를 제공해야 한다. 고객센터 안내나 웹 링크로 대체할 수 없다. 같은 조항이
"법적 목적으로 특정 정보를 보관해야 한다면 그 필요를 고객에게 **구체적으로 고지**하고
나머지는 삭제하라"고 예외를 명시하는데, 이 예외의 존재가 이번 설계의 형태를 결정했다.

## 결정 사항

### 1. 하드 삭제는 **오답**이다 — 파기와 보존의 경계를 긋는다

서로 반대 방향으로 당기는 두 개의 법적 의무가 동시에 걸린다.

| 축 | 근거 | 요구 |
|---|---|---|
| 파기 | 개인정보보호법 §21① — 처리 목적 달성·보유기간 경과 시 **지체 없이 파기** | 지워라 |
| 보존 | 전자상거래법 §6 + 시행령 §6① — **계약·청약철회 5년 / 대금결제·재화공급 5년** | 남겨라 |

두 조문은 충돌하지 않는다. 개인정보보호법 §21① **단서**가 "다른 법령에 따라 보존하여야
하는 경우에는 그러하지 아니하다"이고, §21③은 그 경우 **다른 개인정보와 분리하여 저장·관리**
하라고 정한다. 전자상거래법 §6②는 한 걸음 더 나가 "소비자가 개인정보 이용 동의를 철회하는
경우에도" 거래기록과 그에 관련된 식별정보를 보존할 수 있다고 **허용**한다.

즉 법은 "전부 지워라"도 "전부 남겨라"도 아니라 **경계를 그으라**고 한다. 우리가 그은 선:

```
파기   = 사람을 가리키는 것(이름·전화번호·진입경로·부상 메모)
       + 목적이 끝난 건강 기록(체형사진·인바디·수업기록·홈워크 체크)
       + 다시 로그인할 수 있게 하는 것(UserIndex·Firebase 계정)
보존   = 돈이 오간 사실(Pass·Payment·Contract·Ledger·과거 Booking)
       단, 위 파기로 이름·번호가 사라져 **member_id라는 가명만 남은 상태**로
```

전자상거래법 §6②가 허용하는 "성명 보존"을 **일부러 쓰지 않았다.** 허용은 의무가 아니고,
분쟁이 실제로 오면 회원이 자기 번호·이름을 들고 오지 우리가 먼저 대조하지 않는다. 지켜야 할
것은 "그 거래가 있었다"는 사실(금액·회차·날짜·계약 상태)이고 그건 이름 없이도 완전하다.
남길 이유가 없는 식별자를 남기면 그건 §21①이 말하는 **불필요해진 개인정보**다.

### 2. 원장(Ledger) 행은 **지우지 않는다** — 지울 수 없다

`Ledger`는 append-only이고 잔여 세션의 **유일한 출처**다(`domain.Sum` — 불변식2, P3).
행 하나를 지우면 그 패스의 잔여가 조용히 틀어지고, 이미 확정된 환불 정산액(`SettleRefund`가
`usedFromLedger`로 사용 회차를 파생한다)과 통계(`revenueByMonth`)가 함께 어긋난다.

v2.0이 스태프에 대해 이미 같은 결론을 내렸다 — *"원장은 append-only이고 잔여 세션의 유일한
출처다 — 행위자 uid를 지울 수 없다."* 회원 쪽도 같다. **가명화가 정답이고 삭제는 오답이다.**
`Ledger.member_id`는 그대로 두고, 그것이 가리키는 `Member` 문서에서 이름·번호를 파기해
포인터의 끝을 비운다. 행은 온전하고, 그 행이 누구인지를 아는 경로만 끊긴다.

### 3. 민감정보(건강)는 보존 대상이 **아니다** — 실제로 지운다

체형사진·인바디는 개인정보보호법 §23의 건강 관련 정보다. 전자상거래법이 보존하라는
"계약·결제 기록"이 아니므로 §21① 단서의 예외를 타지 못한다 → **파기 대상**이다.

여기서 v2.9가 남긴 갭이 정면으로 걸렸다:

> `storage.rules`의 `allow delete: if false` + 서버 삭제 API 부재로 **동의 철회·탈퇴 시
> 파기 수단이 0**이다. (계약 v2.9)

Firestore 메타(`bodyPhotos/{id}`)만 지우면 **실제 사진 바이트는 버킷에 영원히 남는다.**
그 상태로 탈퇴 화면에 "체형사진을 삭제합니다"라고 쓰면 화면이 거짓말을 한다 — 이 저장소가
P14·P15에서 두 번 고쳤던 바로 그 종류의 결함이다.

→ **Admin SDK로 서버가 지운다.** Storage 보안 규칙은 **클라이언트 SDK에만** 적용되고
Admin SDK는 규칙을 지나지 않는다. `allow delete: if false`는 **그대로 두고**(클라이언트가
파일만 지워 메타를 고아로 만드는 것을 막는 규칙이다) 서버가 메타와 파일을 짝으로 지운다 —
규칙 주석이 원래 말하던 *"정리는 서버 몫"*이 이제 실제로 존재한다. `storage.rules` 무변경
(교차 서비스 IAM·평가당 2문서 상한 영역을 통째로 회피 — v2.9와 같은 전략).

`UserProvisioner`와 **완전히 같은 패턴**으로 `MediaPurger` 인터페이스를 두어 SDK 호출을
경계 뒤에 숨겼다(dev = no-op, Firebase = Admin SDK). 테스트·로컬이 네트워크 없이 돈다.

### 4. Firebase 계정은 **비활성화가 아니라 삭제**한다

v2.0 퇴사는 `DisableUser`(Disabled + RevokeRefreshTokens)를 쓴다. 퇴사자는 복직할 수 있고
계정이 남아야 이력이 이어지기 때문이다. **탈퇴는 다르다**:

- Identity Platform 계정에는 **전화번호가 그대로 들어 있다.** 남기면 파기가 아니다.
- 계정이 살아 있으면 같은 번호로 다시 로그인해 같은 uid를 받는다 — `UserIndex`를 지워도
  사용자 입장에서 "탈퇴가 안 된 것"으로 보인다.

→ `DeleteUser`를 `UserProvisioner`에 추가. 계정이 없으면 성공으로 본다(`DisableUser`가 이미
쓰는 관용 + 재시도 멱등).

### 5. 탈퇴를 **막지 않는다** — 잔여 회차가 있어도

"잔여 회차가 남았으면 409로 막고 환불부터 받게 하라"를 검토했고 **기각**했다.

- Guideline 5.1.1(v)는 사업상 상태를 이유로 앱 안의 삭제를 막는 것을 예외로 인정하지 않는다.
  "고객센터에 연락하세요"로 끝나는 플로우는 실제 리젝 사유다.
- 막을 실익도 없다. 잔여 회차는 **원장에 그대로 보존**되고 `Pass`·`Payment`·`Contract`도
  남는다 — 탈퇴 후에 환불을 요구해도 정산 근거는 전부 살아 있다. 그게 5년 보존의 목적이다.

대신 **고지한다**: 확인 화면이 잔여 회차를 실제 값으로 보여주고 "탈퇴해도 자동 환불되지
않는다"를 명시한다. 서버 응답도 `remaining_sessions`를 실어 완료 안내가 사실을 말하게 한다.
**조회에 실패하면 "확인하지 못했어요"라고 말한다** — 상자를 그냥 빼면 "남은 회차 없음"과
구별되지 않고, 회원은 정산할 게 있다는 사실을 되돌릴 수 없게 된 뒤에 알게 된다(v2.1 3상태 규약).

### 6. 막는 것은 **스태프 계정** 하나다

`owner`/`trainer`가 이 경로를 부르면 403. v1.9의 `guardNotStaff`·v2.0의 락아웃 가드와 동일
계열이다 — 스태프는 회원 레코드가 없어 지울 대상이 없고, 만에 하나 회원으로도 연결된
계정이면 그 사람의 `UserIndex`가 지워져 **센터가 대표를 잃는다**(복구 API 없음).
스태프의 이탈 경로는 대표의 `POST /v1/staff/{uid}/deactivate`로 이미 있다.

### 7. `Member.status = "withdrawn"` — 문서는 남기고 내용을 비운다

문서 자체를 지우지 않는 이유는 v2.0이 `GET /v1/staff`에서 inactive를 계속 반환하기로 한 것과
**같다**: 이름 해석을 잃으면 참조 지점이 원시 ID로 붕괴한다. 어드민의 미수금 표·계약 목록·
매출 집계는 전부 `member_id`로 회원 문서를 조인하는데, 문서가 사라지면 5년간 보존하기로 한
바로 그 기록들이 **누구 것인지도 모르는 채 화면에서 깨진다**.

```
Member.status  "active|dormant" → "active|dormant|withdrawn"
Member.withdrawn_at 신설(RFC3339, 서버 기록, 재시도해도 최초 시각 보존 — 보존기간 기산점)
필드 부재/"" 는 로드 시 active로 승격 — v2.0 Staff.status와 동형(마이그레이션 불요)
탈퇴 후 name = "탈퇴한 회원"(고정 라벨 — 식별자가 아니다) · phone = "" · trainer_id = ""
```

`phone`을 비우는 것이 **이번 설계에서 가장 중요한 한 줄**이다. 남겨두면
`FindMemberByPhone`이 계속 매칭해서, 탈퇴한 사람이 같은 번호로 다시 가입할 때
`join/match`가 **탈퇴 레코드로 되돌려 붙인다** — 탈퇴가 조용히 취소된다. 뮤테이션 검증의
1순위(M1)로 잡았고, 도메인·스토어·API 세 계층에서 동시에 죽는 것을 확인했다.

`trainer_id`를 회수하는 것은 코치의 퇴사(v2.0 선행 조건 ① "담당 회원 없음")를 탈퇴자가
영구히 막지 않게 하려는 것이다. 대신 그 회수가 만드는 **부작용**을 두 곳에서 함께 막았다:
통계의 `unassigned`·`long_absent`와 어드민의 "미배정 N" 칩(거르지 않으면 탈퇴자 전원이
"담당 배정이 필요한 회원"으로 잡혀 대표가 영원히 줄지 않는 할 일을 본다).

### 8. 스토어 동사는 **하나**만 추가했다

`PurgeMemberPersonalData(ctx, centerID, anonymized *domain.Member) (PurgeCounts, error)`

갈래마다 `DeleteBodyPhoto`·`DeleteWorkoutLog`·`DeleteHwCheck`…를 만들면 두 구현에 6개를
쓰게 되고 "무엇을 지우는가"라는 **정책이 스토어로 샌다**(v2.6이 `UpdatePassWithLedger`
하나로 4갈래를 묶은 것과 같은 근거). 정책은 도메인이 정하고(`Member.Anonymized()`),
스토어는 **집행만** 한다.

`DeleteUserIndex(ctx, uid)`는 따로 뒀다 — `users/{uid}`는 센터 밖 최상위 컬렉션이다.
**없는 uid도 성공**으로 정의했다(`DeleteInbody`의 "없으면 404"와 의도적으로 다르다): 탈퇴
절차의 마지막 단계라 재시도가 404에 막히면 인덱스가 영구히 남는다.

### 9. 실행 순서가 곧 재시도 가능성이다

```
① 체형사진 원본 파일(Storage)  ─┐ 외부 시스템. 실패해도 DB가 그대로라
② Firebase 계정 삭제            ─┘ **같은 ID 토큰으로 재시도**된다(둘 다 멱등)
③ 미래 confirmed 예약 무차감 취소  (CancelAtomic — 슬롯 사본까지 비운다. 페널티 원장 없음)
④ 가명화 + 건강·이용 기록 파기     (기록 먼저, 회원 문서 마지막)
⑤ UserIndex 삭제                 (호출자의 권한 자체를 없애므로 반드시 마지막)
```

메타보다 **파일을 먼저** 지운다: 반대로 하면 경로를 아는 유일한 문서가 먼저 사라져 민감정보
원본이 버킷에 영영 남고, 그 잔존은 **어느 화면에도 드러나지 않아 발견조차 불가능**하다.
`VerifyIDToken`은 계정 삭제를 확인하지 않아 토큰이 최대 1시간 유효하다(v2.0에 이미 적힌
사실) — ②가 앞에 있어도 ④⑤의 재시도가 가능한 이유다.

④의 내부 순서도 같은 원리다: 기록을 먼저 지우고 회원 문서를 나중에 쓰면 중간 실패가
"이름이 아직 남아 있는" **눈에 보이는 상태**로 멈춘다. 반대였다면 "탈퇴한 것처럼 보이는데
민감정보는 남아 있는" 보이지 않는 상태가 된다.

## 진행 단계

- [x] 계약·아키텍처 정독(API계약 v1~v2.10, domain/store/api 3층)
- [x] 파기·보존 경계 설계 + 근거 문서화(§결정 사항)
- [x] 도메인: `Member.Anonymized()` · `MemberStatusWithdrawn` · `WithdrawnAt` (테스트 선작성)
- [x] 스토어: `PurgeMemberPersonalData` · `DeleteUserIndex` (Memory + Firestore) + conformance 2건
- [x] 경계: `MediaPurger`(Storage 파일 파기) · `UserProvisioner.DeleteUser`
- [x] API: `DELETE /v1/me` + 탈퇴 회원 후속 차단 5곳(발급·예약·홈워크·회원수정·가입재연결) + 통계
- [x] 앱: 마이 탭 진입 + 확인 화면(파기/보존 고지·체크박스·다이얼로그) + 로그아웃
- [x] 어드민: 탈퇴 배지·기본 목록 제외·전용 칩·상세 고지·수정 차단
- [x] 계약 문서 v2.11 추가
- [x] 뮤테이션 검증(백엔드 14/14 · 앱 9/10 + 1 equivalent) + 3계층 게이트

## 변경 파일

### backend
```
internal/domain/member.go              MemberStatusWithdrawn · WithdrawnMemberName · WithdrawnAt ·
                                       IsWithdrawn() · Anonymized()(파기·보존 경계의 단일 출처)
internal/domain/withdrawal_test.go     신규 — 가명화 골든 규칙 필드별 검증 + 멱등성
internal/store/store.go                PurgeCounts · PurgeMemberPersonalData · DeleteUserIndex
internal/store/memory.go               두 동사 구현(락 하나 안에서)
internal/store/firestore.go            두 동사 구현 + deleteWhereMember 헬퍼
internal/store/conformance_test.go     신규 2케이스(파기 6종·이웃 회원 불변·원장 보존·재가입 차단 /
                                       DeleteUserIndex 멱등)
internal/api/service_account.go        신규 — DeleteMyAccount · retainedForMember ·
                                       cancelFutureBookingsForWithdrawal · guardMemberNotWithdrawn
internal/api/service_account_test.go   신규 — 파기·보존·차단·순서·와이어 계약
internal/api/provision.go              UserProvisioner.DeleteUser · MediaPurger(dev/Firebase)
internal/api/auth.go                   Authenticator.fbApp 보관(Storage 클라이언트 파생)
internal/api/service.go                Service.media · WithMediaPurger · 탈퇴 가드 4곳
internal/api/service_stats.go          탈퇴 회원 KPI 제외
internal/api/handlers_me.go            DeleteMe 핸들러
internal/api/router.go                 DELETE /v1/me
internal/config/config.go              StorageBucket(STORAGE_BUCKET)
cmd/server/main.go                     MediaPurger 주입 + 기동 문서
go.mod                                 cloud.google.com/go/storage를 indirect → direct 승격
```

### app
```
lib/features/my/domain/account_deletion.dart          신규 — 고지 문구 단일 출처 + 응답 모델
lib/features/my/domain/my_repository.dart             deleteAccount()
lib/features/my/data/my_remote_data_source.dart       DELETE /v1/me
lib/features/my/data/my_repository_impl.dart          구현(파싱은 던지지 않는다)
lib/features/my/presentation/my_view_model.dart       deleteAccount()(성공해도 refresh 안 함)
lib/features/my/presentation/account_deletion_screen.dart  신규 — 확인 화면
lib/features/my/presentation/my_screen.dart           마이 탭 진입 행(danger)
test/features/my/presentation/account_deletion_test.dart        신규 14건
test/features/my/presentation/account_deletion_entry_test.dart  신규 3건
test/features/my/data/account_deletion_api_test.dart            신규 4건
test/features/my/presentation/{consent_save_guard,widgets/*}    기존 fake 4곳에 메서드 추가
```

### admin
```
src/lib/types.ts          MemberStatus에 withdrawn · Member.withdrawn_at
src/features/Members.tsx  MEMBER_STATUS_LABEL/TONE(탈퇴가 "휴면"으로 표시되던 삼항 제거) ·
                          기본 목록 제외 + "탈퇴 N" 칩 · 미배정 카운트 보정 ·
                          WithdrawnNotice(보존 사유·기간 고지) · 수정 버튼 차단
```

### docs
```
docs/API계약_v1.md        v2.11 절 추가(엔드포인트·파기/보존 경계·후속 차단·실행 순서·남은 갭)
```

## 검증

### 게이트
| 계층 | 명령 | 결과 |
|---|---|---|
| backend | `go build ./... && go test ./...` | **green** · 333 PASS |
| app | `flutter analyze` | **0 issues** |
| app | `flutter test` | **848 passed** (착수 시 825 → +23) |
| admin | `tsc -p tsconfig.json && vite build` | **green** |

### 뮤테이션 검증 — backend 14/14 kill

| # | 되돌린 가드 | 죽은 테스트 |
|---|---|---|
| M1 | `Anonymized`가 phone 보존 | domain 2 · store conformance · api 2 |
| M2 | `Anonymized`가 실명 보존 | domain 2 · store conformance · api 1 |
| M3 | 스태프 403 제거 | `RejectsStaff` · 와이어 계약 |
| M4 | Memory 퍼지가 체형사진 건너뜀 | store conformance · api 1 |
| M5 | Storage 원본 파기 호출 제거 | `PurgesAndRetains` |
| M6 | Firebase 계정 삭제 제거 | `PurgesAndRetains` · 외부 실패 2 |
| M7 | UserIndex 삭제 제거 | `PurgesAndRetains` · 와이어 계약 |
| M8 | 단계 순서 뒤집기(외부→DB 이후로) | 외부 실패 2 |
| M9 | 미래 예약 무차감 취소 제거 | `PurgesAndRetains` |
| M10 | 통계 탈퇴 제외 제거 | `ExcludedFromStats` |
| M11 | `UpdateMember` 되살리기 차단 제거 | `BlocksNewWrites/정보수정` |
| M12 | `CreatePass` 차단 제거 | `BlocksNewWrites/발급` |
| M13 | Home Work 배정 차단 제거 | `BlocksNewWrites/HomeWork` |
| M14 | `DeleteUserIndex` 멱등성 제거 | store conformance |

### 뮤테이션 검증 — app 9/10 kill + 1 equivalent

A1 최종 확인 다이얼로그 제거 · A2 체크박스 게이트 제거 · A4 세션정리·로그인 이동 제거 ·
A5 만료·환불 회원권 잔여 합산 · A6 보존 사유 제거 · A7 응답 파싱이 던짐 ·
A8 마이 탭 진입점 제거 · A9 danger 색 제거 · A10 DELETE→POST — 전부 kill.

**A3(`_submit`의 이중 잠금 제거)은 equivalent**로 판정했다: 버튼 게이트(A2)가 살아 있는 한
어떤 UI 경로로도 `_acknowledged == false` 상태의 `_submit`에 도달할 수 없다. 이 저장소의
파괴적 동작 규약("비활성 버튼만 믿지 않는다")에 따라 코드는 유지한다.

A2는 처음에 **survive** 했다 — "탭해도 아무 일이 없다"만 보는 테스트는 *버튼이 활성인데
안쪽 재확인이 막아주는 상태*와 구별하지 못했다. 버튼의 `onPressed == null`을 직접 보는
단언을 더해 kill로 바꿨고, 반대편(체크 후 활성화)도 함께 고정했다.

### 실측으로 확인한 것
- `DELETE /v1/me` 두 번째 호출은 **404**(UserIndex가 사라져 member_id를 잃는다) — "이미
  지웠다"가 200으로 다시 보고되지 않는다. 라우터 통과 테스트로 고정.
- 탈퇴 후 `FindMemberByPhone("010-1234-5678")`이 **ErrNotFound** — 재가입이 탈퇴 레코드로
  되돌아가지 않는다(도메인·스토어·API 3계층에서 각각 확인).
- 탈퇴 후 원장 건수·합계 불변(20회 그대로), Pass/Payment/Contract 각 1건 보존.

## 후속 작업

1. **[사람이 해야 함] IAM**: Cloud Run 서비스 계정에 `rize-218c1.firebasestorage.app` 버킷의
   `storage.objects.delete` 권한 부여(`roles/storage.objectAdmin` 또는 커스텀). 이게 없으면
   탈퇴는 성공하는데 **체형사진 원본만 조용히 남는다** — v2.9의 교차 서비스 IAM 사고와
   같은 모양(증상이 "원인 표시 없는 실패")이다.
2. **[사람이 해야 함] 배포 환경변수**: Cloud Run에 `STORAGE_BUCKET=rize-218c1.firebasestorage.app`
   추가. 미설정이면 파일 파기가 no-op이 되고 기동 로그에 경고만 남는다(기동은 막지 않는다).
3. **배포 순서**: `decodeJSON`이 `DisallowUnknownFields`이고 앱이 `DELETE /v1/me`를 새로
   부르므로 **서버 먼저, 앱 나중**(v2.9와 같은 규약).
4. **스토어 심사 3종 중 남은 둘**: 이용약관·개인정보처리방침 화면이 여전히 없다(P21 지목).
   특히 처리방침은 이번에 확정한 파기·보존 경계를 그대로 옮겨 적으면 되므로 지금이 적기다.
5. **보존기간 만료 후 자동 파기 없음**: `withdrawn_at + 5년`이 지난 문서를 지우는 배치가 없다.
   지금은 어드민 상세가 "언제까지 보관"을 계산해 보여주는 데까지다 — 자동 삭제는 되돌릴 수
   없는 쓰기라 운영 신뢰가 쌓인 뒤에 붙인다.
6. **탈퇴 사유 미수집**: 리텐션 분석에 유용하지만 파기 직전에 목적 외 정보를 새로 받는
   모순을 피했다. 넣는다면 회원과 분리된 익명 집계여야 한다.
7. **`account-deletion.html` 갱신 필요**(다른 갈래 소유 파일): 웹 요청 폼 + 영업일 3일 경로만
   안내하고 있다. 앱 내 즉시 삭제 경로가 생겼으므로 "앱 → 마이 → 회원탈퇴"를 1순위로 올려야
   문서와 실제가 일치한다. 아래 §갈래 정합 참고.
8. **의존성 버전 메모**: `cloud.google.com/go/storage`를 indirect → direct로 승격했다.
   버전 `v1.62.1`은 기존 모듈 그래프(firestore·firebase-admin)가 정한 값을 그대로 쓴 것이고
   새로 고른 것이 아니다. 2026-08 기준 latest stable은 **v1.65.0**(proxy.golang.org 확인) —
   올리려면 그래프 전체 `go mod tidy`가 필요해 이번 범위에서 제외했다.

## 갈래 정합 — P22-legal-documents와의 교차검증

같은 P22 스윕("스토어 심사 3종")의 다른 갈래가 법률 문서 4종을 병렬로 작성했고, 그쪽
`admin/public/legal/privacy.html`·`account-deletion.html`이 **독립적으로 같은 경계**에 도달했다.
서로 참조하지 않고 나온 결과라 교차검증으로서 값이 있다:

| 문서가 약속한 것 | 이 구현이 하는 것 |
|---|---|
| 계약·청약철회 기록 **5년**(전자상거래법 §6·시행령 §6) | `Pass`·`Contract` 보존 |
| 대금결제·재화공급 기록 **5년**(동 법 §6) | `Payment`·`Ledger` 보존 |
| 체성분·체형사진·건강 메모 = 민감정보 → 파기 | `Inbody`·`BodyPhoto`·`WorkoutLog`·`Flags` 삭제 |
| *"계정을 잠그는 것이 아니라 실제로 지웁니다"* | Firebase 계정 **삭제**(Disable 아님) + UserIndex 삭제 |
| *"체형 분석 사진 전부 — 저장소의 이미지 파일과 그 기록"* | `MediaPurger`가 Storage 원본까지 파기 |

문서 갈래가 후속 ①로 올린 *"계정 삭제 — 앱 내 경로 부재. Apple 5.1.1(v)·Play 모두 앱 안에서
시작할 수 있어야 한다"*와 ②*"체형사진 파기 수단 0"*이 **이 작업으로 둘 다 닫혔다.**

→ 다만 `account-deletion.html`은 현재 **웹 요청 폼 + 영업일 3일** 경로만 안내한다(Play가 웹 URL을
강제해 만든 페이지다). 앱 내 경로가 생겼으므로 그 페이지에 "앱 → 마이 → 회원탈퇴로 즉시 처리
가능"을 추가해야 문서와 실제가 일치한다. **그 파일은 다른 갈래 소유라 이번에 건드리지 않았다**
(후속 작업 8번).

## 참조

- `docs/API계약_v1.md` — v2.11 절(이 작업의 계약)
- `work_log/P22-legal-documents.md` — 같은 스윕의 문서 갈래(위 교차검증 표)
- `work_log/P21-hollow-feature-audit.md` — 스토어 심사 3종 부재를 최상위 후속으로 지목
- `work_log/P08-staff-lifecycle.md` — "하드 삭제를 하지 않는 이유"(v2.0)의 선례
- `work_log/P18-inbody-upload-backend.md` — 되돌릴 수단 없는 쓰기를 여는 것에 대한 선례
- Apple App Store Review Guideline 5.1.1(v) — 인앱 계정 삭제 요구와 법적 보관 예외
