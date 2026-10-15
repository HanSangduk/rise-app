---
id: P73
title: 3계층 전면 재감사 — 9팀 병렬 조사(2라운드) → 직접 교차검증 → 수리 → 적대적 리뷰 4라운드 · 계약 v2.37
status: 완료
domain: cross
created: 2026-09-25
completed: 2026-09-26
---

# P73 — "구멍·버그·편의성을 찾아 고치고, 더 고칠 게 없을 때까지 반복"

## 목표 (람 요청)
프로젝트 전체(백엔드 Go · 어드민 React · 회원 앱 Flutter · 계약 문서 · 규칙/설정 · 법정 문서)를
분석해 구멍·버그·사용자 편의성 개선점을 찾고, **교차 검증 · 검토 · 자문자답**을 거쳐 고친 뒤,
같은 과정을 **더 이상 수정할 부분이 없을 때까지 반복**한다.

## 착수 시점 구조 (실측)
- 맥 `ptdesk` 스냅샷(브랜치 `feat/contract-esign-admin-usability`, 미커밋 없음)을 클라우드로 복사해
  수정본(`ptdesk`)과 원본(`orig`)을 나란히 두고 diff로 관리. **파일은 맥에 63개 반영**(md5 전수 대조 일치).
- 계약 문서 v2.36까지 누적, work_log P01~P72. 이미 "보류/후속"으로 기록된 것이 많아 조사팀에
  **"기존 후속 재확인: Pxx-n"** 표기를 강제했다(새 발견처럼 부풀리지 않기 위해).
- 도구 제약(중요): 코워크 VM엔 go·flutter가 없고 클라우드는 모듈·SDK 다운로드가 차단돼
  **go test · flutter test를 이 세션 안에서 돌릴 수 없었다.** 대신 ① `gofmt -e` 구문 검사(Go 15개 파일),
  ② 어드민 `tsc --noEmit`(VM에서 실행 · 통과), ③ Dart는 괄호 밸런스 + 식별자·시그니처 전수 grep,
  ④ 사람 눈 적대적 리뷰 3라운드로 대신했고, 실제 실행은 맥의 `docs/temp/p73_verify.sh`로 넘긴다(아래 검증).

## 자 (스킬 §0 — 고치기 전에 만든 것)
| 자 | 착수 | 완료 |
|---|---|---|
| `flutter analyze` | 0 issues (P72) | **0 issues** |
| `flutter test` | **1497 pass** (P72) | **1532 pass** (+35 · 파일 9 신설 + 기존 7파일 추가 · 회귀 0) |
| `go vet` · `go test ./...` · `-race` | 그린 (P70·P71) | **그린**(api·config·domain·store 4패키지 · race 통과) |
| 어드민 `tsc --noEmit` | 통과 | 통과 (VM에서 재실행) |
| 어드민 `npm run build` | 그린 (P70) | **그린** |
| 시간대 민감 시험 `TZ=America/New_York` | 규약만 있음(주석) | **29 pass**(검증 스크립트 단계로 고정) |
| 변이 검사 | — | **14/14 KILL**(12건 + 하위 2건, 전부 단언 실패로 죽음 · 원복 md5 확인) |
| 맥 반영 파일 md5 | — | 63/63 일치 |

## 조사 (읽기 전용 7팀 · 파일:줄 근거 · [근거]/[추측] 분리)
B1 백엔드 인가·스코프·IDOR·Memory↔Firestore 동등성 · B2 백엔드 상태머신(패스·예약·결제·환불·통계) ·
A1 어드민 계약 정합·캐시 갱신 · A2 어드민 사용자 여정 UX · P1 앱 데이터·상태·세션 ·
P2 앱 화면 UX·접근성·문구 · X1 3계층 교차(계약·규칙·설정·법정 문서). **총 40건**(CRITICAL 1 · HIGH 5 ·
MEDIUM 18 · LOW 16). 결과: **수리 32 · 명시 보류 8 · 오탐 0**(보고서 ↔ diff 1:1 대조표
`ptdesk_audit/finding_map.md`, 세션 산출물).

**교차검증 — 조사 결과를 그대로 믿지 않았다.** 확정 전 핵심 주장을 직접 열어 확인:
`superadminAllowedPath` 부분일치 · `CreateBooking`/`CreateRecurring`의 `err == nil` 가드 ·
`RefundPass`가 금액을 어디에도 안 남김 · `staffMap` keepAlive가 세션을 안 봄 · 마이 탭 동의와
`myProfileProvider` 이중 상태 · `DateTime.parse`(throw) 단독 사용처 · pbxproj 리터럴 재붕괴 ·
법정 문서 "체크인·예약 기록 삭제" vs 실제 5년 보존 → **전부 사실**. [추측] 태그가 붙었던 10건도
전부 실체가 있었다(9 수리 · 1 보류).

## 결정 사항

### C1 (앱 CRITICAL) 동의를 켰는데 셔터는 계속 "동의 필요"였다
마이 탭의 민감정보 동의 토글은 `myViewModel`의 자기 상태만 갱신했고, 촬영 화면의 셔터 게이트는
**다른 provider**(`myProfileProvider`)를 봤다. 두 provider가 따로 놀아 동의를 켠 직후 촬영 탭으로
가면 여전히 막혔고, 앱을 다시 켜야 풀렸다.
→ `updateConsent` 성공 시 `ref.invalidate(myProfileProvider)` + `refresh()`. 기록 탭 당겨서 새로고침도
`myProfileProvider`를 함께 무효화. 시험은 **진짜 배선**으로 잰다(`cross_tab_invalidate_test` —
`_CountingMyRepository`가 `_CountingMemberApi.updateConsent`를 실제로 부르고, 셔터 게이트가 읽는
provider가 재조회되는지 카운트로 확인. 첫 초안은 가짜끼리 연결이 안 돼 있어 **R2 리뷰가 잡았다**, 아래).

### C2 (앱 HIGH) 로그아웃해도 이전 센터 코치 명단이 15분 살아 있었다
`staffMap`은 keepAlive + 15분 TTL 캐시인데 세션을 보지 않았다. 로그아웃 → 다른 계정 로그인이면
다음 계정이 **이전 센터의 코치 명단**을 봤다(담당 코치 이름·아바타·프로필 시트).
→ `ref.keepAlive()` **앞에서** `ref.watch(sessionProvider.select((s) => s?.memberId))` — 신원이
바뀌면 재빌드, 같은 신원 안의 세션 객체 교체(이름만 갱신 등)는 `select`가 걸러 재조회하지 않는다.
시험 3건(로그아웃 후 재로그인 · 구독 유지 중 계정 교체 · 같은 신원 세션 교체).

### C3 (앱 HIGH) 예약·취소 뒤 마이 탭이 옛 잔여 횟수를 보여줬다
예약 생성·취소 성공이 홈·예약 탭만 무효화했다. → `myViewModelProvider`도 무효화(잔여·이용 내역).

### C4 (백엔드 · 돈) 환불액이 DB 어디에도 남지 않았다 — 계약 v2.37 ①
`RefundPass`는 정산(`SettleRefund`)을 계산해 **응답에만** 싣고 패스에는 `status=refunded`만 썼다.
어드민이 나중에 "얼마를 돌려줬는지" 볼 수 없었고, 분쟁 시 근거가 없었다.
→ `Pass.RefundedAmount *int` · `RefundedAt *time.Time`(둘 다 `omitempty`). 트랜잭션 mutate 클로저 안에서
**원장을 다시 센 값**으로 정산해 기록하고(재시도 사이에 완료 처리가 끼어들 수 있다), 응답 quote도
그 값으로 통일. 포인터인 이유: **0원 환불도 "환불 전"과 구별돼야 한다**(`int`+omitempty면 0원이
키째 사라진다 — R1 리뷰 지적). 어드민 회원권 카드에 `환불액 N원 · YYYY-MM-DD 마감`.

### C5 (백엔드) superadmin 관문이 부분일치였다
`superadminAllowedPath`가 접두사만 봐 `/v1/admin`·`/v1/me`의 **부분일치 경로**가 관문을 통과한 뒤
서비스 가드에서 500으로 죽었다(403이어야 할 자리). → `/v1/me` 정확일치 + `/v1/admin/` 접두사만.
경계 시험에 `id=me`·`admin-x` 같은 꼬인 경로 추가.

### C6 (백엔드) 스토어 순단이 예약 거부 규칙을 껐다 — fail-open 2곳
`CreateBooking`·`CreateRecurring`이 담당 트레이너를 `if st, err := GetStaff(...); err == nil { 퇴사·휴무 검사 }`로
읽었다. Firestore가 잠깐 실패하면 검사가 **조용히 건너뛰어** 퇴사자·휴무일에 예약이 잡혔다.
→ `ErrNotFound`만 통과(dev 시딩 경로), 다른 오류는 즉시 반환. `CreateRecurring`은 두 번 읽던 것을
한 번으로(휴무일도 같은 읽기에서). `hookStore` 실패 주입 시험 2건(`service_guard_not_silent_test`).

### C7 (백엔드) 탈퇴 회원이 만료 임박·HW 완료율에 남았다
탈퇴(`withdrawn`) 회원의 패스·홈워크가 KPI에 그대로 잡혔다. → `withdrawn` 집합을 한 번 만들어
만료 임박·HW 완료율(센터·트레이너별)에서 제외. **매출·재등록 집계는 건드리지 않는다**(돈은 사실이다).

### C8 (백엔드/어드민) 회원 등록 시 동의 시각을 PC 시계로 저장했다
`CreateMember`가 클라이언트가 보낸 `consent.signed_at`을 그대로 믿었다(`UpdateMember`는 서버가
찍는다). → 서버가 찍는다: 민감정보 동의가 있거나 클라이언트가 시각을 보냈으면 `now`, 둘 다 없으면
`nil`, `revoked_at`은 등록 시 항상 `nil`. 계약 v2.37 ③.

### C9 (백엔드+앱, 한 쌍) 체형사진 날짜 — 서버는 무검증, 앱은 한 건에 전체가 죽었다
서버 `CreateBodyPhoto`가 `date`·`direction`을 검증하지 않았고, 앱 `BodyCheckRepositoryImpl`은
**유일하게** `DateTime.parse`(throw)를 써서 불량 레코드 하나가 `guardApi`에서 Err로 접혀 **수개월치
타임라인 전체**를 "불러오지 못했어요"로 숨겼다(인바디·수업 기록은 이미 tryParse+스킵).
→ 서버: `YYYY-MM-DD` 형식·미래 날짜 거부·direction enum(400, 계약 v2.37 ②). 앱: tryParse + 그 건만
스킵(`body_photo_bad_date_test`는 **실제 RepositoryImpl**을 돌린다).

### C10 (스토어 대칭성) Firestore `checkDocID` 3곳 · Memory `Normalize`
`GetBodyPhoto/SaveBodyPhoto/DeleteBodyPhoto`만 빈 ID 검사가 없었다(빈 ID로 Firestore 경로를 만들면
컬렉션 오류로 500). Memory `GetCenter/ListCenters`는 읽기 시 `Normalize()`를 안 해 빈 status가 그대로
나왔다(Firestore와 불일치). → 양쪽 정렬 + conformance 시험 확장(빈 ID 읽기 3종 · 빈 status→active).

### C11 (어드민) 갱신 누락·잠금 누락·막힌 링크·영문 오류
- 완료·노쇼 처리 뒤 **대시보드 정산이 stale** → `["stats"]` 무효화.
- 뮤테이션 중 모달 닫기(ESC·백드롭·X)가 `JoinRequests` 한 곳만 잠겨 있었다 → **17곳**에 `closeDisabled`
  (Settings 8 · Members 5 · Schedule 3 · Centers 1). 환불 계산기는 **견적 조회 중엔 닫을 수 있게** 남겼다
  (읽기 전용 호출, R3 확인).
- 대시보드 "만료 임박"만 이름 링크가 없어 클릭할 수 없었다 → `NameLink` 3명 + "외 N명".
- 로그인·메일 발송 실패가 영문 Firebase 코드를 그대로 노출 → `firebaseErrorKo.ts`(로그인표·메일표,
  미지 코드는 "메일 서버가 요청을 거절했어요 (코드: …)").
- 예약 그리드가 폰 폭에서 레인이 뭉개짐 → `minmax(72px, 1fr)` + 가로 스크롤.

### C12 (교차) iOS 버전 상수가 세 번째로 pbxproj에 박혔다
`FLUTTER_BUILD_NAME/NUMBER = 1.0.1/9` 리터럴이 pbxproj에 다시 들어가(P60·P67 뒤 3번째) pubspec(`1.0.0+8`)과
갈라졌다 — Xcode에서 손으로 고친 흔적. → 리터럴 제거 + `check_release_target.sh`가 **빌드 시 리터럴을
발견하면 실패**(가짜 pbxproj로 exit 1/0 확인) + **pubspec을 `1.0.1+9`로 올림**(Xcode에 적힌 값 기준 —
람이 다른 번호를 원하면 pubspec만 바꾸면 된다).

### C13 (P65 후속 3 · 앱) 2호점 회원에게 1호점 상호를 보여주던 것
서버는 v2.32부터 `join/match` 응답에 매칭된 **그 회원의 센터** `center`를 실어 왔는데 앱 DTO엔 칸이
없어 버려졌고, 대기실 매칭 카드·로그인 뒤 홈 헤더·마이 탭은 `GET /v1/public/center`(무인증 = **기본
센터 고정**)의 상호를 찍었다. → 데이터 소스가 응답 맵에서 `center.name` 한 칸만 읽어(`JoinMatchPayload`;
freezed 생성물은 건드리지 않는다) 매칭 카드에 싣고, `centerDisplayNameProvider`는 세션이 있으면
`?center=<세션 center_id>`로 묻는다. 형이 이상해도(널·문자열·숫자 이름) 매칭 자체는 살아남는다
(`is Map`/`is String` 판정만 — `as String?` 캐스트는 R3가 지적한 대로 숫자 이름에서 던진다).

### C14 그 밖(앱 UX·접근성 · 문서)
예약 확정·홀딩 재개·동의 저장 성공 스낵바(3곳 무통보 종료) · 사진 삭제 왕복 중 닫기 잠금
(`PopScope` + 드래그 닫기 차단 + `onDeleted`를 await **전에** 캡처해 어떻게 닫혀도 목록 갱신) ·
서명패드 "다시 쓰기" 44dp · 포즈 칩 `Semantics(selected:)`·"촬영 완료"/"지금 찍을 포즈" · 인바디 차트
1.35 배율 실측 시험 · 법정 문서(계정 삭제·개인정보) "체크인·예약 기록 삭제" → 실제 동작(체크인 기록과
**앞으로의** 예약만 삭제, 지난 예약 이력 5년 보존)으로 정정 · `support.html` "자동으로 연결" 잔존 문구 ·
backend README 라우트 54→71 · `.env.example` `INITIAL_STAFF_PASSWORD` · `firebase.json` `/api/v1/public/center`
캐시 헤더 · admin/app README 스테일.

## 2라운드 — 1라운드가 열지 않은 앱 파일 99개(순수 규칙·파서 · 위젯·데이터 계층)
1라운드 보고서의 "읽은 파일 목록"을 소스 트리와 대조해 **한 팀도 열지 않은 파일**을 골라냈다(백엔드·
어드민은 사실상 전수, 앱은 99개가 남아 있었다). P3(도메인 규칙 21파일 + 서버 짝 2) · P4(위젯·데이터
40파일) 두 팀 → 4건(HIGH 1 · MEDIUM 2 · LOW 1) → 직접 확인 → 전부 수리.

### C15 (앱 HIGH) 같은 배정의 Home Work 두 칸을 연달아 체크하면 하나가 서버에서 사라질 수 있었다
`POST /v1/hw-checks`는 형제 done 배열 **전체**를 보내고 서버는 문서를 통째로 교체한다. 항목을 훑듯
연달아 체크하면 두 POST가 서로 다른 배열(`[T,F,F]`·`[T,T,F]`)로 **동시에** 나갔고, 네트워크에서
순서가 뒤집히면 나중에 도착한 옛 배열이 이겨 방금 체크한 칸이 지워졌다 — 둘 다 200이라 롤백도
토스트도 없다(이 뷰모델은 같은 부류의 사고를 조회 실패·자정 경계 두 경우엔 이미 막고 있었다).
→ hwId별로 제출을 **직렬화**(`_hwSubmitTail`): 앞 요청이 끝난 뒤 보내고, 보내는 시점의 **최신 상태**로
배열을 다시 만든다(뒤 토글이 앞 요청에 흡수돼 마지막 배열은 언제나 화면과 같다). 낙관적 UI는 그대로,
실패는 종전대로 그 칸만 역토글. 다른 hwId끼리는 기다리지 않는다. 시험 3건(`Completer` 게이트로
"겹치는 순간"을 만들고 `maxInFlight == 1`을 잰다 — 종전 코드는 이 자리에서 두 건이 떠 있었다).

### C16 (앱 MEDIUM) 셀프 체크인 창이 서버보다 1초 미만 넓었다
`inSeconds` 절삭 — 30분 0.0~0.999초가 "30분"으로 읽혀 서버(`time.Time` 정확 비교)가 이미 400인
시각에 버튼이 켜져 있었다. `inMinutes`(P44)를 초로 "줄인" 것이지 절삭을 없앤 게 아니었다.
→ `Duration` 값 그대로 비교(`diff.abs() <= window`). 경계 시험(±30:00.000 열림 · ±30:00.500 닫힘).

### C17 (앱 MEDIUM) 인바디 삭제 "확인"을 왕복 중 한 번 더 하면 성공한 삭제에 "실패" 토스트
행이 재조회 전까지 남아 있어 같은 id로 DELETE가 두 번 나갔고, 두 번째는 이미 없는 문서라 400대 →
"되돌릴 수 없어요"라고 강조한 화면에서 성공과 모순되는 안내. → 같은 id의 진행 중 삭제는 그 결과를
함께 받고(`_deletingInbody`), 성공 즉시 행을 목록에서 뺀다(재조회 전에 두 번째 탭이 들어갈 자리를
없앤다). 시험 4건(중복 제거가 상시화되면 삭제가 죽는 케이스 포함).

### C18 (앱 LOW→5곳) 로컬 `DateTime`의 날짜 산술이 기기 서머타임에 하루를 흘렸다
`difference().inDays`·`add/subtract(Duration(days:))`는 절대 시각 산술이라 기기가 DST 지역이면
전환일을 낀 하루가 23/25시간 → D-day가 하루 당겨지고(`daysUntilExpiry`), 전환일 체크가 어느 주에도
안 들고(`HomeworkWeekRules`), 가을 전환 뒤 예약 날짜 스트립에 **같은 날짜 칩이 둘·하루 누락**
(`DateStrip`), 사진 비교 "N일 뒤"가 하루 어긋났다. 한국엔 DST가 없지만 이 산술은 **기기** 타임존
규칙을 탄다(해외 체류·외국 기기) — 저장소는 이미 `hold_rules.durationDays`를 UTC 자정으로 고쳐 둔
전례가 있고, 시간대 시험을 `TZ=America/New_York`으로도 돌리는 규약이 있다. → 4곳을 `DateTime.utc`
필드 산술 / 달력 필드(`day + i`) 정규화로. 시험은 전환일(2026-03-08·03-29·11-01)을 끼운 값으로 —
**KST 호스트에선 종전 코드도 통과하므로** 검증 스크립트가 같은 파일을 `TZ=America/New_York`으로
한 번 더 돌린다(`flutter_test_tz_newyork`).

## 적대적 리뷰 4라운드 (수정분을 새 눈이 다시 봤다 — 실제로 건진 것)
- **R1(백엔드)** LOW 2: `RefundedAmount int`+omitempty가 **0원 환불을 키째 지운다** → 포인터로 ·
  동의 플래그가 둘 다 없는데 `signed_at`을 찍던 분기 → switch로 가드.
- **R2(앱·어드민)** CRITICAL 2 + MEDIUM 1: ① `cross_tab_invalidate_test`의 가짜 저장소가 가짜 API를
  **부르지 않아** 카운트가 영원히 0 — 초록이어도 아무것도 안 재는 시험(**함정 ⑩ 그 자체**) → 생성자
  주입으로 실제 배선. ② `DateTime.tryParse('2026-13-99')`는 Dart에서 **null이 아니라 이월 정규화**된다 →
  자릿수 불일치·빈 문자열·비날짜로 교체(범위 초과는 서버 `time.Parse`가 막는다는 사실을 주석에 남김).
  ③ `takeException`은 RenderFlex 외 오버플로를 못 잡는다 → 텍스트 높이 실측(≤80)으로.
- **R3(리뷰 이후 변경분만 새 눈)** MEDIUM 1: 0원 환불 시험이 "결제 기록 없음"으로 셋업했는데
  `refundBasis`는 결제 기록이 없으면 **계약가 전액을 실수납으로 간주**(레거시 폴백)해 900,000원이 나온다 —
  같은 파일의 기존 golden 값(`TestSplitPaymentRecordsWithinContractPriceAllowed`)이 이미 증명하던 사실.
  → "결제는 있으나 **미납 회차**(paid_at 없음)"로 진짜 0원을 만들고 `PaidSum/Refund == 0`을 셋업 단언.
  나머지(P65-3 배치 전체 · 포인터화 · 동의 switch · 어드민 잠금 완화)는 **정확**으로 판정.
- **R4(2라운드 수정분)** CRITICAL·MEDIUM 0: 직렬화 체인의 마이크로태스크 순서·`??=` 중복 제거·UTC 산술의
  대칭성·새 시험 5파일의 생성자/인터페이스 전수 대조 → 통과. LOW 1(같은 hwId의 뒤 요청이 앞 요청의
  타임아웃만큼 기다릴 수 있다 — 조용한 손실 대신 택한 트레이드오프, 기록만).

## 진행 단계
- [x] 스냅샷 복사 + 자 확보(도구 제약 확인: go/flutter 실행 불가 → 맥 위임 스크립트 작성)
- [x] 7팀 병렬 읽기 전용 조사(40건) → 핵심 주장 직접 확인 → 수리 32 / 보류 8
- [x] 수리(3계층 + 계약 v2.37 + 법정 문서 + 설정) · 어드민 tsc · gofmt 구문 검사
- [x] 적대적 리뷰 R1·R2 → 수정 → P65-3 후속 → R3 → 수정
- [x] 2라운드: 미열람 파일 99개 → P3·P4(4건) → 수리 → R4
- [x] 맥 반영 63파일 md5 전수 대조
- [x] 맥에서 `docs/temp/p73_verify.sh` 3회(1차: 분석기 오류 3 + 시험 가짜 결함 → 2차: 시험 3건 → 3차: 전부 그린)
- [x] 변이 검사 14/14 KILL → 이 문서 갱신 → 완료

## 변경 파일 (80 — 코드·문서 76 + 검증 스크립트 2 + work_log 2)
**backend** — `internal/api/auth.go`(C5) · `service.go`(C4·C6·C8·C9) · `service_stats.go`(C7) ·
`handlers_staff.go`(주석) · `internal/domain/pass.go`(C4) · `internal/store/firestore.go`·`memory.go`(C10) ·
시험 `service_admin_test.go`·`service_guard_not_silent_test.go`·`hookstore_test.go`·`service_account_test.go`·
`service_test.go`·`service_bodypose_test.go`·`service_money_test.go`·`store/conformance_test.go` ·
`README.md`·`.env.example`.
**admin** — `lib/queries.ts`(C11 stats)·`lib/firebaseErrorKo.ts`(신설)·`lib/types.ts`(refunded_*) ·
`features/Login.tsx`·`Settings.tsx`·`Centers.tsx`·`Members.tsx`·`Schedule.tsx`·`Dashboard.tsx` ·
`public/legal/account-deletion.html`·`privacy.html`·`support.html` · `README.md`.
**app(lib)** — `features/my/presentation/my_view_model.dart`(C1) · `core/api/staff_directory.dart`(C2) ·
`features/booking/presentation/booking_view_model.dart`(C3) · `features/records/presentation/records_screen.dart` ·
`features/bodycheck/data/body_check_repository_impl.dart`(C9) · `features/auth/{domain/auth_models,
data/auth_remote_data_source, data/auth_repository_impl, presentation/center_confirm_screen,
presentation/center_contact_provider}.dart`(C13) · `records/.../body_photo_viewer.dart` ·
`booking/.../booking_confirm_sheet.dart` · `my/.../pass_list.dart`·`consent_toggles.dart`·`signature_pad.dart` ·
`bodycheck/.../pose_sequence_chips.dart` · `app.dart`(주석) · `pubspec.yaml`(1.0.1+9) ·
`ios/Runner.xcodeproj/project.pbxproj`·`ios/scripts/check_release_target.sh`(C12) · `README.md` ·
**2라운드** `features/home/presentation/home_view_model.dart`(C15) · `features/home/domain/checkin_rules.dart`(C16) ·
`features/records/presentation/records_view_model.dart`(C17) · `features/home/domain/home_models.dart`·
`features/records/domain/homework_week_rules.dart`·`features/booking/presentation/widgets/date_strip.dart`·
`features/records/presentation/widgets/body_photo_timeline.dart`(C18).
**app(test)** — 신설 `my/presentation/cross_tab_invalidate_test.dart`(4) · `bodycheck/data/body_photo_bad_date_test.dart`(2) ·
`bodycheck/presentation/pose_chip_semantics_test.dart`(1) · `auth/data/join_match_center_test.dart`(2) ·
추가 `core/api/staff_directory_test.dart`(3) · `auth/presentation/center_confirm_screen_test.dart`(2) ·
`center_contact_provider_test.dart`(2) · `records/.../body_photo_viewer_test.dart`(1) ·
`inbody_chart_legend_test.dart`(1) · `my/.../signature_pad_test.dart`(1) ·
**2라운드** 신설 `home/presentation/homework_toggle_serialization_test.dart`(3) · `home/domain/checkin_rules_test.dart`(4) ·
`home/domain/pass_option_expiry_test.dart`(3) · `booking/presentation/widgets/date_strip_test.dart`(1) ·
`records/presentation/inbody_delete_dedupe_test.dart`(4) · 추가 `records/domain/homework_week_rules_test.dart`(1).
**루트/문서** — `firebase.json` · `docs/API계약_v1.md`(v2.37 절) · `docs/temp/p73_verify.sh`·`.command`(검증 위임 ·
KST 아닌 TZ 재실행 포함) · `docs/temp/p73_mutate.sh`(변이 검사 12건 자동화) · 이 문서 · `work_log/README.md`.

## 계약
`docs/API계약_v1.md` **v2.37** — ① `Pass.refunded_amount`·`refunded_at`(환불 뒤에만, 0원도 키 존재) ·
② `POST /v1/body-photos` `date`(YYYY-MM-DD·미래 거부)·`direction`(front|side|back) 400 · ③ `CreateMember`
동의 시각 서버 스탬프 · ④ superadmin 관문 정확일치 · ⑤ 내부 수정(fail-closed·통계·스토어 대칭) ·
클라이언트 반영 목록(P65-3 포함) · 무변경 명시. **서버 배포가 필요하다**(①②③④).

## 검증
- 맥 `docs/temp/p73_verify.sh` **3차 실행 전부 그린**: `go vet`·`go test ./...`·`-race` 그린 · `npm run build` 그린 ·
  `flutter analyze` **0 issues** · `flutter test` **1532 pass**(착수 1497, 신규 35, 회귀 0) ·
  `TZ=America/New_York` 시간대 시험 **29 pass** · 이어서 변이 검사 **14/14 KILL**. 로그 `docs/temp/p73_logs/`
  (run1/·run2/에 이전 회차 보관). 맥 반영 80파일 md5 전수 일치(변이 원복 뒤 재확인).
- 세션 안 정적 검사(맥 실행 전): 어드민 `tsc --noEmit` · Go `gofmt -e` · Dart 괄호 밸런스·식별자 전수 grep ·
  적대적 리뷰 4라운드.

### 실제 실행이 잡은 것 (사람 눈 리뷰 4라운드가 놓친 것 — 이 절차의 값어치)
- **1차(51 실패 중 50이 컴파일)**: `sessionProvider.select(...)`가 컴파일되지 않았다 — Riverpod 3.0.3에서
  `select`는 `ProviderListenableSelect` **확장**이고 `riverpod_annotation`은 그것을 재수출하지 않는다
  (`flutter_riverpod` import 필요). 저장소에 provider `.select` 선례가 0건이라 리뷰 4라운드가 전부
  "유효"로 판정했다. + `const Semantics(...)`는 const 생성자가 아니다(R2가 "const 가능"으로 오판).
  + 새 시험 가짜의 게이트 버그: 호출이 `_gate`를 비운 뒤 `release()`가 그 `_gate`를 풀어 **아무도 안 풀려**
  30초 타임아웃 — 자문자답 라운드가 `whenComplete(() => map.remove(id))`의 자기 대기(같은 부류의 "끝나지 않는
  Future")는 잡았지만 이건 놓쳤다.
- **2차(3 실패)**: 직렬화 시험이 `Future.delayed`로 이벤트 루프를 한 번 돌리자 **구독 없는 autoDispose
  provider가 폐기**돼 "폐기된 Ref" 예외·null 상태 — 시험은 홈 탭처럼 구독을 유지하도록(현실과 같게),
  프로덕션은 `ref.mounted` 가드(auth·camera 뷰모델 규약)를 제출 전후에 넣어 로그아웃 중 제출이 던지지 않게.
- **3차**: 전부 그린 → 변이 14/14 KILL(전부 단언 실패 — `mut_12`는 NY 시간대에서 정확히 "일 1" 칩 중복을,
  `mut_10`은 동시에 떠 있는 두 배열을, `mut_2`는 이전 계정의 't1'을 드러냈다).

### 변이 검사 (되돌리면 죽어야 하는 짝 — 전부 KILL)
① `my_view_model.dart`의 `ref.invalidate(myProfileProvider)` 제거 → `cross_tab_invalidate_test` KILL ·
② `staff_directory.dart`의 세션 watch 제거 → `staff_directory_test` '세션 경계' KILL ·
③ `service.go` RefundPass의 `fresh.RefundedAmount/RefundedAt` 기록 제거 → `TestRefundPass*`·`TestPassWireOmits…` KILL ·
④ `auth.go`를 `HasPrefix(p, "/v1/admin")`로 원복 → `TestSuperadminPathBoundary` KILL ·
⑤ `service_stats.go` `withdrawn` 스킵 제거 → `TestWithdrawnMemberExcluded…` KILL ·
⑥ `body_check_repository_impl.dart` `tryParse`→`parse` 원복 → `body_photo_bad_date_test` KILL ·
⑦ `auth_remote_data_source.dart` `centerName` 배선 제거 → `join_match_center_test` KILL ·
⑧ `service.go` GetStaff 가드를 `err == nil`로 원복 → `service_guard_not_silent_test` CreateBooking/CreateRecurring KILL ·
⑨ `checkin_rules.dart` 초 절삭 원복 → `checkin_rules_test` KILL · ⑩ `home_view_model.dart` 직렬화 해제 →
`homework_toggle_serialization_test` KILL · ⑪ `records_view_model.dart` `??=`→`=` → `inbody_delete_dedupe_test` KILL ·
⑫ `date_strip.dart` 절대시각 덧셈 원복 → `date_strip_test` **TZ=America/New_York에서** KILL(KST 호스트에선 SURVIVE가
정상 — 그래서 TZ를 바꿔 돌린다). 전부 `docs/temp/p73_mutate.sh`에 자동화(백업→변이→시험→원복→md5 확인),
검증 스크립트가 그린이면 이어서 실행한다. **결과: 14/14 KILL**(⑤·⑧은 자리가 둘이라 하위 변이 포함).

## 안 하기로 한 것 (그리고 그 이유)
- **`skipError` 전역 변경**(P1, P33 재확인): 재조회 실패 시 탭 전체가 에러 화면으로 뒤집히는 문제는
  실재하지만 전 탭의 로딩 규약을 바꾸는 일이라 화면별 재측정이 필요하다 → P33 후속 유지.
- **Firestore 컨포먼스 CI 연결**(B1 HIGH): 에뮬레이터 기동·서비스 계정이 CI 구성 결정을 동반한다 —
  람 결정 사항. 이번엔 Memory 컨포먼스만 확장했다.
- **`PayInstallment`/`CreatePayment` 트랜잭션화**(B2, P37 재확인): 체크-후-쓰기 경쟁은 실재하나
  결제 문서 3곳을 한 번에 트랜잭션으로 옮기는 일은 원장 규약(P3)과 함께 설계해야 한다 → P37 유지.
- **`DELETE /v1/join/request`**(B2, P69-4 재확인): 계약·어드민 큐 화면이 함께 움직인다 → P69-4 유지.
- **인바디 `_reading` 잠금 연동**(P2 LOW, P59-3 재확인) · **계약 서명 스크림 탭 보호**(P2 LOW): 화면 규약을
  P59가 시험으로 고정해 둔 자리라 그 결정 위에 덧대지 않는다.
- **계정 삭제 제출 중 뒤로가기 안내 스낵바**(P2 LOW): 넣었다가 **되돌렸다** — `ScaffoldMessenger` 큐가
  완료 스낵바를 뒤로 미뤄 `account_deletion_test`의 "완료 안내" 시점이 깨진다. 잠금 자체는 이미 있다.
- **`privacy.html` 처리위탁표의 앱 운영자**(X1, P66-6 재확인): 사업자 정보를 적는 일 — 람 결정.
- **다크모드 · FCM 승인 푸시**: P72 결정 유지(조사팀도 결함으로 올리지 않았다).

## 후속 작업
1. **람 — 커밋·배포**: P73 80파일(+P71·P72 분)이 미커밋(브랜치 `feat/contract-esign-admin-usability`, HEAD는
   P53~P70). 서버(v2.37 ①~④) · 어드민 · 앱 순. `docs/temp/`(검증 스크립트·로그)는 untracked — `.gitignore`에
   넣거나 끝난 뒤 지운다. `pubspec 1.0.1+9`가 의도한 번호인지 확인(Xcode에 적혀 있던 값을 따랐다).
2. `centerDisplayName`·`staffMap` 함수 본문이 바뀌었으므로 맥에서 `dart run build_runner build`를 한 번
   돌려 `.g.dart`의 핫리로드 해시를 갱신(테스트·컴파일과 무관, 정합용).
3. Firestore 컨포먼스 CI(B1) · 결제 트랜잭션(P37) · skipError(P33) · join/request 철회(P69-4) — 위 보류 항목.
4. 어드민 "환불 이력" 전용 목록(지금은 회원권 카드 한 줄) — 환불이 잦아지면.

## 참조
- 세션 산출물(클라우드): `ptdesk_audit/{B1,B2,A1,A2,P1,P2,X1}.md` 조사 보고 · `R1_backend_review.md`·
  `R2_app_admin_review.md`·`R3_review.md`·`R4_review.md` 리뷰 · `P3.md`·`P4.md` 2라운드 조사 · `finding_map.md`
  대조표 · `p73_full.diff`·`p73_round2.diff`. 맥: `docs/temp/p73_logs/`(3회차 로그·mutation.txt).
- work_log/P71-initial-password-and-booking-integrity.md(주석을 믿지 않는다) · P72(자 먼저·변이 검사) ·
  P65/P66(멀티센터) · P33·P37·P59·P69(보류 항목 원출처)
- 스킬: `~/.claude/skills/ram-verify-loop`(자 먼저 · 변이 검사 · 멈추는 조건 · 함정 ⑩)
