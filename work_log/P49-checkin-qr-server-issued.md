---
id: P49
title: 데스크 체크인 QR — 대표가 환경변수를 알 필요가 없어진다
status: 완료
domain: cross
created: 2026-08-30
completed: 2026-08-30
---

# P49 — 체크인 토큰: 환경변수 → 서버 발급 센터 비밀

> 백엔드(이 절)와 어드민(맨 아래 절)을 병렬로 진행했다. 계약 v2.23이 둘 사이의 와이어다.

## 목표

대표(센터 대표)의 말: **"그냥 자동 생성 버튼만 있으면 되잖아, 값 대조 같은 건 실사용자한테
필요 없잖아."**

종전 구조에서 데스크 체크인 QR을 인쇄하려면 대표가 **자기가 알 수 없는 문자열을 알아야** 했다.
값은 Cloud Run 환경변수 `CHECKIN_QR_TOKEN` 안에만 있는데, 어드민 화면은 그것을 손으로 입력하라
요구했고 그 위에 `sha256sum`으로 서버 값과 대조하라는 셸 명령까지 안내했다. 센터 대표는 배포
설정을 볼 수 없고 서버 셸도 없다 — 개발자가 옆에 붙지 않으면 끝나지 않는 화면이었다.

토큰을 **서버가 만들어 센터 문서에 보관하는 비밀**로 바꾸고, owner 전용 발급/재발급
엔드포인트를 낸다. 사람이 값을 알거나 옮겨 적는 단계를 없애는 것이 목표 전부다.

## 결정 사항

### 1. `CHECKIN_QR_TOKEN`과 그 기동 검증을 **함께 삭제**한다 (자문자답의 본체)

세 안을 놓고 골랐다.

| 안 | 판정 | 근거 |
|---|---|---|
| (a) DB가 유일한 진실. 미발급이면 self_qr 거부 + env·기동검증 삭제 | **채택** | 조용히 안전하지 않은 상태가 0개 |
| (b) DB가 비면 env로 폴백 | 기각 | **재발급이 이전 토큰을 무효로 만들지 못한다** |
| (c) 비기본 env 토큰을 최초 1회 DB로 흡수(인쇄물 보존) | 기각 | 없는 문제를 푼다 + 죽은 설정을 살아 보이게 남긴다 |

**(b)가 가장 결정적으로 틀렸다.** 폴백이 있으면 유출된 env 토큰이 영원히 통과하는데 어드민
어디에도 보이지 않는다 — 대표는 재발급을 누르고 "되돌렸다"고 믿지만 실제로는 안 되돌아갔다.
이 작업이 계약으로 박은 "재발급 = 직전 인쇄물 무효"가 그 순간 거짓이 되고, 그 거짓은 사고가
나기 전까지 아무 증상도 내지 않는다. **가장 적은 수의 조용한 불안전 상태**를 고르라는 것이
지시였고, 폴백은 그 기준에서 최악이다.

**(c)는 없는 문제를 푼다.** 제품 미출시 — 온보딩된 회원 0, 발급된 계약 0, 인쇄된 QR 0이다.
보존할 인쇄물이 없다. 반면 대가는 실재한다: ① 읽기가 문서를 만드는 형태인데 이 코드베이스는
`GetBusiness`·`GetFacility`에서 그 모양을 의도적으로 거부해 왔다 ② `CHECKIN_QR_TOKEN`이 Cloud
Run 설정에 남아 **다음 사람이 살아 있는 값으로 읽는다**. 죽었는데 살아 보이는 설정은 덫이다.

**기동 검증을 함께 지운 이유**가 자문자답의 핵심이다. 그 검증(`USE_FIRESTORE=true` + 저장소
기본값이면 거부)은 겉보기에 "보안 장치"라 남기고 싶어진다. 그런데 그것이 실제로 막던 것은
**`env()`가 빈 문자열을 미설정으로 보고 저장소에 적힌 공개 기본값으로 승격시키는 fail-open**
하나뿐이다. 읽는 코드가 사라지면 승격될 기본값 자체가 없고, 막을 대상이 없는 검증은 보호가
아니다 — 아무도 안 읽는 변수 때문에 기동을 거부하면 그게 새로운 거짓말이다.

fail-closed는 사라진 게 아니라 **기동 검증에서 요청 경로로 내려갔다**: 미발급 센터의 self_qr은
폴백 없이 400이고, 문구가 조치를 말한다("데스크 체크인 QR이 아직 발급되지 않았습니다 — 어드민
설정에서 발급해 주세요"). 종전 공개 기본값 `rise-desk-checkin`을 보내도 통과하지 않는다.
`qr_token이 유효하지 않음`만 돌려주면 대표는 인쇄물과 앱을 의심하며 헤맨다 — 고칠 곳은 어드민
설정인데 화면이 그 말을 안 한다.

레거시 배포 설정은 **무해**하게 만들었다: Cloud Run에 변수가 남아 있어도 읽히지 않고 기동도
막지 않는다. config 테스트가 "env가 Config를 바꾸지 않는다"를 고정해 폴백 부활 회귀를 잡는다.

### 2. 두 엔드포인트 **모두** owner 전용

조회만 막으면 트레이너가 rotate로 새 토큰을 받아 **그 응답에서 값을 읽는다**(발급 응답에도
토큰이 실린다). 한쪽만 잠근 문은 잠긴 문이 아니다. 데스크를 트레이너가 지키는 센터가 많아
열어 주고 싶어지지만, 이 값은 **"보는 권한"과 "가지는 권한"이 같다** — 한 번 보면 화면을 찍어
영구 보관하고 퇴사해도 사본은 남는다. 인쇄물은 대표가 한 번 뽑아 붙이면 되는 물건이라 열어서
얻는 편의보다 잃는 통제가 크고, 트레이너가 회원 출석을 찍는 정당한 경로는 tap 체크인으로
이미 따로 있다(권한 분리가 이미 존재한다).

### 3. 발급과 재발급은 **같은 동사**

나누면 "이미 발급됨" 409 분기가 생기고 어드민이 상태를 먼저 조회해 버튼을 고르게 되는데,
조회와 실행 사이에 다른 창에서 발급이 끼면 대표는 무엇이 실패했는지 알 수 없는 에러를 본다.
발급은 애초에 멱등할 수 없는 행위(늘 새 값)라 확인은 UI의 몫이고, 서버는 "누르면 새로 난다"는
한 가지 의미만 갖는 편이 정직하다.

### 4. rotate는 **바디를 읽지 않는다**

`decodeJSON`을 태우지 않은 것은 의도다. 읽는 순간 어드민이 무엇을 보내도 되는 것처럼 보이고,
언젠가 "원하는 토큰을 지정" 같은 필드가 붙는다 — 그러면 사람이 고른 비밀이 다시 들어와 이
작업이 없앤 문제가 그대로 돌아온다. **토큰의 출처는 crypto/rand 하나뿐이라는 것이 계약이다.**
GET에 rotate를 걸지 않은 것도 같은 계열(브라우저 프리페치·재시도가 인쇄물을 죽이면 안 된다).

### 5. 전용 응답 타입으로만 나간다 (마스킹 목록이 아니라)

`CenterResponse`에 필드를 얹고 역할별로 가리는 방식이었다면, 다음에 누가 필드를 늘릴 때
마스킹을 잊는 순간 샌다. `CheckinQRView`에 담을 것을 손으로 적어야만 나가게 했다 —
`PublicBusiness`의 `BusinessView`와 같은 근거다. 위협 모델 전부가 한 줄이다: **토큰을 아는
회원은 집에 누워 출석을 찍는다.**

### 6. 토큰 길이 32자는 QR 제약에서 나왔다

24바이트 → `RawURLEncoding` 32자(192비트). 문자셋에 소문자·`-`·`_`가 있어 QR 영숫자 모드를
못 쓰고 바이트 모드로 떨어지는데, 32바이트는 오류정정 레벨 Q에서 **버전 3(29모듈)에 정확히**
들어간다. 더 길면 버전이 올라가 같은 인쇄 크기에서 모듈이 잘아지고, 데스크 조명·코팅 반사에서
스캔 실패가 는다. 패딩 `=`를 뺀 것은 URL·QR 페이로드에서 이스케이프 논쟁을 부르는 문자라서다.

### 7. DEV_SEED는 **고정 토큰**을 심는다

실발급(crypto/rand)이면 매 구동마다 값이 달라져 앱의 `CHECKIN_QR_TOKEN` dart-define 폴백이
맞을 수 없고, 카메라 없는 시뮬레이터·CI가 셀프 체크인을 끝까지 돌려볼 통로가 사라진다.
공개된 값이어도 안전한 이유는 **범위**다: `SeedDemo`는 `DEV_SEED=true` + **인메모리 스토어**
일 때만 호출된다(`cmd/server/main.go`). 종전 구조의 위험은 "문자열이 알려졌다"가 아니라
"알려진 문자열이 **실 DB에 붙은 서버**에서 통했다"였고(그래서 기동 검증이 있었다), 그 조합이
여기서는 성립하지 않는다.

### 8. 비교를 상수 시간으로

192비트짜리를 타이밍으로 캘 일은 없다. 그래도 바꾼 이유는 **비밀을 `!=`로 비교하는 코드가
다음 사람이 복사해 가는 본보기**가 되기 때문이다. 길이가 다르면 0을 돌려주므로 판정 의미는
바이트 비교 그대로다.

## 진행 단계

- [x] 기존 코드 독해 — config 부트 검증(:62-65) · service.go self_qr(:1854) · P42 facility
      3종(domain/service/handlers) · 스토어 센터 문서 동사 · seed · .env.example · README 배포절
- [x] 자문자답: env 처리 3안 비교 → (a) 채택, 근거를 계약 문서·이 파일에 명문화
- [x] 도메인 — `domain.CheckinQR` + `NewCheckinQRToken()` + `Issued()`/`Normalize()`
- [x] 스토어 — 인터페이스 2동사 + Memory + Firestore(**머지 쓰기**) + 컨포먼스 1케이스
- [x] 서비스 — owner 게이트 · crypto/rand 발급 · `issued_at` · `CheckinQRView` 전용 타입
- [x] 체크인 검증 경로를 저장 토큰으로 전환 + 미발급 거부 문구
- [x] 핸들러 2개 + 라우트 2개
- [x] `CHECKIN_QR_TOKEN` 제거(config 필드·기본값 상수·Load·Validate 분기) + 회귀 테스트로 대체
- [x] SeedDemo 고정 토큰 시딩 + `store.DemoCheckinQRToken`
- [x] 테스트 10 + 컨포먼스 1 + config 1
- [x] build / vet / test -count=1 / -race(api) / 에뮬레이터 컨포먼스
- [x] 뮤테이션 12건 — 12/12 kill
- [x] 문서 — 계약 v2.23 · `.env.example` · backend/README(배포표·엔드포인트·테스트표·총계)

## 변경 파일

### 신규

- `backend/internal/domain/checkin_qr.go` — 타입·`NewCheckinQRToken`(24B→32자 RawURL base64)·
  `Issued()`·`Normalize()`. 길이 32의 QR 근거를 주석에 남김
- `backend/internal/api/service_checkin_qr.go` — `CheckinQRView` + `GetCheckinQR` +
  `RotateCheckinQR`(owner 게이트 2곳)
- `backend/internal/api/handlers_checkin_qr.go` — 핸들러 2개(rotate는 바디 미독해)
- `backend/internal/api/service_checkin_qr_test.go` — 테스트 10건

### 수정

- `backend/internal/api/service.go:1854±` — self_qr 대조를 `s.cfg.CheckinQRToken` →
  `s.store.GetCheckinQR` + 미발급 400 + `subtle.ConstantTimeCompare`. `crypto/subtle` import
- `backend/internal/api/router.go:135-139` — `GET /center/checkin-qr` ·
  `POST /center/checkin-qr/rotate`(`/api/v1` 미러는 같은 클로저라 자동)
- `backend/internal/config/config.go` — `defaultCheckinQRToken` 상수 · `CheckinQRToken` 필드 ·
  `Load` 한 줄 · `Validate` 분기 **삭제**. 삭제 근거를 파일 상단·Validate 안에 주석으로 보존
- `backend/internal/store/store.go:393-405` — 인터페이스에 `GetCheckinQR`/`SaveCheckinQR`
- `backend/internal/store/memory.go` — `checkinQRs` 맵 + 두 동사(`IssuedAt` 깊은 사본)
- `backend/internal/store/firestore.go:1890-1924` — `checkin_qr` 절 머지 읽기/쓰기
- `backend/internal/store/seed.go` — `DemoCheckinQRToken` 상수 + 시딩
- `backend/internal/store/conformance_test.go` — `CheckinQRRoundTripAndCoexist`(5단)
- `backend/internal/config/config_test.go` — 기본값 케이스 2건 삭제 →
  `TestCheckinQRTokenEnvIsNoLongerRead`로 대체
- `backend/internal/api/service_test.go` — `TestSelfQRCheckinFindsBookingInWindow`가
  `seedCheckinToken` 픽스처를 쓰도록. 시간창 예약 심기를 `seedBookingInCheckinWindow`로 추출
- `backend/internal/api/service_demo_seed_test.go` · `service_inbody_test.go` — 삭제된
  config 필드 참조 제거
- `docs/API계약_v1.md` — **v2.23** 신설(와이어·보안 규약·env 삭제 결정·배포 순서)
- `backend/.env.example` — `CHECKIN_QR_TOKEN` 블록을 "삭제됨 + 새 경로 안내"로 교체
- `backend/README.md` — 배포 환경변수 표(취소선 + 폐기 명시) · 새 절 "데스크 체크인 QR —
  환경변수가 아니다" · 엔드포인트 지도 · 테스트 파일 표 + 총계 재집계(274 → 332)

## 검증

```
go build ./...                                        OK
go vet ./...                                          OK
go test -count=1 ./...                                api / config / domain / store 전부 ok
go test -race -count=1 ./internal/api/...             ok (2.1s)
firebase emulators:exec --only firestore ...          ok (15.9s) — 두 구현이 새 동사에 합의
gofmt -l (신규·수정 파일 전부)                          clean
```

`gofmt -l`이 저장소 전체에서 3건을 남기지만(`service_body_photo_reconcile_test.go` ·
`policy_test.go` · `service_demo_seed_test.go`) **전부 기존 결함**이다 — 동아시아 문자폭 정렬에
대한 gofmt 판정 차이이고, 내가 만진 줄과 무관한 위치다(HEAD 사본에서도 동일하게 플래그된다).
병렬 세션 영역 파일이 섞여 있어 손대지 않았다.

### 뮤테이션 12건 — **12/12 kill (정직)**

| # | 심은 결함 | 잡은 테스트 |
|---|---|---|
| M1 | `GetCheckinQR` owner 게이트 제거 | `TestCheckinQROwnerOnly` · `TestCheckinQREndpoints` |
| M2 | `RotateCheckinQR` owner 게이트 제거 | 같음(+ 403 뒤 미발급 단언) |
| M3 | 미발급 거부 분기 제거 | `TestSelfQRCheckinRejectedWhenNeverIssued` |
| M4 | 재발급이 기존 토큰 재사용(무효화 실패) | `...RotationKillsOldPrints` 외 2 |
| M5 | `CenterResponse`에 토큰 누출 | `TestCheckinTokenNeverLeaksToSharedResponses` |
| M6 | 상수시간 비교를 항상-참으로 | `...RotationKillsOldPrints` · `...FindsBookingInWindow` |
| M7 | `Memory.GetCheckinQR` 지연 시딩(읽기가 토큰 생성) | `TestGetCheckinQRBeforeIssue` · 컨포먼스 |
| M8 | `SeedDemo` 토큰 시딩 제거 | `TestSeedDemoIssuesKnownCheckinToken` |
| M9 | `NewCheckinQRToken` 엔트로피 0(컴파일되는 형태로 재실행) | `TestRotateCheckinQRTokenShape` 외 2 |
| M10 | `issued_at` 미기록 | `TestRotateCheckinQRPersistsAndStampsTime` · 엔드포인트 |
| M11 | `Issued()` 항상 참 | `TestGetCheckinQRBeforeIssue` · 컨포먼스 |
| M12 | Firestore `SaveCheckinQR`를 통 Set으로(머지 파괴) | 컨포먼스 `:1627`(**에뮬레이터에서만** 재현) |

M9는 1차에 컴파일 거부(빈 import)로 끝나 **약한 kill**이라, `if false { rand.Read(...) }`로
컴파일되는 형태로 다시 심어 실제 테스트 실패를 확인했다. M12는 Memory에 머지 개념이 없어
기본 `go test`로는 영원히 초록이다 — 에뮬레이터에서 돌려 `slot_capacity=4`가 사라지는 것을
실측했다(P27 사고의 정확한 재현).

## 후속 작업

- [ ] **배포 후 대표가 어드민에서 1회 발급**해야 셀프 체크인이 열린다(env 토큰 미이관 — 결정 1의
      (c) 기각 결과). 회원 0명이라 실사용 중단은 없지만 순서상 사실
- [ ] Cloud Run의 `CHECKIN_QR_TOKEN` 환경변수 제거(무해하지만 죽은 설정 — 남기면 다음 사람이
      살아 있는 값으로 읽는다)
- [ ] `app/README.md` — `CHECKIN_QR_TOKEN`을 "백엔드 Cloud Run 환경변수와 값이 같아야 한다"
      (:184, :191, :179, :203)로 설명하는 4곳이 사실과 어긋났다. 이제 그 dart-define은 **DEV_SEED
      데모 토큰과 맞추는 dev 폴백**일 뿐이다. 앱 코드는 무변경(영역 밖 — 앱 세션 소관)
- [ ] `admin/README.md:302-306`, `:131` — 어드민 절 후속 참고

## 참조

- 계약 v2.23(`docs/API계약_v1.md`) — 와이어·보안 규약·env 삭제 결정·배포 순서
- P42(`P42-contract-template-variants.md`) — 미러한 owner 전용 센터 설정 절 패턴
- P27(`P27-center-business-info.md`) — SavePolicy 통 Set 사고. 이번이 그 교훈의 **네 번째 절**
- P44 — self_qr 체크인 원설계(시간창 ±30분·앱이 스캔값을 가공 없이 전달)

---

## 어드민(admin/src) — 화면 재설계

> 백엔드 절과 병렬로 작업한 구획. 위 본문이 백엔드 소관이면 이 아래가 어드민 소관이다.

### 목표

`CheckinQr.tsx`가 센터 대표에게 **서버 환경변수 값을 손으로 입력하라**고 요구하고 있었다.
그 값은 Cloud Run 설정 안에만 있어 대표가 알 방법이 없고, 화면은 그 위에 "붙이기 전에 값
대조하기"라며 `sha256sum` 셸 명령까지 안내했다. 개발자가 옆에 붙어야만 끝나는 화면이었다.
새 계약(GET `/v1/center/checkin-qr` · POST `/v1/center/checkin-qr/rotate`)에 맞춰
**버튼 하나로 끝나는 두 상태 화면**으로 갈아엎었다.

### 결정 사항 (어드민)

1. **상태는 둘뿐** — 미발급(버튼 1개) / 발급됨(QR · 발급일 · 인쇄 · 새로 발급).
   첫 발급과 재발급은 같은 엔드포인트를 부르지만 **2단 확인은 재발급에만** 붙인다:
   확인이 막아야 할 결과(붙어 있는 종이가 죽는다)가 첫 발급에는 존재하지 않는다.
2. **신원 표식은 발급 일시, 토큰 뒷자리는 쓰지 않는다.**
   `YYYY-MM-DD HH:MM`을 화면 "발급일" 칸과 인쇄물 하단에 **같은 문자열**로 찍는다.
   분 해상도면 같은 날 두 번 발급한 종이도 갈리므로, 비밀 조각(뒷 4자)을 흘릴 이유가 없다.
   덤으로 종전 인쇄물 하단의 `{지문} · {출력일}`이 고쳐졌다 — 출력일은 토큰이 바뀌어도
   안 변하고 재인쇄하면 변해서, 표식으로 쓰기엔 방향이 정확히 반대였다.
3. **토큰 문자열은 화면 어디에도 글자로 띄우지 않는다.** QR이 유일한 표현이다.
4. **재조회가 끝날 때까지 인쇄를 막는다.** `useRotateCheckinQr`의 `onSuccess`가
   `invalidateQueries`의 **프로미스를 돌려준다** → react-query v5가 재조회까지 `isPending`을
   유지 → 그동안 인쇄 버튼 disabled + 인쇄 시트 언마운트. 프로미스를 삼키면 캐시에 아직
   옛 토큰이 있는 상태로 pending이 풀려 **방금 무효가 된 QR을 인쇄할 창**이 열린다.
5. **`useCheckinQr`에 enabled 게이트를 두지 않는다.** 호출부가 하나뿐이고
   `App.tsx(isOwner) → Settings.tsx(isOwner)` 두 겹 뒤라 트레이너 세션에서는 마운트 자체가
   없다. `useJoinRequests`가 게이트를 갖는 이유(대시보드에서도 불린다)가 여기엔 없다.
6. **배포 시차(404)는 장애가 아니라 "아직 없음"으로 접는다.** 조회·재발급 양쪽에서 404를
   전용 문구로 가른다 — "그동안 데스크에 붙어 있는 QR은 그대로 동작하니 떼지 마세요."
   (구서버는 종전 방식으로 검사하므로 사실이다. 이 말이 없으면 대표가 종이를 뗀다.)

### 삭제한 것 (전부 "사람이 비밀을 손으로 옮긴다"는 전제의 부속물)

| 삭제 | 왜 개발자 전용이었나 |
|---|---|
| `ENV_KEY = "CHECKIN_QR_TOKEN"` + UI의 환경변수 이름 노출 | 대표는 배포 설정을 볼 수 없다 |
| 토큰 텍스트 입력칸(+보기/가리기 토글) | 입력할 값이 더는 사람 손을 거치지 않는다 |
| `tokenIssues()` — `.env` 한 줄 붙여넣기·따옴표·앞뒤 공백·비ASCII 경고 | 전부 **붙여넣기 사고** 진단. 붙여넣을 일이 없어졌다 |
| `cleanToken()` + "자동으로 정리하기" 버튼 | 위 진단의 수리 도구 |
| `useTokenFingerprint()` + SHA-256 8자 대조 UI | 서버 값과 눈으로 맞추는 장치. 서버가 값을 주므로 대조 대상이 없다 |
| `sha256sum` / `printf %s` 셸 명령 블록 | 대표에게 서버 셸을 열라는 안내였다 |
| "브라우저에 저장하지 않는다 / 새로고침하면 사라진다" 문단 | 토큰이 로컬 state였을 때의 해명. 이제 서버가 들고 있다 |
| "왜 기본은 가려두나" 문단 · `저장 안 됨` 뱃지 | 입력칸이 사라지며 함께 무의미해졌다 |

### 보존한 것 (인쇄 품질 보증)

`QR_LEVEL="Q"`(오류정정 25%) · `PRINT_QR_MM=80`(모듈 ≥1.6mm, 64자 토큰까지 실측 근거 유지) ·
`marginSize=4` · 흰 바탕/검은 모듈 · `document.body` 포털 + `has-qr-print` A4 1장 시트 ·
앱 실물과 글자 단위로 맞춘 3단계 안내 · "폰 기본 카메라로 찍으면 아무 일도 안 일어난다
(주소가 아니라 토큰이라서)" · "사이드바·헤더는 인쇄되지 않는다".

### 변경 파일 (어드민)

- `admin/src/features/CheckinQr.tsx` — 전면 재작성(448줄 → 429줄). 입력·진단·지문 → 2상태 화면
- `admin/src/lib/types.ts` — `CheckinQrToken` 신설(`Center` 앞)
- `admin/src/lib/api.ts` — `api.checkinQr()` · `api.rotateCheckinQr()`
- `admin/src/lib/queries.ts` — `keys.checkinQr` · `useCheckinQr()` · `useRotateCheckinQr()`
- `admin/src/features/Settings.tsx` — 마운트 지점 주석(owner 게이트 두 겹이 enabled 생략의 근거)

### 검증 (어드민)

- `npm run build` — tsc(app+node) + vite 통과. 신규 경고 없음(청크 크기 경고는 기존)
- 누수 grep(`CHECKIN_QR_TOKEN` / `sha256sum` / `shasum`): `admin/src` **0건**
- 남은 1건은 `admin/README.md:302-306`(구 화면 설명) — **영역 밖이라 손대지 않음**, 아래 후속

### 후속 (어드민)

- [ ] `admin/README.md:302-306` — "대표가 직접 입력하는 로컬 state" · `CHECKIN_QR_TOKEN` ·
      "SHA-256 앞 8자 지문" 설명이 사실과 반대가 됐다. 서버 발급 + 2상태 + 발급일 표식으로 갱신
- [ ] `admin/README.md:131` 파일 목록 한 줄(P11 → P49) 갱신
