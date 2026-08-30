---
id: P51
title: 센터 운영시간 정책화 · 트레이너 프로필 사진 업로드(서버)
status: 완료
domain: backend
created: 2026-08-30
completed: 2026-08-30
---

# P51 — 운영시간을 정책으로, 사진을 파일로

> 백엔드 갈래. 어드민·앱 갈래는 병렬로 진행했고 계약 **v2.24 / v2.25**가 셋 사이의 와이어다.

## 목표

센터 대표가 서버 없이는 넘을 수 없던 벽 두 개.

1. **운영시간이 코드에 박혀 있다.** 어드민 `Schedule.tsx DEFAULT_HOURS`, 앱
   `booking_rules.dart openHour/closeHour` 둘 다 09~21 하드코딩. 06시에 여는 센터,
   23시에 닫는 센터는 **그 시간대에 예약을 만들 수단이 아예 없다** — 담을 필드가 어디에도 없다.
   설계00 §3.1 "정책은 설정값(하드코딩 금지)"의 마지막 조각.
2. **트레이너 사진에 URL이 필요하다.** 어드민 `Settings.tsx`는 "사진 URL(http/https)"
   텍스트 박스를 준다. 대표 휴대폰·바탕화면의 사진에는 URL이 없고, 제품 안에 URL을 만드는
   수단도 없다. `storage.rules:90-95`가 `staff/photos/{fileName}`을
   `allow read, write: if false`로 **예약해 두고** 주석에 *"서버(Admin SDK)가 올리고,
   클라이언트는 다운로드 토큰 URL로 읽는다"*라고 설계까지 적어 뒀는데 그 서버 경로가 존재한
   적이 없었다. 없던 기능이 아니라 **반쯤 만들어진 채 잠겨 있던 기능**이다.

## 결정 사항

### 1. 0시 표현 — 부재 센티널을 **필드가 아니라 (0,0) 쌍**에 건다 (이 작업의 핵심 판단)

이웃 규약(`NormalizeHoldLimits`, v1.2)은 "0 = 필드 부재 → 기본값 승격"을 **필드 하나씩**
판정하고 무제한은 `-1`로만 표현한다. 운영시간에 그대로 옮길 수 없었다.

| 안 | 판정 | 근거 |
|---|---|---|
| (a) 필드별 `0 = 부재`(홀딩 상한 규약 그대로) | 기각 | **0시는 24시간 헬스장의 실제 여는 시각.** 자정 개점이 영원히 표현 불가능해진다 |
| (b) `-1 = 부재` 센티널 | 기각 | 구문서의 제로값은 어차피 `0`이라 **구분이 안 된다**(마이그레이션 없이 동작해야 한다는 전제와 충돌) |
| (c) `*int` 포인터 | 기각 | Policy는 전 계층이 값 타입이고 Firestore에 `null`이 쓰인다. 머지 PUT·Validate·응답 직렬화 전부를 건드려 비용이 이득을 넘는다 |
| **(d) `(0,0)` 쌍만 부재** | **채택** | `open < close` 검증이 그 쌍을 **애초에 저장 불가능**하게 만든다 → 그 조합만이 안전한 서명. `open_hour=0`은 `close_hour≥1`이면 그대로 산다 |

**읽기는 관대하고 쓰기는 엄격하다.** 저장된 `(0,0)`은 읽을 때 `(9,21)`로 승격하지만,
PUT으로 **명시 전송한** `{open_hour:0, close_hour:0}`은 400이다 — 조용히 9~21로 바꿔 저장하면
대표가 요청한 적 없는 값이 남는다. 홀딩 상한의 "0 읽기=승격 / 0 쓰기=400"과 정확히 같은 비대칭.

### 2. 양끝 포함(inclusive) 슬롯 **시작** 시각 — 그리고 그 사실을 코드가 세게 한다

`9~21`은 09:00 시작부터 21:00 시작까지 **13칸**이다(21:00에 끝나는 게 아니라 21:00에
**시작하는** 수업이 마지막). `h < close`로 쓰면 영업 한 시간이 조용히 증발하고, 증상이 없다.

주석으로만 적지 않고 `domain.Policy.SlotHours()`/`IsOpenHour()`를 뒀다 — 세는 곳마다 다시
틀릴 기회를 없애고, 오프바이원 뮤턴트를 테스트가 죽일 표면을 만든다.

### 3. 서버는 예약 시각을 운영시간으로 **강제하지 않는다** (의도된 범위)

`POST /v1/bookings`·`/v1/recurrings`는 종전대로 `hour 0~23`만 본다. 강제하면 대표가
`close_hour`를 21→20으로 줄이는 순간 **이미 잡힌 21시 예약을 취소·이동조차 못 하게 잠긴다**
(그 예약을 만지는 모든 경로가 400). 정책 변경이 과거를 소급 파괴하지 않는다는 이 코드베이스의
규칙(v2.0 하드 삭제 거부, 이관 시 과거 정산 귀속 보존)과 같은 근거. 데스크에서 특별히 잡아
주는 영업시간 외 수업도 실재하는 정상 영업이다.

### 4. 업로드 경계는 파기 경계와 **분리**한다 — 미설정 시 동작이 반대여야 하므로

`MediaPurger`(v2.11)는 `STORAGE_BUCKET`이 없으면 조용한 no-op으로 떨어진다(예약·결제가
멈출 이유가 없다). `MediaUploader`는 **정반대로 503**이다: no-op이면 어드민은 "저장됨"을 보고
회원앱은 빈 아바타를 본다. 그 조용한 no-op이 실제로 버킷에 고아 50개를 남긴 사고의 모양이다
(v2.15 reconcile이 그 뒤처리로 생겼다). 한 인터페이스로 합치면 이 대칭을 표현할 수 없다.

기본값(`NewService`)도 no-op이 아니라 **503 구현**이다 — 주입을 잊어도 조용한 성공이 없다.

### 5. 옛 파일 경로는 **URL에서 되뽑는다**(프로필에 `photo_path`를 두지 않는다)

`PUT /v1/staff/{uid}/profile`은 **통 교체**라 어드민이 보내지 않은 필드는 지워진다(v1.6 계약).
서버만 관리하는 `photo_path` 칸을 두면 프로필 저장 한 번에 조용히 비고, 그때부터 교체가 옛
파일을 영원히 남긴다. URL은 어드민이 항상 되돌려 보내는 값이라 그 함정이 없다.

되뽑기에는 **호스트 + 경로 모양 + `staff/photos/` 접두 + `..` 차단** 네 겹을 건다. 대표가 손으로
넣어 둔 외부 URL이나 회원 체형사진 경로를 가리키는 토큰 URL이 프로필에 들어 있어도, 사진 교체
한 번이 남의 민감정보 파일을 지우는 일이 없어야 한다.

### 6. 순서: 업로드 → 프로필 저장 → 옛 파일 삭제

- 업로드가 저장보다 **앞**: 업로드 실패 시 프로필 무변경(재시도가 그대로 통한다).
- 옛 파일 삭제가 저장보다 **뒤**: 저장 실패인데 옛 파일을 먼저 지우면 프로필이 죽은 링크를
  가리킨다.
- **저장이 실패하면 방금 올린 파일을 그 자리에서 지운다** — 아무도 가리키지 않는 오브젝트는
  메타에서 출발하는 어떤 경로로도 발견되지 않는다.
- 옛 파일 삭제 실패는 업로드를 실패시키지 않는다(로그만) — 대표에게 사진은 이미 바뀌었다.

### 7. owner 전용 (프로필 편집 PUT과 다른 경계)

프로필 편집은 owner **또는 본인 트레이너**지만 업로드는 owner만이다. 센터 공용 버킷에 **파일을
만드는** 호출이고 되돌릴 수단·용량·비용이 대표 쪽에 있다 — 스태프 관리 계열(생성·정정·이관·
퇴사·복직) 전부와 같은 경계.

### 8. 완결성 검사를 형식별로 (P44 IEND 교훈의 확장)

`image.DecodeConfig`는 헤더만 읽어 "몸통 없는 파일"을 못 본다(P44에서 IHDR만 남긴 PNG가
증거로 저장되던 갭). 형식마다 "끝났다"는 신호가 달라 함수로 받았다:

| 형식 | 완결성 신호 | 왜 그 모양인가 |
|---|---|---|
| PNG | IEND 청크로 **끝나야** 한다(접미 일치) | 명세상 IEND는 마지막 청크이고 CRC가 상수 — 절단본과 IEND 뒤 쓰레기를 하나로 막는다 |
| JPEG | EOI(`FF D9`)가 **존재**해야 한다 | 일부 인코더가 뒤에 패딩을 붙인다 — 접미 일치로 잡으면 정상 사진이 거부된다 |
| WEBP | `"WEBP"` 시그니처 + RIFF **선언 길이 ≥ 실제 길이** | WebP엔 종료 청크가 없다. RIFF 헤더가 스스로 적어 둔 길이가 그 역할을 한다 |

### 9. `golang.org/x/image` 의존성 추가 (webp DecodeConfig)

stdlib에 webp 디코더가 없다. 손으로 VP8/VP8L/VP8X 헤더를 파싱하는 안도 검토했으나
(RIFF 완결성 검사는 어차피 직접 써야 했다), 치수 판독은 라이브러리에 맡기는 쪽이 옳다고 봤다 —
VP8X 캔버스 크기 vs VP8 프레임 크기, 알파·애니메이션 변형이 손으로 틀리기 쉽고, 틀리면
**정상 사진이 거부되는데 실사용에서만 드러난다**. `go list -m -versions`로 2026-08-30 시점
최신 stable **v0.45.0** 확인 후 고정(go.mod에 검증 흔적 주석). 디코더만 쓰고 픽셀은 풀지
않는다(`DecodeConfig` = 헤더만) — 디코드 폭탄 표면 불변.

### 10. 바디 상한을 이 경로만 4MiB로

base64가 3바이트를 4자로 부풀려 2MB 이미지가 약 2.67MiB가 된다 — 공용 `maxBodyBytes`(1MiB)로는
**계약이 허용하는 정상 사진이 먼저 막힌다.** `SignContract`와 같은 모양으로 자기 상한을 걸되
엄격 디코딩(미지 필드 거부)은 그대로.

## 진행 단계

- [x] 리서치·기존 규약 파악(NormalizeHoldLimits · MediaPurger · P44 서명 검증 · storage.rules)
- [x] F1 도메인: `Policy.open_hour/close_hour` + Validate + NormalizeHours + SlotHours/IsOpenHour
- [x] F1 스토어 conformance: 두 구현의 읽기 승격 규약 고정
- [x] F2 업로드 경계(`MediaUploader`) + 503 매핑 + 서비스 주입
- [x] F2 검증(매직·완결성·크기·치수) + 엔드포인트 + 라우트
- [x] 테스트(도메인 표 · API · 라우터) · 뮤테이션 패스
- [x] 문서(계약 v2.24/v2.25 · README · .env.example)

## 변경 파일

**F1 — 운영시간**

| 파일 | 내용 |
|---|---|
| `backend/internal/domain/policy.go` | `OpenHour`/`CloseHour` 필드, `Validate` 절, `NormalizeHours`, `SlotHours`, `IsOpenHour`, `DefaultPolicy` 9·21 |
| `backend/internal/domain/policy_test.go` | 경계 표(12행) · 승격 표(5행) · 오프바이원 잠금 |
| `backend/internal/api/service_center_hours_test.go` | (신규) 기본값·회원 가시성·양방향 머지·자정 왕복·거부 표·403·라우터 |
| `backend/internal/store/conformance_test.go` | (신규 케이스) `PolicyHoursPromotedOnRead` — Memory·Firestore 동일 규약 |

**F2 — 사진 업로드**

| 파일 | 내용 |
|---|---|
| `backend/internal/api/provision.go` | `MediaUploader` 인터페이스, `ErrUploadUnavailable`, `unconfiguredUploader`, `firebaseMediaUploader`(다운로드 토큰), `Authenticator.MediaUploader`, `randomHex` |
| `backend/internal/api/service_staff_photo.go` | (신규) 형식 명세·완결성 함수·`decodeStaffPhoto`·`staffPhotoObjectPath`·`UploadStaffPhoto`·best-effort 삭제 |
| `backend/internal/api/handlers_staff.go` | `UploadStaffPhoto` 핸들러(4MiB 전용 상한) |
| `backend/internal/api/router.go` | `POST /v1/staff/{uid}/photo` |
| `backend/internal/api/service.go` | `uploader` 필드 · 기본값 503 구현 · `WithMediaUploader` |
| `backend/internal/api/util.go` | `ErrUploadUnavailable` → 503 매핑 |
| `backend/internal/api/service_staff_photo_test.go` | (신규) 픽스처(PNG/JPEG/최소 VP8L WebP/RIFF-not-WebP/2MB 초과) + 33 케이스 |
| `backend/internal/api/hookstore_test.go` | `SaveStaff` 래핑(찢어진 쓰기 재현) |
| `backend/cmd/server/main.go` · `internal/config/config.go` | 업로더 주입 · `STORAGE_BUCKET` 의미 갱신 |
| `backend/go.mod` · `go.sum` | `golang.org/x/image v0.45.0` |

**문서**: `docs/API계약_v1.md`(v2.24 · v2.25 + StaffProfile·스태프 라우트 표 갱신) ·
`backend/README.md`(라우트·배포 env 표·Storage 절·갭 목록) · `backend/.env.example`(`STORAGE_BUCKET` 신설)

**미변경(의도)**: `storage.rules` — `staff/photos/**` 전면 차단이 그대로 옳다. Admin SDK는
규칙을 지나지 않고, 클라이언트는 토큰 URL로만 읽는다(규칙 주석의 설계 그대로).

## 검증

```
go build ./...            OK
go vet ./...              OK
go test -count=1 ./...    OK — 584 PASS / 0 FAIL(서브테스트 포함)
go test -race ./internal/api/   OK
에뮬레이터 conformance     OK (firebase emulators:exec, Firestore 15.7s — 신규
                           PolicyHoursPromotedOnRead 포함 전 케이스)
```

**뮤테이션 패스 — 35개 주입, 33 kill / 2 equivalent(증명 첨부).**

F1(13): Validate 전체·`>=`→`>`·상하한 4종·부재 판정 `&&`→`||`·승격 제거·Normalize 호출 제거·
`SlotHours` 오프바이원·`IsOpenHour` 오프바이원·기본값 9→8·21→22 → **전부 kill**.

F2(19): owner 가드·uid 경로 주입 가드·content_type 화이트리스트·빈 image·매직바이트·완결성·
2MB 상한·치수·PNG IEND·JPEG EOI·WebP RIFF 길이·WebP 시그니처·교체 self 비교·옛 파일 삭제·
접두 가드·호스트 검사·저장 실패 정리·없는 스태프 차단·파라미터 접기 → **전부 kill**.

주입(3): 기본 업로더 조용한 성공·`MediaUploader` 버킷 분기·`WithMediaUploader` nil 가드 → **kill**.

**살아남은 2개는 증명 가능한 equivalent mutant**(조건식의 중복 절 — 지우지 않고 남긴 이유는
그 조건이 계약 `0 <= open < close <= 23`을 글자 그대로 읽히게 하기 때문):

- `CloseHour < 0` 절 제거: 통과하려면 `open >= 0 ∧ open < close`인데 `close < 0`이면
  `open < close < 0`이 되어 `open >= 0`과 모순. 단독 원인으로 도달 불가.
- `OpenHour > 23` 절 제거: 통과하려면 `open < close ∧ close <= 23`인데 `open > 23`이면
  `close > 24 > 23`이 되어 모순. 역시 도달 불가.

**1차 패스에서 살아남았다가 테스트를 보강해 죽인 4개**(초기 5 survive → 최종 0 real survive):
uid 가드(404가 아닌 **400**을 단언하도록 교정) · 교체 self 비교(비교 대상을 생성 경로에서
**반환 URL의 경로**로 바꿔 결정적으로 재현 가능하게 만든 뒤 테스트 추가) · 저장 실패 정리
(`hookStore.SaveStaff` 래핑으로 찢어진 쓰기 재현) · WebP 시그니처(RIFF지만 WebP가 아닌 픽스처 추가).
`WithMediaUploader` nil 가드도 테스트를 더해 죽였다.

## 후속 작업

- **어드민·앱이 배포돼야 사용자에게 닿는다.** 특히 회원앱은 `booking_rules.dart`에 09~21을
  박은 빌드가 나가 있어, 대표가 운영시간을 바꿔도 **스토어 배포 전까지 회원 화면은 09~21이다**
  (어드민에는 즉시 반영되므로 대표는 바뀐 것처럼 본다 — 그 어긋남을 계약 v2.24에 명시했다).
- **스태프 사진 파기 경로 없음(범위 밖, 확인만).** 퇴사는 소프트 전이라 프로필·파일이 남는 게
  옳다(복직이 그대로 되살린다). 스태프를 **영구 삭제하는 경로가 서버에 아예 없어** "지워진
  스태프의 사진이 남는" 상태도 아직 없다. 그 경로가 생기는 날 사진 파기를 함께 정해야 하고,
  `staff/photos/` 접두를 훑는 reconcile(체형사진 `POST /v1/body-photos/reconcile`의 스태프판)도
  그때의 과제다.
- **교체 삭제는 best-effort다.** 삭제가 실패한 옛 오브젝트를 찾을 수단이 없다(위 reconcile 부재와
  같은 구멍). 로그에는 남는다.
- **`GET /v1/slots`는 여전히 예약 있는 시간대만 반환한다.** 이제 영업시간 모델이 생겼으니
  서버가 빈 슬롯을 합성할 근거는 있다 — 응답 크기·캐시 정책을 함께 정하면 옮길 수 있다.
- **운영시간 강제는 열지 않았다**(결정 3). 열려면 기존 예약의 유예 규칙을 먼저 정해야 한다.
- `.env.example`에 `STORAGE_BUCKET`이 **그동안 없었다**(v2.11부터 쓰였는데). 이번에 추가했으나,
  운영 Cloud Run에 실제로 설정돼 있는지는 배포 담당이 확인해야 한다 — 없으면 업로드가 503이다.

## 참조

- `docs/API계약_v1.md` **v2.24**(운영시간) · **v2.25**(사진 업로드)
- P05(트레이너 프로필 v1.6 — `photo_url`과 "업로드는 Storage 트랙 후속" 예고)
- P22(`MediaPurger` — Admin SDK 파기 경계, 조용한 no-op의 대가)
- P44(서명 PNG 검증 — IEND 완결성 교훈)
- P46(홀딩 상한 `0 = 부재` 규약 — 이번에 **의도적으로 다르게** 간 자리)
- `storage.rules:88-95`(예약돼 있던 설계)
