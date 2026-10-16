# 라이즈 컨디셔닝 백엔드 (Go)

PT 센터 운영 SaaS "라이즈 컨디셔닝"의 백엔드 API 서버. 회원 → 회원권(세션) → 예약 → 체크인 →
정산으로 이어지는 코어 루프를 다룬다. 설계 근거는 `../PT데스크_설계_00_제품정의_자문자답_2026-08-14.md`
(§4 도메인, §10 결정로그 P1~P20)와 `../PT데스크_설계_03_라이즈_v1확정_DB백엔드_2026-08-14.md`
(P33~P48: 슬롯3팀·역할·홀딩·고정스케줄·체크인·가입매칭). API 계약의 단일 진실은
`../docs/API계약_v1.md` — 필드명·엔드포인트가 여기와 다르면 계약 문서가 맞다.

## 스택

| 역할 | 선택 | 근거 |
|---|---|---|
| 언어/런타임 | Go 1.26 | 스케일투제로 콜드스타트·단일 바이너리(와드샷 백엔드와 동일 근거) |
| 라우팅 | chi v5 | net/http 100% 호환·미들웨어·zero dep |
| DB | Firestore(+인메모리 개발) | 예약 원자성=트랜잭션, 설계03 §11 스키마 |
| 인증 | Firebase Auth(ID 토큰) + dev 헤더 폴백 | 로컬 개발은 키 없이 즉시 구동 |

## 아키텍처(클린 아키텍처)

```
cmd/server         부트스트랩·DI·graceful shutdown
internal/
  domain/          순수 stdlib(프레임워크 0) — 회원권 원장·환불계산·예약규칙·홈워크배정·체크인시간창
                   골든값 테이블 테스트로 교차검증(각 *_test.go)
  store/           Store 인터페이스 뒤 Firestore(실연동)/Memory(개발). BookAtomic이 슬롯 원자성을 강제
  api/             chi 라우터·Firebase/dev 인증·역할 스코프·서비스 오케스트레이션·핸들러
  config/          환경변수
```

의존 방향: `api → {store, domain}`. domain은 아무것도 모른다(표준 라이브러리만) → SDK 없이
테스트·이식 자유. Store 인터페이스가 Firestore·Memory 구현을 감춘다(와드샷 패턴 재사용).

## 설치

```bash
cd ptdesk/backend
go mod tidy      # 최초 1회: chi·firebase-admin·firestore 의존성 고정(네트워크 필요, go.sum 생성)
```

## 실행

```bash
go run ./cmd/server     # 기본: 인메모리 스토어 + dev 헤더 인증(키·DB 없이 즉시 구동)
```

실행 모드는 환경변수로 스왑([.env.example](.env.example) 참고):

| 원함 | 설정 |
|---|---|
| 오프라인 개발(기본) | (기본) 인메모리 + dev 헤더 인증 |
| **데모 데이터 시딩(v1.4)** | `DEV_SEED=true` — 스태프 3·회원 5·패스·예약·홈워크·결제(미납)·계약·수업기록 시딩. 어드민 데모 uid `owner1`/`t1`/`t2`, 회원 앱 데모 uid `member1`(김민지). 인메모리 한정 |
| 실 DB | `USE_FIRESTORE=true GCP_PROJECT=...`(또는 `FIRESTORE_EMULATOR_HOST`) |
| 실 인증 | `FIREBASE_PROJECT=...` (Firebase Admin SDK가 Application Default Credentials로 인증) |

### 로컬 개발 인증(dev 헤더)

`FIREBASE_PROJECT`가 비어 있으면 모든 `/v1` 요청에 아래 헤더가 필요하다:

```
X-Dev-Uid: owner1
X-Dev-Role: owner        # owner|trainer|member
```

`curl` 예시:

```bash
curl -s http://localhost:8080/v1/me -H "X-Dev-Uid: owner1" -H "X-Dev-Role: owner"
```

## 테스트

```bash
go test ./...                    # 전체(도메인 골든값 + api 통합 테스트)
go test ./internal/domain/...    # domain은 외부 의존 0 → 오프라인으로 항상 통과해야 함
go test ./internal/api/... -v    # 서비스 오케스트레이션 통합 테스트(인메모리 스토어)
go test ./internal/domain/... -run TestRefundQuoteGolden -v
```

domain 패키지의 골든값(모두 `API계약_v1.md` "핵심 골든값" 문단과 설계03 §14 R10에서 그대로 가져옴):

- 환불: 1,000,000원·20회·7회사용·10% → per 50,000 / usage 350,000 / penalty 100,000 / **refund 550,000**
- 예약: 슬롯 용량 3 초과 거부, 동일 트레이너 중복 예약 거부
- 재등록률: 2/8 + 1/6 + 1/6 = 4/20 = 20%
- 홈워크: 부상 플래그 회원 자동 제외(my_members·center_notice), individual은 필터 미적용, 수동 포함 오버라이드
- 체크인: 예약 슬롯 시작 ±30분 시간창
- 홀딩 상한: 회원 셀프 홀딩 최대 2회·총 30일(정책값, 경계 30일=통과·31일=거부)

api 패키지의 통합 테스트는 감사 라운드마다 나온 버그들의 회귀를 고정한다 — 발급 직후 예약 성공
(잔여 스냅샷), 이중 complete 400, 노쇼 유예 1회 소진, 미연결 회원 403(스코프 우회 차단),
member 셀프 스코프 강제, consent 전이 시각, 부분 PUT 머지, 셀프 홀딩 상한, recurring 잔여 캡,
트레이너 center 통계 금액 제외, self_qr 체크인 등. 파일이 주제별로 나뉘어 있다:

| 파일 | 주제 | `func Test` |
|---|---|---|
| `internal/api/service_test.go` | 코어 루프 전반(P01~) | 60 |
| `internal/api/service_staff_test.go` | 직원 생애주기(v1.8·v2.0) | 22 |
| `internal/api/service_atomicity_test.go` | 트랜잭션·경합(v2.6) | 9 |
| `internal/api/service_recurring_hw_test.go` | 고정 스케줄·HW 스케줄(v2.3) | 8 |
| `internal/api/service_money_test.go` | 환불 기준액·발급 검증(v2.4) | 6 |
| `internal/api/service_scope_test.go` | 쓰기 경로 담당 경계(v2.5) | 4 |
| `internal/api/service_hwschedule_wiring_test.go` · `service_inbody_date_test.go` | 배선 회귀 | 1 + 1 |
| `internal/api/service_contract_test.go` | 전자계약 전이·경합(v2.15) | 10 |
| `internal/api/service_checkin_qr_test.go` | 데스크 QR 발급·재발급·누출 방지(v2.23) | 10 |
| `internal/api/hookstore_test.go` | 실패 주입용 훅 스토어(테스트 없음, 헬퍼) | 0 |

현재 총계(2026-08-30, P49 시점 재집계): **api 234 · domain 86 · store 9 · config 3 = 332**
(그중 1개는 아래 에뮬레이터 태그가 있어야 돈다). 위 표의 파일별 숫자는 각 파일이 만들어진
시점 것이라 이후 추가분을 반영하지 않는다 — 정확한 값은 `grep -c "^func Test"`. 종전 README가
적어 둔 "api 통합 34케이스"는 v1.5, "총계 182"는 v2.7 시점 숫자다.

### 두 스토어 공통 계약 스위트 (v2.6)

`Memory`와 `Firestore`는 **같은 인터페이스를 만족한다고 해서 같게 동작하지 않는다**. v2.6 감사에서
18개 프로브 중 13개에서 동작이 갈렸다(없는 ID Update가 Firestore에선 유령 문서 + 200, Memory에선
404 등). 드리프트를 막으려고 같은 테스트 함수를 두 구현에 돌리는 공통 스위트를 뒀다.

```bash
go test ./internal/store/       # 기본 = Memory 구현으로 스위트 실행
```

- 스위트 본체: `internal/store/conformance_test.go`(서브테스트 20종 — 유령 문서·Ledger 롤백·
  fresh 재검증·페널티 원장 동반 취소·잔여 예산·정렬·**동시 환불/홀딩/예약**, v2.15부터 계약
  전이 fresh 재검증·**동시 서명 vs 재발송**·환불 마감+무효화 원자성·**동시 계약 생성** 포함).
- **새 스토어 동사를 추가하면 이 스위트에 케이스를 함께 넣는다.**

경합 결함은 Memory에서 **재현되지 않는다**(전역 뮤텍스 하나라 경합 창이 나노초). `go test`가
전부 초록인데 프로덕션에서만 터지는 종류라, 에뮬레이터 러너를 별도 빌드 태그로 옵트인한다:

```bash
# 사전: JDK 21+ (firebase-tools 15가 그 아래를 거부한다)
export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"

firebase emulators:exec --only firestore --project demo-rize \
  --config testdata/firebase.json \
  'go test -tags firestore_emulator -count=1 ./internal/store/'
```

- 태그가 붙는 파일은 `internal/store/firestore_conformance_test.go` **하나뿐**이다
  (`//go:build firestore_emulator` — 저장소 전체에서 유일한 빌드 태그).
- `emulators:exec`가 자식 프로세스에 `FIRESTORE_EMULATOR_HOST`를 주입하고 SDK가 그걸 자동
  감지한다. 미설정이면 테스트가 스스로 `t.Skip`하므로 태그만 켜고 러너 없이 돌리면 조용히 건너뛴다.
- 에뮬레이터 설정은 `backend/testdata/firebase.json`(포트 8480, UI 끔, singleProjectMode).
  저장소 루트의 `firebase.json`과 **다른 파일**이다 — 루트 쪽은 Hosting·rules 배포용이라
  emulators 블록이 없다. 프로젝트 ID의 `demo-` 접두는 자격증명을 요구하지 않게 하는 관례다.
- **CI 잡은 아직 없다**(저장소에 `.github` 없음). 지금은 사람이 손으로 돌린다.

## API

전체 엔드포인트·JSON 필드명은 [`../docs/API계약_v1.md`](../docs/API계약_v1.md) 참고. 요약:

```
GET  /v1/me                                          POST /v1/join/match|confirm|request|approve
GET  /v1/join/requests                               (v1.1)
GET  /v1/members  POST /v1/members  PUT /v1/members/{id}  GET /v1/members/{id}/ledger
POST /v1/passes  GET /v1/passes(v1.1)  POST /v1/passes/{id}/hold|resume|refund-quote
GET  /v1/slots  POST /v1/bookings  GET /v1/bookings(v1.1)  DELETE /v1/bookings/{id}  POST /v1/bookings/{id}/complete|noshow
POST /v1/recurrings  DELETE /v1/recurrings/{id}  POST /v1/checkin
GET  /v1/homeworks  POST /v1/homeworks  POST /v1/hw-checks  GET /v1/hw-checks?hw_id=&member=&date=(v1.1·v1.2)
GET  /v1/stats  POST /v1/payments  GET /v1/payments(v1.1)  POST /v1/payments/{id}/installments/{i}/pay
GET  /v1/contracts(v1.1)  POST /v1/contracts(v1.1)  POST /v1/contracts/{id}/send(v1.1)
GET  /v1/body-photos  POST /v1/body-photos  GET /v1/inbody  POST /v1/inbody
GET  /v1/staff  POST /v1/staff(v1.8 초대·재고용)  POST /v1/staff/{uid}/offdays
PUT  /v1/staff/{uid}  POST /v1/staff/{uid}/transfer|deactivate|reactivate   (v2.0 생애주기)
GET  /v1/center(v1.1·v1.4 member 공개)  PUT /v1/center(v1.4 정책 편집)
GET  /v1/center/checkin-qr  POST /v1/center/checkin-qr/rotate   (v2.23 데스크 QR 발급, owner 전용)
GET  /v1/workout-logs  POST /v1/workout-logs        (v1.4 수업 기록)
GET  /v1/recurrings?include_expired=                 (v1.4 고정 스케줄 관리 · v2.3 만료 규칙 포함)
DELETE /v1/recurrings/{id}?keep_bookings=            (v2.3: 204 → 200 {cancelled, kept})
POST /v1/passes/{id}/refund                          (v1.4 환불 실행)
POST /v1/contracts/{id}/sign                         (v1.4 회원 자체서명)
PUT  /v1/staff/{uid}/profile                         (v1.6 트레이너 공개 프로필)
POST /v1/staff/{uid}/photo                           (v2.25 프로필 사진 업로드, owner 전용 — STORAGE_BUCKET 필수)
GET  /healthz  GET /health  ← Cloud Run(run.app)에서는 /health만 사용 — GFE가 /healthz를 가로챔(P06)
```

라우터에 실제로 등록된 `/v1` 라우트는 **71개**(2026-09-26, v2.37 기준 — 정확한 수는 `router.go`의
`v1` 클로저가 진실이다)이고, 전부 `/v1/*`과 `/api/v1/*` **양쪽에 미러 마운트**된다(이유는 아래 "배포" 절).
위 목록은 그 미러를 접어서 적은 것이다.

**v1.4 기능 패치(2026-08-22, 기능 갭 리서치·UX 여정 검수 — 계약 문서 "## v1.4 기능 패치" 섹션)**:
코어 루프의 마지막 구멍(수업기록)과 owner 여정 데드엔드 4곳을 채웠다 — WorkoutLog 엔티티+
목록/생성, 고정 스케줄 목록(GET /v1/recurrings), 운영 정책 편집(PUT /v1/center, 범위 검증 —
member도 GET은 가능하되 매출 목표 제외), 환불 실행(원장 refund 마감+refunded 전이, owner 전용),
계약 자체서명(sent→signed, member 본인), Stats에 sessions(트레이너 정산 근거)·미수금
(unpaid_total/count, owner 전용), 예약 생성 시 트레이너 휴무일 거부, DEV_SEED 데모 시딩.
전부 api 통합 테스트(총 26케이스)와 실서버 E2E로 검증됨(work_log/P02).

**v1.4.1 검수 보완(2026-08-22, P03 새눈 검수 — 계약 "v1.4.1" 절)**: 환불 실행이 미래 confirmed
예약을 무차감 일괄 취소(원장 음수·정산 오집계·슬롯 점유 방지, complete/noshow에 refunded 패스
이중 방어선), used는 원장 파생값 검증(빈 바디 전액 환불 견적 버그 수정), PUT /v1/center 머지
시맨틱(누락 필드 초기화 방지), WorkoutLog 날짜 형식 검증(정렬·필터 오염 방지), refunded 패스
홀딩/재개 차단, recurring의 지난 시각 회차 생성 금지, by_trainer에서 owner 행 제외, 재발송↔서명
경합 가드, decodeJSON 다중 문서 거부. 회귀 테스트 4개 추가(api 통합 총 30케이스).
잔여(당시 문서화된 LOW)의 현재 상태: **RefundPass의 마감은 v2.6에서 트랜잭션화됐고**
(`UpdatePassWithLedger`), **`SendContract`·`SignContract`는 v2.15에서 트랜잭션화됐다**
(`TransitionContract` — P37. v1.4.1의 재발송↔서명 경합 가드는 저장 직전 재확인이라 창을
좁혔을 뿐이었고, 이제 판정 자체가 트랜잭션 안이다). `PayInstallment`는 **여전히 열려 있다**
(아래 갭 목록). 휴무일 소급 등록 시 기존 confirmed 예약 스윕 없음도 그대로다(고정 스케줄
해제는 v2.3에서 스윕이 생겼지만 휴무일은 별개 경로다). `signer_ip`는 신뢰 프록시 전제
(v1.5에서 XFF 마지막 홉으로 좁힘).

**v1.5 정산·정합 패치(2026-08-22, 예약·결제·계약 도메인 수직 감사 — 계약 "v1.5" 절, work_log/P04)**:
환불이 세 도메인을 관통하는 한 사건이 되도록 재구성 — 실수납(Σ납부 회차) 기준 정산(분할 미완납
패스의 과지급 차단, RefundResult.paid_sum), 계약 요율 스냅샷(penalty_rate — 정책 변경 소급 차단),
미납 회차 청구 종결(waived_at → 유령 미수금 제거), 미서명 계약 자동 무효(voided), 미래 예약 취소와
합쳐 4종 부수효과 일원화. 미수금을 연체(due 경과)로 재정의(+upcoming_total), 매출은 순매출(환불
제외). CreatePayment 검증 게이트 7종·납부 멱등·회원 동시 1팀 규칙·스태프 무차감 취소(?waive=true)·
tap 체크인 가드·recurring 검증(hour/days)·슬롯 최소노출(member)·빈 슬롯 용량 갱신·계약 중복 차단·
first_sent_at·signer_ip XFF 마지막 홉. 도메인 감사 3팀의 실증(스크래치 사본 재현 테스트) 기반이며
회귀 테스트로 고정(api 통합 34케이스 + 정산 골든: 완납 550,000 / 분할 50만 수납 시 50,000).

v1.1 정합 패치(2026-08, `../docs/API계약_v1.md` "## v1.1 정합 패치" 섹션)가 위 (v1.1) 표시 엔드포인트와
`Contract` 엔티티, `Slot.teams[].status`, `GET /v1/members`의 임베드 `passes:[]`를 모두 반영했다.
`POST /v1/passes`는 이제 발급과 동시에 `Contract`를 `status=sent`로 자동 생성한다(하단 확정 플로우).

**v1.2 정합 패치(2026-08-17, 3계층 교차검증 — 계약 문서 "## v1.2 정합 패치" 섹션)** 반영 요약:

- **회원 앱 셀프서비스 허용**: member가 `GET /v1/members`(본인 1건=내 프로필), `PUT /v1/members/{id}`
  (본인 consent만 — 전이 시각은 서버 기록), `hold/resume`(정책 상한: 기본 2회·총 30일), `refund-quote`를
  호출할 수 있다. 종전엔 전부 403이라 회원 앱 마이 탭이 전멸이었다.
- **스코프 우회 차단**: member인데 member_id 미연결(가입 매칭 전)이면 목록 엔드포인트가 403 —
  빈 스코프가 필터를 지워 센터 전체가 노출되던 결함 수정.
- **PUT /v1/members/{id} = 머지 시맨틱**: 보낸 필드만 갱신(부분 PUT이 app_linked·last_visit_at을 지우지 않음).
- **예약 규칙 보강**: 발급 직후 예약 실패(잔여 스냅샷 0) 수정 — 잔여는 항상 원장 재계산. 슬롯 날짜도
  유효기간·홀딩과 대조. complete/noshow는 confirmed에서만(이중 차감 방지). 노쇼 유예는 waived 이력도
  소진으로 집계(무한 유예 수정). recurring도 동일 검증 + 잔여 캡.
- **stats**: trainer의 `scope=center` 허용하되 금액(monthly/ytd/target)·by_trainer 제외(P45 비교는 비율만).
- **에러 메시지**: 사용자향 한국어로 통일(내부 마커·Go 원문 제거), 500은 로그로만 원문 기록.

**v1.3 정합 패치(2026-08-18, 2라운드 로직 재검증 — 계약 문서 "## v1.3 정합 패치" 섹션)** 반영 요약:

- **보안**: `join/confirm`에 전화번호 재대조 필수(유출 member_id만으로 타인 레코드 연결 불가),
  member의 홈워크 응답에서 대상/제외 명단 제거 + 부상 제외 회원에겐 공지형도 미배달,
  `DELETE /bookings/{id}` 상태 가드(재취소 이중 차감 차단 — 스토어 트랜잭션 내부 재검증 포함),
  member 셀프 홀딩의 시간축 검증(과거/유효기간 밖/겹침 거부 — 공짜 연장·만료 부활 차단),
  stats의 target(매출 목표)은 scope 무관 owner 전용.
- **예약 시간축 확정**: 상태·잔여는 지금 기준, 날짜 적합성은 슬롯 기준 — 지난 시간대 거부,
  미래 시작 패스의 유효기간 내 선예약 허용(재등록 플로우), 홀딩 구간 슬롯 거부.
  `Booking.status=waitlist`는 예약어로만 유지(알림 인프라 없는 자동 승격은 노쇼 함정 — 후속).
- **직렬화·정책 규약**: 배열 필드 항상 `[]`(null 금지 — 어드민 크래시 방지), Policy 홀딩 상한
  0=부재→기본값 승격·-1=무제한(v1.2 이전 Firestore 문서에서 상한이 풀리는 것 방지),
  consent 전이 시각 항상 서버 기록(스태프 PUT 포함), 체크인 기록 예약당 1건 멱등 upsert,
  JSON 파싱 에러 한국어화, offdays 날짜 형식 검증, CreatePass의 member 실존 검증.

빠른 확인:

```bash
go run ./cmd/server &
curl -s -X POST http://localhost:8080/v1/members \
  -H "X-Dev-Uid: owner1" -H "X-Dev-Role: owner" -H "Content-Type: application/json" \
  -d '{"name":"김민지","phone":"010-1234-5678","channel":"워크인","trainer_id":"t1","status":"active"}' | jq .
```

**v1.9 보안 패치(2026-08-22, P08 새눈 감사 — 계약 "v1.9" 절)**: 가입 경로가 뚫려 있었다.
v1.7의 "토큰에 번호가 **있으면** 진실" 조건부 규칙이, 번호 없는 토큰(이메일 계정)을 바디 폴백으로
흘려보내 **번호만 알면 남의 회원 계정에 연결**할 수 있었다(자체 가입 허용 + 공개 웹 API 키).
조건부 → 필수로 강화. 더불어 join/confirm·approve가 호출자 UserIndex를 무조건 member로 덮어써
**대표가 한 번 호출하면 센터가 영구히 잠기던** 경로를 차단, 승인 멱등 가드, 연결 전 응답에서
건강정보(부상 메모) 제거, 권한 검사를 데이터 조회보다 앞으로(존재 오라클 차단).
프로덕션에서 공격 시나리오를 재현해 6/6 차단 확인.

**v2.0 직원 생애주기(2026-08-23, P08 — 계약 "v2.0" 절)**: `Staff.status`(부재=active 승격) +
정정·이관·퇴사·재입사 4 엔드포인트. 퇴사는 담당 이관을 **선행 요구**하고(막는 이유를 blockers로
반환), 이관은 패스마다 원장에 `transfer`(delta 0)를 남긴다 — v1부터 선언만 돼 있던 예약된 사유값의
첫 사용이다. 락아웃 3중 가드(자기 자신·마지막 활성 owner·강등 우회). 같은 패치에서 **체형사진·
인바디 쓰기에 권한 검사가 없던 구멍**(읽기는 막혀 있어 비대칭)과 미연결 회원의 주인 없는 홈워크
체크도 함께 막았다. 프로덕션 전 여정 E2E 24/24 통과.

**v2.1 비율 분모·차단 사유(2026-08-23, P09 — 계약 "v2.1" 절)**: `Stats`에 `noshow_d`·`hw_d`와
`by_trainer[]`의 같은 분모를 추가했다. 비율만 주고 분모를 감추면 클라이언트가 "성과 0"과 "모수
없음"을 가를 수 없어, 이번 기간 수업 0건인 코치가 "노쇼율 0.0%"로 **최우수처럼** 표시됐다.
`omitempty`를 일부러 붙이지 않는다 — 0은 정보이고, 필드가 사라지면 구버전 서버와 구별되지 않는다.
같은 패치에서 퇴사 차단의 `blockers.bookings`를 `{id, slot_key}` 객체로 바꾸고(어드민이 이유를
사람 눈으로 읽으려 예약을 한 번 더 조회하던 왕복 제거), `POST /v1/passes`·`/v1/members`·
`PUT /v1/members/{id}`의 `trainer_id`에 실존·재직 검증을 걸었다(v2.0이 예약·고정스케줄만 막아
발급 경로로 루프가 다시 열려 있었다). 목록 기본 정렬은 두 스토어 공통 **문서 ID 오름차순**.

**v2.2 `/v1/me` 표시 이름(2026-08-23, P10 — 계약 "v2.2" 절)**: 응답에 `name`(omitempty)을 더했다.
staff면 Staff.name, 연결된 member면 Member.name. **best-effort** — 이름 조회가 실패해도 이 호출은
성공한다. 모든 클라이언트가 가장 먼저 부르는 부트스트랩 엔드포인트라, 표시용 이름 하나 때문에
"앱이 온보딩을 시작 못 하고 어드민이 로그인 화면에 갇히는" 위험을 지지 않는다.

**v2.3 고정 스케줄·Home Work 스케줄(2026-08-23, P12 — 계약 "v2.3" 절)**: 고정 스케줄의 "잔여 이내"
보장이 **규칙 단위**라 규칙을 두 번 만들면 무력화됐고(잔여 10회 → confirmed 21건), 규칙을 지워도
그 규칙이 만든 예약은 남았다. 캡 기준을 "이 요청이 만든 건수"에서 **이 패스의 살아있는 confirmed
예약 총량**으로 옮겼다(`budget = remaining − open`, `countOpenPassBookings`) — 잔여는 완료 시점
차감(P4)이라 예약이 늘어도 줄지 않는 값이어서 뺄셈 없이는 캡이 성립하지 않는다. `until` 과거
날짜 400, `GET /v1/recurrings?include_expired=true`(숨기기만 하면 UI에서 지울 수 없다),
`DELETE /v1/recurrings/{id}`는 **204 → 200 `{cancelled, kept}`** + 그 규칙이 만든 **미래
confirmed 예약을 무차감 취소**(`CancelAtomic(..., entry=nil)` — 노쇼 유예를 소진하지 않는다.
`?keep_bookings=true`로 옵트아웃). 그리고 `Homework.schedule`은 **판정하는 코드가 어디에도 없어**
저장만 되고 있었다 — `domain.HwSchedule`(순수 도메인 타입, `internal/domain/homework.go`)의
`IsActiveOn`/`IsEndedOn`/`ValidateHwSchedule`을 신설해 목록 필터·통계 분모·쓰기 검증에 물렸다.
판정 규칙은 **이미 출시된 회원 앱의 순수 함수(`homework_schedule_rules.dart`)와 동일**하다.

**v2.4 돈 무결성(2026-08-23, P12 — 계약 "v2.4" 절)**: 서버가 "이 거래로 실제 오간 돈이 얼마인지"를
스스로 판정하지 않고 클라이언트 기록을 그대로 믿었다. 실측: 550,000원 회원권에 결제를 한 번 더
기록하면 환불 견적 **5,445,000원**, 반대로 일시불(회차 미기재)로 기록하면 **0원 환불 + refunded
확정(복구 API 없음)** — **정확히 기록할수록 손해가 커지는** 역방향 인센티브였다. 원장은
append-only(P3)라 잘못 박힌 기록을 지울 수 없으므로 **쓰기 게이트와 읽기 캡을 이중으로** 건다:
`CreatePass`의 `total_sessions >= 1`·`paid_amount >= 0`(0은 허용 — 무료 체험권은 실제 영업 조건),
`CreatePayment`의 Σtotal ≤ `pass.paid_amount` **합계 상한**(건수 제한이 아니라 카드+현금 분할은
통과), `installments[].paid_at` 미래 시각 400(시계 오차 5분), 일시불(installments 생략) = 실수납
`total`로 확정(`Payment.PaidSum` — 불변식 `PaidSum + Outstanding == Total`), 환불 정산식
`refund = max(min(실수납, 계약가) − usage − penalty, 0)`. 캡이 걸린 사건은 서버 로그에 남긴다.

**v2.5 쓰기 경로 담당 경계(2026-08-23, P12 — 계약 "v2.5" 절)**: 읽기 경로는 여러 라운드 감사를
거쳐 촘촘한데 **쓰기 4곳에 스코프 검사 자체가 없었다**(전부 curl 실측으로 재현). ①
`POST /v1/workout-logs`는 `booking_id` 없이 오면 `checkMemberScope` — 종전엔 booking_id를 생략하는
것만으로 교차검증 전체가 비활성화됐다. ② `POST /v1/homeworks`는 후보 집합과 부상 맵을 **같은
출처(pool)**에서 뽑고 `my_members` subset을 담당과 교집합 처리. ③ `POST /v1/hw-checks`는 배정
실존·배달 대상·`done` 길이 검증 + 스태프 대행은 담당 회원만(hw_rate는 정산·평가 지표다).
④ `POST /v1/checkin` tap은 `p.IsTrainer() && booking.TrainerID != p.UID`면 **403** —
complete/noshow와 같은 규칙이고, 상태 검사보다 **앞에** 둬서 400/200 차이로 예약 상태를 캐지
못하게 한다.

> ⚠ **운영 영향(데스크 운영 방식)**: tap 체크인이 **담당 예약으로 좁혀졌다.** 데스크 태블릿을
> 트레이너 계정으로 로그인해 쓰고 있었다면, 그 계정으로는 **다른 코치의 회원을 체크인할 수 없다**
> (403). 데스크는 **대표(owner) 계정으로 운영**해야 한다. owner는 이 분기를 타지 않아 센터 전
> 예약을 체크인할 수 있다. 회귀 가드는 `TestCheckinTapRespectsTrainerScope`.

**v2.6 원자성(2026-08-23, P13 — 계약 "v2.6" 절)**: 원자성이 제대로 된 곳은 **예약 상태 전이
하나뿐**이었고, 발급·환불·홀딩은 스토어 트랜잭션 **밖에서** 2~3개의 독립 호출로 쪼개져 있었다.
에뮬레이터 실측으로 재현한 것: 동시 환불 2건이 **둘 다 200**(495,000원 두 번 승인) · 발급 3회가
**HTTP 500 세 번인데 실제로는 60회 지급** · 동시 홀딩 5건 전부 200인데 패스엔 1건·원장엔 5건 ·
잔여 2회 패스에 4건 예약 후 완료 → **잔여 −2**. 스토어 인터페이스에 트랜잭션 동사 6개를 뒀다:
`IssuePass` · `UpdatePassWithLedger`(환불·홀딩·재개·이관 4갈래 공유) · `BookAtomic` ·
`CancelAtomic` · `SetBookingStatusWithLedger` · `ReassignBookingTrainer`. `PassMutator`에는
**두 제약이 인터페이스에 못박혀 있다** — mutate는 순수해야 하고(트랜잭션이 재시도된다),
mutate 안에서 Store를 다시 부르면 안 된다(Memory 스토어 교착). 정책 같은 외부 값은 트랜잭션
밖에서 미리 읽어 캡처한다. 계약 변경으로는 예약 생성의 잔여 캡(`domain.ErrNoSessionsLeft` —
remaining > 0이어도 거부될 수 있다), 홀딩 중복 400, 동시 환불 중 1건만 200, `GET /v1/passes`
정렬을 `valid_from` 오름차순(동률 시 id)으로 확정, Update 계열의 없는 ID는 **404**
(종전 Firestore는 `.Set()` upsert라 **유령 문서를 만들고 200**을 돌려줬다).

**v2.7 센터 정책 집행 정합(2026-08-23, P14 — 계약 "v2.7" 절)**: 정책 화면은 대표가 돈과 약관을
정하는 자리인데 **저장한 값과 집행되는 값이 달랐다.** `Policy`는 위약금율 0~1을 전부 허용하는데
`RefundQuote`가 10%로 하드 캡해서, 30%를 저장하면 어드민 푸터·회원 앱 `GET /v1/center`·**계약서
스냅샷(회원이 서명하는 조항)** 셋이 전부 30%를 말하고 실제 공제만 10%였다. 캡을 남기고 경고만
붙이는 대신 **상한을 정책으로 끌어올렸다**: `PUT /v1/center`의 `penalty_rate` 유효 범위 `0~0.1`
(초과 400), `GET /v1/center`는 검증을 지나지 않은 구문서 값을 **읽는 자리에서 접는다**
(`Policy.Normalize`/`EffectivePenaltyRate` — 저장 시점에 접으면 머지 PUT이 초과값을 이어받아
용량 하나만 바꿔도 400이 나는 잠금이 생긴다). `RefundQuote`의 런타임 캡은 **유지**한다 —
이미 30%로 서명된 계약이 실재할 수 있다. 정책 변경의 소급 여부도 명문화했다: 취소 컷오프·슬롯
용량·통계 임계값은 **즉시·소급**(취소 시점에 정책을 새로 읽는다), 위약금율은 **계약 스냅샷**
(`Contract.penalty_rate`, 발급 시점 값 고정). 홀딩 상한(`max_holds_per_pass`/`max_hold_total_days`)은
**회원 셀프 홀딩에만** 걸린다 — owner·trainer가 어드민에서 거는 홀딩은 정책을 로드하지 않는다.

## 배포(Cloud Run) — P06 실배포 완료

운영 서비스: **`rize-api`** / 리전 **asia-northeast3(서울)** / 프로젝트 **rize-218c1**
URL: `https://rize-api-773077624928.asia-northeast3.run.app`

재배포는 저장소 루트에서(빌드팩이 모듈 루트를 `backend`로, 엔트리를 `cmd/server`로 잡는다):

```bash
gcloud run deploy rize-api --source backend --region asia-northeast3 --project rize-218c1 \
  --set-build-env-vars GOOGLE_BUILDABLE=./cmd/server
```

현재 설정된 환경변수(`--set-env-vars`로 최초 배포 시 지정, 이후 유지):

| 키 | 값 | 비고 |
|---|---|---|
| `USE_FIRESTORE` | `true` | Firestore 스토어 사용 |
| `GCP_PROJECT` · `FIREBASE_PROJECT` | `rize-218c1` | 둘 다 필요 — 후자가 있으면 dev 헤더는 무시된다 |
| `DEFAULT_CENTER_ID` | `rise` | 센터 부트스트랩 |
| ~~`CHECKIN_QR_TOKEN`~~ | — | **v2.23에서 삭제. 이 변수를 설정하라는 종전 안내는 이제 틀렸다.** 아래 절 참고 |
| `STORAGE_BUCKET` | `rize-218c1.firebasestorage.app` | **v2.25부터 업로드에 필수.** 두 경로가 쓴다 — 회원탈퇴 시 체형사진 원본 파기(v2.11, 없으면 no-op+기동 경고)와 트레이너 프로필 사진 업로드(v2.25, **없으면 그 엔드포인트가 503**). 파기는 없어도 서비스가 돌지만 업로드는 안 돈다 |
| `CORS_ORIGINS` | `http://localhost:5174` | 로컬 개발 어드민용. 운영 어드민은 Firebase Hosting에서 같은 오리진의 `/api`로 붙어 **CORS가 발생하지 않는다**(P07) |

**`USE_FIRESTORE=true`인데 `FIREBASE_PROJECT`가 비어 있으면 기동을 거부한다**(P08). 그 조합은 실
DB에 붙은 채 dev 헤더 인증으로 뜨는 것이라, 헤더만 보내면 누구나 owner가 된다 — 종전엔 경고만
찍고 기동했다. 검증은 `config.Config.Validate()`(테스트 있음).

### 데스크 체크인 QR — 환경변수가 아니다 (v2.23, P49)

**종전 안내(`CHECKIN_QR_TOKEN`을 설정하고 그 값을 어드민에 손으로 입력)는 폐기됐다.** 그 구조는
대표가 **알 수 없는 값을 옮겨 적어야** 하는 요구였다(값은 Cloud Run 설정 안에만 있고 대표는 배포
설정을 볼 수 없다). 지금은 서버가 만들어 서버가 보관한다:

```
GET  /v1/center/checkin-qr          (owner 전용) → {issued, token, issued_at}
POST /v1/center/checkin-qr/rotate   (owner 전용) → 새 토큰 발급(바디 없음)
```

대표는 어드민 설정에서 **발급 버튼만** 누르고 QR을 인쇄한다. 토큰은 `centers/{id}` 문서의
`checkin_qr` 절에 저장되고(머지 쓰기 — Policy·Business·Facility 불침범), 32자 URL-safe
base64(crypto/rand)다. **회원·트레이너가 보는 어떤 응답에도 실리지 않는다** — 아는 회원은 집에서
출석을 찍는다. `GET /v1/center`(5키)와 무인증 `GET /v1/public/business`에 없다는 것을 키 집합
테스트가 고정한다.

**재발급은 직전 인쇄물을 즉시 무효로 만든다.** 토큰이 샜을 때 대표가 스스로 되돌릴 유일한
수단이고, 어드민이 누르기 전에 경고하는 근거다.

`CHECKIN_QR_TOKEN` 환경변수와 그 기동 검증(운영에서 저장소 기본값이면 거부)은 **함께 삭제됐다**.
그 검증은 "미설정 → 저장소의 공개 기본값으로 승격"이라는 fail-open을 막던 것인데, 읽는 코드가
사라져 막을 대상 자체가 없어졌다. env를 폴백으로 남기지 않은 이유는 **재발급이 이전 토큰을
무효로 만들지 못하게 되기 때문**이다 — 유출된 env 토큰이 영원히 통과하는데 화면에는 안 보인다.
fail-closed는 기동 검증에서 **요청 경로로** 내려갔다: 미발급 센터의 self_qr은 400 +
"데스크 체크인 QR이 아직 발급되지 않았습니다 — 어드민 설정에서 발급해 주세요".

배포 후 프로덕션은 **미발급 상태**이므로(종전 env 토큰은 DB로 이관되지 않는다) 대표가 한 번
발급해야 셀프 체크인이 열린다. 기존 Cloud Run에 `CHECKIN_QR_TOKEN`이 남아 있어도 무해하다
(읽히지 않고 기동을 막지도 않는다) — 지우는 것이 권고지만 배포 순서에 걸리지 않는다.
로컬은 `DEV_SEED=true`가 고정 토큰 `rise-desk-checkin`을 심는다(앱 dart-define 기본값과 동일,
인메모리 전용).

Firestore 서비스 계정에 `roles/datastore.user` 권한이 필요하다. `FIREBASE_PROJECT`를 설정하면
Firebase Admin SDK가 Cloud Run의 서비스 계정으로 Application Default Credentials를 자동 사용한다
(별도 키 파일 불필요). 스태프 초대·퇴사는 Admin SDK로 Firebase 계정을 만들고 잠그므로 서비스
계정에 Firebase Auth 관리 권한이 필요하다(기본 compute SA의 Editor로 충족).

**복합 인덱스는 필요 없다**(P06 실측). 이 코드의 Firestore 쿼리는 전부 (a) 동등 필터이거나
(b) 같은 필드의 범위 필터(`slot_key >= lo AND <= hi`)이고, `OrderBy`를 쓰지 않는다 — 정렬은
전부 Go에서 한다. 자동 생성되는 단일 필드 인덱스로 충분하다. 나중에 `OrderBy`나 서로 다른
필드의 부등호를 추가하면 그때 복합 인덱스가 필요해진다(Firestore가 콘솔 링크로 안내한다).

**헬스체크는 `/health`를 쓴다.** run.app 도메인에서는 Google 프론트엔드가 `/healthz`를 가로채
컨테이너까지 도달하지 않는다(실측: 앱의 404는 `text/plain`, `/healthz`의 404는 구글 HTML 페이지).
`/healthz`는 로컬·다른 호스팅용으로 그대로 남겨 두었다. Cloud Monitoring의 uptime check가
5분 주기로 3개 리전에서 `/health`를 확인하고, 실패 시 알림 정책이 메일을 보낸다(P07).

**API는 `/v1/*` 과 `/api/v1/*` 양쪽에 붙어 있다**(P07, `router.go`의 미러 마운트). 어드민이
Firebase Hosting에서 서비스되고 `/api/**`가 이 서비스로 리라이트되는데 Hosting이 경로 접두사를
벗겨주지 못하기 때문이다. 덕분에 어드민은 API와 같은 오리진을 쓰게 되어 **CORS가 아예 발생하지
않고**, 개발(vite 프록시가 `/api`를 벗김)과 운영의 클라이언트 코드가 완전히 동일하다.
앱(Flutter)은 이 URL을 직접 부르므로 `/v1/*`을 쓴다. 회귀 가드는 `TestAPIPrefixMirror`.

Firestore 보안 규칙은 저장소 루트 `firestore.rules`가 소스 오브 트루스이며 **클라이언트 전면
차단**이다(모든 접근은 Admin SDK를 쓰는 이 백엔드를 경유 — Admin SDK는 규칙을 우회한다).

### Storage 버킷 — 파기는 선택, 업로드는 필수 (v2.25, P51)

`STORAGE_BUCKET`을 서버가 만지는 경로가 **두 개**이고, 미설정 시 동작이 정반대다.

```
파기(v2.11 회원탈퇴)        미설정 → 조용한 no-op + 기동 경고.  체형사진 업로드는 클라이언트
                            SDK가 하므로 이 값이 없어도 서비스 자체는 돈다.
업로드(v2.25 트레이너 사진)  미설정 → 그 엔드포인트가 **503**.   규칙이 클라이언트 쓰기를 막아
                            둔 경로라 서버만이 쓸 수 있다.
```

업로드가 no-op으로 떨어지지 않는 이유가 이 절의 요점이다: 조용히 성공하면 어드민은 "저장됨"을
보고 회원앱은 빈 아바타를 본다. 그 조용한 no-op이 실제로 버킷에 고아 50개를 남긴 사고의
모양이다(v2.15 reconcile이 그것을 치우려고 생겼다). 그래서 업로드는 실패를 말한다 —
`{"error":"사진 업로드 저장소가 설정되지 않았어요(관리자에게 STORAGE_BUCKET 설정을 요청해주세요)"}`.

**로컬 개발(`FIREBASE_PROJECT` 미설정, 인메모리)에서는 업로드가 항상 503이다.** Admin SDK 앱이
없어 Storage 클라이언트를 만들 수 없다. 로컬에서 트레이너 사진을 넣어 보려면 v1.6의 URL 직접
입력 경로(`PUT /v1/staff/{uid}/profile`의 `photo_url`)를 계속 쓴다 — 그 경로는 제거하지 않았다.

`storage.rules`는 **변경하지 않았다.** `match /staff/photos/{fileName}`의 전면 차단
(`allow read, write: if false`)이 그대로 옳다: Admin SDK는 규칙을 지나지 않고, 클라이언트는
서버가 붙인 **다운로드 토큰 URL**로만 읽는다(그 URL도 규칙을 거치지 않는다 — 규칙 주석이
적어 둔 설계 그대로다).

### 접속기록(안전성 확보조치 기준 §8) — 2년 버킷 · 월 1회 점검 (v2.30, P61)

privacy.html이 약속하는 "개인정보처리시스템 접속기록 2년 이상 보관 · 위·변조 방지 · 점검"의 서버·인프라
구현이다. 근거는 「개인정보의 안전성 확보조치 기준」(개인정보보호위원회고시 제2026-9호, 2026.7.1. 일부개정·같은 날 시행 —
law.go.kr 헤더 [시행 2026. 7. 1.] 확인)
§8 — ①항 2호(고유식별정보 또는 **민감정보**를 처리하는 시스템 → 2년 이상. 이 서비스는 체형사진·체성분을
민감정보로 취급하므로 회원 수와 무관하게 2년), ②항(점검의 주기·방법·사후조치를 **내부 관리계획으로 정하고
이행** — 현행 고시에 "월 1회" 문구는 없다; 아래 주기는 우리가 정한 값이고 정했으면 지켜야 이행이다),
③항(위·변조·도난·분실 방지). 이 절이 그 내부 관리계획이다.

**무엇을 남기나** — 서버(`internal/api/accesslog.go`)가 `/v1`·`/api/v1` 요청 하나당 stdout에 JSON 한 줄
(`log_type:"access"`). 고시 §2의 접속기록 정의 5요소를 그대로 매핑한다:

| 고시 §2 요소 | 필드 |
|---|---|
| 식별자(취급자) | `uid` · `role` · `center_id` |
| 접속일시 | `time`(RFC3339Nano UTC → LogEntry.timestamp) |
| 접속지 정보 | `remote_ip`(RealIP 결과: True-Client-IP → X-Real-IP → XFF **첫** 값 순 — **셋 다 클라이언트가 지정할 수 있어 위조 가능**) · `xff_last`(XFF **마지막** 값 = 프록시(GFE)가 덧붙인 값 → **신뢰 값**; Hosting 리라이트 경유는 끝값이 Hosting 프록시라 `x_forwarded_for`의 끝에서 둘째가 클라이언트) · `x_forwarded_for`(원 헤더 전체, 512자 클립) · `user_agent`(512자 클립) · `peer_addr`(RealIP가 덮기 전 TCP 피어 — 앞단 프록시 내부 주소, v2.39) · `ip_headers`(True-Client-IP·X-Real-IP 등 IP 헤더의 **존재**만, v2.39 — RealIP 이전 실측용) |
| 처리한 정보주체 | `subject.member_id`(path `/members/{id}` · 쿼리 `member` · 핸들러 훅 `setAccessSubject`) · `subject.resource_id`(그 외 `{id}`) · `subject.staff_uid`(`{uid}`) |
| 수행업무 | `method` · `route`(chi 패턴) · `path`(쿼리 제외) · `status`(헤더 미기록이면 타임아웃 504 / 그 외 500) · `aborted`(패닉으로 끊긴 요청만 true — 헤더가 이미 나갔으면 status는 나간 값 유지) · `latency_ms` · `bytes` |
| 상관 | `request_id` · `logging.googleapis.com/trace`(Cloud Run 요청 로그와 연결, `GCP_PROJECT` 있을 때만) · `severity`(INFO / 401·403·429 WARNING / 5xx ERROR) · `message` |

**무엇을 절대 남기지 않나**(`accesslog_test.go`가 못 박는다): 요청·응답 본문, `Authorization`·`X-Dev-*` 값,
쿠키, **쿼리 문자열 원문**(`GET /v1/members?q=이름·번호`가 들어온다 — 화이트리스트 `member` 값만 subject로
옮긴다), `Principal.Phone`, 이름.

**기록 범위** — 스태프(owner/trainer/superadmin) 요청 **전부** + 역할 무관 **401·403·429**(429는 빈도 제한,
v2.38 — 제한기가 무엇을 막았는지의 유일한 관측점). 회원(member) 요청은
**401·403·429 외에는 기록하지 않는다(400·404·5xx 포함)**(§8① "정보주체는 제외한다" + 회원 IP를 2년 쥐는 것은
최소수집에 역행 — Cloud Run 요청 로그 30일이 운영 목적을 덮는다). `/healthz`·`/health`·`/api/health`·`/v1/public/*`는 v1 클로저 밖이라
지나지 않는다. 401은 라우팅 전 거부라 `route:"/v1/*"`로 남고 `path`가 단서다. 패닉도 500·ERROR 라인을
남긴 뒤 같은 값으로 재패닉해 `recoverJSON`이 계약 포맷 500을 만든다.

**어디에 얼마나 쌓이나** — `backend/scripts/setup-access-log.sh`(멱등, 실행은 람):

| 항목 | 값 |
|---|---|
| 로그 버킷 | `access-log-2y` · 위치 **asia-northeast3**(privacy.html "서울 리전 보관" — 위치는 생성 후 변경 불가라 global 금지) · 보존 **740일**(2년 731일 + 여유) |
| sink | `access-log-2y` · 필터 `resource.type="cloud_run_revision" AND resource.labels.service_name="rize-api" AND jsonPayload.log_type="access"` · 같은 프로젝트 버킷이라 IAM 부여 불필요 |
| _Default 버킷 | 그대로(30일 운영 뷰 유지). access 라인은 두 곳에 들어간다 — 중복량 월 수 MB, 50GiB 무료 한도 안 |
| 잠금(위·변조 방지) | **미적용**. `--lock`은 불가역(수정·삭제·보존 변경 불가)이라 첫 라인 확인 후 1~2주 운영 → 스키마 안정 확인 → 람 결정. 잠금 전에도 Cloud Logging은 엔트리 편집 API가 없고 보존 정책+IAM으로 삭제를 제한하므로 "위·변조 방지"는 약하게 참, 잠그면 강하게 참 |
| sink 시작일(2년 시계) | **미실행 — 람이 스크립트 실행 시 기입**. sink는 **비소급**이라 이 날 이전의 접속기록은 존재하지 않는다 |
| Log Analytics | 켜지 않는다(`--enable-analytics` 불가역). 점검은 `gcloud logging read`만 쓴다 |

**내부 관리계획(§8②)** — 주기 **매월 첫 영업일** · 담당 **람** · 방법 `backend/scripts/access-log-review.sh [YYYY-MM]`
→ `work_log/access-review/YYYY-MM.md`(uid×업무 건수 · 401/403 목록(시각·remote_ip·xff_last·XFF 전체) · 심야 23~06 KST
스태프 접속 · 민감정보 경로 `/body-photos`·`/inbody` 상위 uid · 대량 조회(목록 GET — router.go의 목록 라우트
화이트리스트 `/members`·`/passes`·`/bookings`·`/body-photos`·`/inbody`… 만, `{id}` 단건·`/me`·`/stats`는 제외) —
이 서비스에 파일 다운로드 기능은 없어 §8②의 "다운로드 상황"은 목록 GET을 route로 식별한다). 점검 기록 파일
자체가 이행 증거다. 리포트의 `remote_ip`는 위조 가능한 값이므로 접속지 판단은 `xff_last`로 한다(위 표). 사후조치:
이상 uid → 스태프 deactivate(`POST /v1/staff/{uid}/deactivate`) + 정보주체 통지 여부 판단 + 리포트 6절에 기록.

**점검 절차(매월)** — ① `gcloud auth login`(rizejoy91@gmail.com) → ② `./backend/scripts/access-log-review.sh`
(지난달; 조회 실패는 exit 1로 멈추고 빈 리포트를 만들지 않는다 — 0건과 실패를 섞지 않는다) → ③ 생성된
`work_log/access-review/YYYY-MM.md` 6절 판정 체크. **dry-run 스모크**(gcloud 없이 스크립트·리포트 형식 확인 —
스크립트를 고쳤을 때 반드시): `bash backend/scripts/access-log-review.sh --dry-run backend/scripts/testdata/access-log-entries.sample.json 2026-08`
→ `/tmp/access-review-2026-08.md`(dry-run은 `work_log/access-review/`에 쓰지 않는다; `--out PATH`로 위치 지정 가능).
샘플은 실제 LogEntry 모양 — Cloud Logging은 stdout JSON의 `time`·`severity`를 jsonPayload에서 **떼어** 최상위
`timestamp`·`severity`로 승격하므로 스크립트는 `e.timestamp`를 읽는다(jsonPayload.time은 폴백).

**chi `middleware.Logger`를 제거한 이유** — (1) `RequestURI`에 쿼리가 통째로 실려 `?q=이름·번호`가 30일
운영 로그에 평문으로 남았다(P56 L9). (2) IP·URL·status·latency·UA는 Cloud Run 요청 로그
(`run.googleapis.com/requests`)가 자동으로 남긴다. (3) 평문은 필터가 안 된다. **정직한 고지**: 쿼리 문자열
(예: `GET /v1/members?q=`)은 Cloud Run 요청 로그(30일)에는 **여전히 남는다** — 이번 작업이 없앤 것은
우리 컨테이너 로그의 두 번째 사본이고, 접속기록 라인(2년)에는 싣지 않는다는 것이다. 요청 로그에서도
지우려면 `_Default` sink에 제외 필터를 거는 별도 결정이 필요하다(요청 로그 전체가 운영 디버깅에 쓰인다).

**로컬 개발** — 접속기록이 stdout에 찍혀 요청 로그를 대신한다(dev 헤더는 대부분 스태프 uid라 기록됨).
회원 역할 요청은 안 보인다 — 운영 규칙과 분기를 만들지 않으려고 dev 스위치를 두지 않았다.

**배포 순서(참이 되는 순서)** — ① 서버 배포(라인 생성 시작) → ② 람이 `setup-access-log.sh` 실행(sink 생성
= 2년 시계 시작) → ③ 위 표의 "sink 시작일" 기입 + privacy.html 개정 이력에 적용일 행 추가 → Hosting 배포.
②·③ 전에는 privacy.html의 "2년·위변조 방지·점검"이 아직 거짓이다(P56 L9 — 문서에서 의무를 지우는 것은
답이 아니라 순서를 지키는 것이 답).

### 요청 빈도 제한 — 프로세스 내 토큰 버킷 (v2.38, P74)

| 대상 | 키 | 정상 속도 · 순간 |
|---|---|---|
| `POST /v1/join/match`·`join/confirm`·`join/request`·`consult-requests` | 회원 uid | 분당 30 · 15 |
| `POST /v1/checkin`·`hw-checks`(한 버킷) | 회원 uid | 분당 120 · 40 |
| `GET /v1/public/business`·`public/center`(+ `/api/v1` 미러) | IP(RealIP) | 분당 60 · 30 |
| 스태프·superadmin 요청 | 세지 않음 | 어드민 원탭 체크인 포함 — 어드민은 429를 보지 않는다 |

넘으면 `429 {error, code:"rate_limited"}` + `Retry-After`(초, 올림). 수치는 `router.go` 한 곳에서 바꾼다.
**인스턴스마다 따로 센다** — Cloud Run 인스턴스가 n개면 상한도 n배로 느슨하다(정확한 분산 제한이 필요해지면
Cloud Armor/Memorystore). 무인증 경로의 IP 키는 XFF로 위조할 수 있어 적대적 방어선이 아니다(App Check 후속).
키 표는 인스턴스당 1만 개가 상한이고 가득 차면 새 키는 추적 없이 통과한다 — 그때 컨테이너 로그에
`ratelimit: 키 표 상한(10000)에 걸려 N건을 추적 없이 통과시켰어요`가 분당 최대 한 줄 남는다(위조 IP 폭주 신호).
회원의 429는 접속기록(v2.30)에 WARNING으로 남는다 — 상한 조정의 근거는 거기서 본다.

## 알려진 갭 / TODO(정직한 목록)

이 절은 "무엇을 안 만들었는가"를 숨기지 않기 위한 목록이다. API계약_v1.md가 모든 세부사항을
명시하지 않은 지점에서 내린 판단과, 명백히 v1 범위 밖으로 미룬 것을 구분해 적는다.

**최근 닫힌 갭(2026-08-23 코드 대조 — 무엇이 닫았는지 함께 적는다)**

이 목록은 자랑이 아니라 **이 README를 다시 읽는 사람이 옛 서술에 속지 않게** 하려는 것이다.
아래 5건은 종전 README가 "없다"고 적어 두었으나 지금은 있다.

| 종전 서술 | 무엇으로 닫혔나 |
|---|---|
| 정책(Policy) 조회/수정 API 없음 | `GET /v1/center`(`Service.GetCenter`) · `PUT /v1/center`(`Service.UpdateCenterPolicy`, owner 전용·머지 시맨틱) — v1.4, 범위 검증은 `domain.Policy.Validate`(v2.7에서 `penalty_rate` 0~0.1) |
| 환불 "실행" 엔드포인트 없음(계산만) | `POST /v1/passes/{id}/refund` → `Service.RefundPass` — v1.4. owner 전용, 마감은 `store.UpdatePassWithLedger` 트랜잭션(v2.6) |
| Contract `signed` 전이 엔드포인트 없음 | `POST /v1/contracts/{id}/sign` → `Service.SignContract` — v1.4, member 본인. `signed_at`·`signer_ip`를 서버가 기록 |
| 스태프 생성 엔드포인트 없음(GET·offdays 뿐) | `POST /v1/staff`(`Service.CreateStaff`, v1.8) + `PUT /v1/staff/{uid}`·`/transfer`·`/deactivate`·`/reactivate`(v2.0) + `PUT /v1/staff/{uid}/profile`(v1.6) — 총 8개 |
| `GET /v1/center`는 member 403 | member도 **200**을 받는다(v1.4). owner가 아니면 `revenue_target`만 0으로 지운다 — trainer도 마찬가지다. 쓰기(PUT)만 owner 전용 |

**설계 판단(계약이 침묵한 부분에서 합리적으로 채운 것)**

- **멀티센터 해석은 단일 센터로 단순화**: `users/{uid}.memberships[]`(설계03 §6, 여러 센터 가입)
  대신 `store.UserIndex`가 uid당 센터 1건만 유지한다. 실제 1호 고객(라이즈 컨디셔닝)이 단일
  센터라 v1엔 충분하지만, 진짜 멀티센터 전환 시 슬라이스로 승격해야 한다.
- **센터 생성·최초 owner는 v2.16 관리 평면으로 닫혔고, v2.32에서 화면까지 붙었다**(Phase A P41 ·
  Phase B P65): superadmin이 어드민 **센터 관리** 탭에서 센터 신원 + 정책 기본값 + 최초
  owner(계정·인덱스·레코드)를 한 번에 만든다(`POST /v1/admin/centers`). 남은 수작업은
  **최초 superadmin 1회 시딩**뿐 — Firestore 콘솔에서 `users/{uid}` = `{role:"superadmin",
  center_id:""}`.
  - **초대 계정의 최초 비밀번호는 생성 응답에 실린다**(v2.36, P71): `POST /v1/admin/centers`와
    `POST /v1/staff`가 `initial_password`를 돌려주고 어드민이 화면에 띄운다. 값은
    `INITIAL_STAFF_PASSWORD`(기본 `123456` — Firebase 최저 길이가 6자라 4자리는 불가능하다).
    **6자 미만이면 기동을 거부한다.** 종전엔 난수를 걸고 비밀번호 재설정 메일에 넘겼는데
    센터 생성 화면에 그 메일을 보내는 코드가 없어, 새 센터 대표는 로그인할 방법이 0이었다.
    메일도 이제 함께 나간다 — 이 값은 메일이 무너졌을 때의 경로다.
  - **관리 평면 목록에 1호점이 안 보이던 것은 v2.35(P70)에서 닫혔다** — `GET /v1/admin/centers`가
    기본 센터를 상호 없이도 항상 맨 앞에 싣는다(회원용 `GET /v1/join/centers`와 같은 집합).
  - **그 uid는 센터 owner 계정과 달라야 한다.** UserIndex는 uid당 역할 1개라, 기존 owner 계정을
    superadmin으로 바꾸면 그 사람은 자기 센터 어드민에서 잠긴다(superadmin은 `/v1/admin/*`과
    `/v1/me` 외 전부 403). 별도 이메일로 Firebase 계정을 만들고 그 uid를 시딩할 것.
  - 새 센터 owner는 **비밀번호를 모른 채** 계정만 생긴다(`EnsureUser`가 임의 임시 비밀번호로
    만든다) — 첫 로그인은 반드시 **비밀번호 재설정 메일**로 한다.
- **미등록 번호의 가입 요청은 회원이 센터를 고른다**(v2.33, P66): `GET /v1/join/centers`가
  고를 수 있는 목록(기본 센터 ∪ 신원 등록 센터)을 주고, `POST /v1/join/request`의 `center_id`는
  **그 목록에 있을 때만** 통과한다(없으면 400). 생략하면 종전대로 Principal의 센터다.
  앱은 목록이 2곳 이상일 때만 선택을 묻는다.
- **법정 문서는 센터별이다**(v2.33): `GET /v1/public/business`·`/v1/public/center`가 `?center=`를
  받는다. 모르는 센터는 **404** — 기본 센터로 폴백하면 그 문서가 거짓 고지가 된다.
  전자계약은 처음부터 센터 스코프였다(`gatherContractVars`).
- **대기 상태는 uid로 묻는다**(v2.34, P69): `GET /v1/me.join_request`가 `{status, center_id, created_at}`
  3칸이고 조회는 `Store.ListJoinRequestsByUID`(센터 무관·최신 먼저). 종전엔 Principal 센터(미연결
  uid = 기본 센터 폴백) 큐만 훑어 **2호점에 보낸 요청이 /v1/me에 안 실렸다**. 중복 409 본문은
  `{error, code:"join_pending", center_id}`(판정은 그 센터). `POST /v1/join/approve`는 같은 번호의
  살아 있는 회원이 있으면 409(승인은 새 레코드를 만든다 — 옳은 연결은 회원의 재인증).
  `GET /v1/public/center`에 `open_hour`·`close_hour`(대기실 센터 카드용, 양끝 포함 · 앱은 close+1 표기).
- **회원의 센터는 전화번호가 정한다**(v2.32, P65): `join/match`·`join/confirm`이 `Principal.CenterID`
  (신규 uid에서는 `DEFAULT_CENTER_ID` 폴백)가 아니라 검증된 번호로 전 센터를 훑는다. 이게
  없으면 2호점 회원은 앱에서 영원히 연결되지 않는다. (기존 rise 센터는 신원 미등록 상태로도
  종전과 동일하게 동작한다 — `GET /v1/center`의 name이 ""일 뿐.)
  `store.SeedDemo`는 여전히 `DEV_SEED=true` + 인메모리 전용이라 프로덕션 부트스트랩에 못 쓴다.
- **예약 생성 바디의 `kind`**: 계약 예시는 `{slot_key, member_id, pass_id}`뿐이라 kind(pt/group/ot)
  출처가 불명확 — 기본값 `pt`로 채우되 요청에 `kind`가 오면 그대로 쓴다.
- **체크인 응답/부수효과**: 계약은 검증 규칙만 명시한다. 구현은 `Member.last_visit_at` 갱신
  (설계03 §11에 명시)과 예약 객체 반환을 부수효과로 채택했고, 체크인 이력 자체는 계약에 없는
  내부 전용 타입(`store.CheckinRecord`)으로만 남긴다.
- **컷오프 이내 취소의 처리**: "컷오프 검사(24h)"만 명시돼 있어, 컷오프 이내 취소는 노쇼와
  동일한 유예 정책(최초 1회 무차감)을 적용하는 것으로 해석했다. 취소 자체를 막지는 않는다.
- **홀딩(P46)의 "회원 신청 → 어드민 승인" 플로우는 v1에서 단순화**: 계약에 신청 큐 엔드포인트가
  없어, 회원 본인 패스의 셀프 홀딩을 정책 상한(기본 최대 2회·총 30일, `Policy.max_holds_per_pass`/
  `max_hold_total_days`) 안에서 직접 허용했다(v1.2). 스태프는 상한 없이 처리 가능(데스크 예외) —
  v2.7에서 **"상한은 회원 셀프 홀딩에만 걸린다"를 계약에 명문화**했다(어드민 경로는 정책을
  로드조차 하지 않는다). 상한 `0`은 저장할 수 없다(400) — "홀딩 완전 금지"를 표현할 방법이
  현재 없고 최소 1회는 항상 허용된다. 진짜 승인 큐가 필요해지면
  `POST /v1/passes/{id}/hold-requests` 류의 후속 추가가 자연스럽다.
- **stats scope 게이팅(v1.2로 개정)**: 트레이너도 `scope=center`를 호출할 수 있다. 단 금액 지표
  (monthly/ytd/target)와 by_trainer 비교표는 owner 전용이라 비워서 반환한다 — P45의 "센터 평균과
  비교"는 비율 지표(재등록·노쇼·HW)로 성립하고, P13(타인·센터 매출 비공개)도 지킨다.
- **v1.1 "가정 승인" 목록 엔드포인트의 역할 스코프**: `GET /v1/passes|bookings|hw-checks|contracts|payments`
  모두 `member=` 쿼리 파라미터가 있어도 role=member 호출자는 항상 본인 것만 보도록 강제
  덮어쓴다(`ListHomeworks`와 동일한 override 패턴 — 불일치 시 에러가 아니라 조용히 본인 스코프로
  대체). trainer는 담당 회원(또는 담당 트레이너 소속 패스로 연결된) 것만, owner는 전체를 본다.
  `Payment`·`Contract`는 엔티티에 `trainer_id`가 없어 연결된 `Pass.trainer_id`로 소유를 판별한다.
- **전자계약 문서 스냅샷 — 발행 래치는 이제 켜져 있다**(v2.18 → **v2.22 ON**, P39·P42·P48):
  `send`가 `template_version`·`vars`를 확정하고(재발송 = 재확정) `POST /v1/contracts/{id}/sign`이
  서명 트랜잭션 **안에서** `sha256`(= SHA-256(버전 + canonical_json(vars)))으로 봉인한다.
  2026-08-30 대표 결정으로 `pt-v1-reported`·`pt-v1-exempt` 두 변형 모두 **issuable=true**
  (`contract_template.go`) — v2.18이 적어 둔 "래치 OFF로 배포된다"는 **더 이상 사실이 아니다**.
  다만 래치는 세 게이트 중 첫째일 뿐이라, 지금 실제로 발행을 막고 있는 것은 나머지 둘이다:
  **① `facility.report_status`가 미선언(unknown)** — 프로덕션 센터가 아직 선언하지 않아 읽기
  기본값이 unknown → 스탬프 스킵(v2.19) **② Business 6칸 미등록** — 전부-아니면-전무 조립이
  스킵. 즉 오늘의 관측 가능한 동작 변화는 0이지만 **이건 안전장치가 아니라 잠금 해제다**: 대표가
  어드민에서 사업자 정보를 등록하고 시설 신고 상태를 선언하는 순간(코드·배포 없이) 다음 발급·재발송부터
  실제 스탬프가 시작되고, 회원 화면은 요약 고지 → 계약서 본문 렌더로 바뀐다. 래치가 열린
  대가로 발급·발송이 매번 `facility`를 1회 더 읽는다(v2.19의 latch-off 불변은 이제 롤백
  구성의 보장이고, 그 구성에서는 여전히 테스트로 증명된다). **템플릿 교체는 첫 서명 전까지만
  자유**다 — 한 건이라도 서명되면 그 버전은 동결이고 문구 변경은 새 버전 키로 온다(§D ①).
  `pdf_path`는 §D ③대로 의도적으로 빈 자리다(채우면 "PDF가 있다"는 거짓 신호). **sha256이 빈
  서명은 요약 고지 기반 동의 기록**(P28 적법 기준선)이고, 채워진 서명만 본문 위·변조 검출이
  가능하다. `signer_ip`도 신뢰 프록시(Cloud Run/GCLB) 전제다 — XFF의 **마지막** 홉을 쓴다
  (v1.5. 첫 항목은 클라이언트가 위조할 수 있다).
- **`GET /v1/join/requests`는 owner 전용**: `JoinApprove`(승인)가 이미 owner 전용이라 목록도
  동일 경계로 맞췄다 — trainer는 가입 요청을 볼 수 없다.
- **P14(v2.7) 이전에 10%를 넘겨 서명된 계약**: `Contract.penalty_rate`에 0.3 같은 값이 그대로
  남고 어드민도 그대로 표시한다(실공제는 `RefundQuote`의 런타임 캡으로 10%). **서명된 문서를
  소급 수정하지 않는다**는 판단이다 — 표시에 "실제 공제 10%" 각주를 붙일지는 미결.
- **예약 단위 컷오프 스냅샷은 넣지 않았다**: 넣으면 앱의 취소 가능 판정(센터 정책 실값 사용)과
  서버가 예약마다 갈려 새로운 3자 불일치가 생긴다. 대신 컷오프는 취소 시점 정책으로 판정하고
  (즉시·소급), 어드민이 **컷오프를 올릴 때만** 확인 단계를 세운다.

**정확도 근사치(정밀 구현엔 스키마 확장이 필요)**

- **`stats.registered`**: Member에 가입일 필드가 계약에 없어 활성 회원수로 근사한다.
- **`stats.hw_rate`**: "배정 대상 중 체크가 한 번이라도 있었는가"의 근사 비율. 스케줄 반복
  대비 실제 이행율(예: 주3회 배정 중 몇 회 완료)은 계산하지 않는다.
  단 **기간이 끝난 배정(`schedule.to` 경과)은 분모에서 제외한다**(v2.3) — 종전엔 종료일을
  아무도 보지 않아 분모가 단조 증가했고, 완료율이 시간이 갈수록 구조적으로 하락했다.
  "오늘 대상 요일인가"가 아니라 "기간이 끝났는가"로 가른다: 주3회 배정은 화요일에도 진행 중인
  배정이라, 요일로 거르면 비율이 요일마다 출렁인다(`domain.HwSchedule.IsEndedOn`).
- **`GET /v1/stats?range=`가 아직 무시된다**(v2.1에 명시된 구현 갭): `noshow_d`·`hw_d` 등 분모는
  "해당 기간"이 아니라 **전 기간** 집계다. 어드민에 기간 필터 UI를 붙이는 시점에 분자·분모가
  함께 기간을 타도록 고쳐야 한다. 계약 위반은 아니지만 소비하는 쪽이 알아야 하는 사실이다.
- **월별 매출(`stats.monthly`)**: `Payment`에 결제일 필드가 계약에 없어 연결된 `Pass.valid_from`의
  월로 귀속시킨다. 분할납부의 실제 입금 시점(installments[].paid_at)별 집계는 아니다.
- **재등록률**: "만료 후 N일 내 같은 회원의 새 패스 발급"으로 판정한다. 같은 트레이너 유지율과
  센터 유지율(P45가 언급하는 2종 정의)을 코드가 자동 구분하진 않는다 — trainer_id로 미리
  필터링된 입력을 넣으면 트레이너 유지율이, 필터링 안 하면 센터 유지율이 나오는 방식으로 by_trainer
  루프가 트레이너별로 계산한다.
- **`GET /v1/slots?date=`는 예약이 하나라도 있는 시간대만 반환**: 빈 시간대(0/3)를 서버가
  합성하지 않는다. **v2.24부터 영업시간 모델 자체는 생겼지만**(`Policy.open_hour`/`close_hour`)
  이 엔드포인트는 그대로다 — 클라이언트가 그 두 값으로 그리드를 그리고 빈 칸을 채운다.
  서버 합성으로 옮기려면 응답 크기·캐시 정책을 함께 정해야 해서 미룬 것이지 근거가 없어서가
  아니다. 두 값은 **슬롯 시작 시각이고 양끝 포함**이다(9~21 = 13칸, 마지막이 21시 시작).
- **운영시간을 예약 생성이 강제하지 않는다**(v2.24 의도된 범위): `POST /v1/bookings`·
  `/v1/recurrings`는 `hour 0~23`만 보고 운영시간 밖 예약을 거부하지 않는다. 강제하면 대표가
  `close_hour`를 줄이는 순간 이미 잡힌 그 시간 예약을 **취소·이동조차 못 하게** 잠긴다
  (정책 변경이 과거를 소급 파괴하지 않는다는 규칙 — v2.0과 같은 근거). 데스크에서 특별히
  잡아 주는 영업시간 외 수업도 실재하는 정상 영업이다.
- **가입 매칭(`/v1/join/match`) 대상 센터**: 요청자가 아직 어느 센터에도 연결되지 않았으면
  `DEFAULT_CENTER_ID`를 대상으로 검색한다. 진짜 멀티센터에서는 "센터 검색" UI가 지정한
  center_id를 받아야 한다(위 멀티센터 갭과 연결).

**되돌릴 수단의 부재(v2.5에서 계약 갭으로 명문화 — 아직 열려 있다)**

원장이 append-only(P3)라 "삭제"가 아니라 **역전 원장(상쇄 기록)**으로 설계해야 하는데, 넷 다
아직 없다. 어드민의 2단 확인은 지혈일 뿐이다.

- **납부 취소**: `PayInstallment`에 역이 없다. 오클릭 한 번이 완납으로 영구 확정된다.
- **환불 취소**: `RefundPass`에 역이 없다. v2.4 실측에서 **0원 환불이 확정까지** 갔는데 복구
  수단이 없었다(그래서 v2.4가 쓰기 게이트를 먼저 세웠다).
- **노쇼·취소 되돌리기**: `LedgerReason`에 `revert`가 정의돼 있으나 이를 만드는 코드가 없다.
- **계약가 정정**: `PUT /v1/passes/{id}`가 없다 — `paid_amount` 오입력은 재발급이 유일한 경로다.

**아직 원자적이지 않은 쓰기 경로(v2.6이 닫지 않은 나머지 — v2.15에서 계약 전이는 닫힘)**

v2.6은 **돈·세션이 "움직이는"** 경로(발급·홀딩·재개·환불 마감·예약 상태 전이·담당 이관)를
트랜잭션화했고, v2.15(P37)가 **계약 전이(send·sign·void)와 수동 계약 생성**을 같은 패턴으로
닫았다(`TransitionContract`·`UpdatePassWithLedgerAndContracts`·`CreateContractGuarded` —
환불의 미서명 계약 무효화는 이제 마감과 **한 트랜잭션**이다). 남은 것:

- **`PayInstallment`** — `GetPayment` → 인메모리 수정 → `UpdatePayment`.
- **`CreatePayment`의 계약가 상한 검사** — 합계 계산이 트랜잭션 밖이라 동시 2건이 각자 통과할 수
  있다(v2.4의 쓰기 게이트를 경합이 우회한다. 읽기 캡이 2차 방어선이라 환불액은 계약가를 넘지
  않는다).
- **`RefundPass`의 뒷정리 중 미납 회차 종결(waived_at)** — 여전히 트랜잭션 밖이다. 결제는 센터
  전체 스캔으로 찾고 회차 인덱스 단위 재검증이 필요해, 마감을 먼저 확정하고 뒷정리 실패는
  **보이는 500**으로 남긴다(재시도하면 "이미 환불 처리된 패스예요"라 이유는 설명된다).
  waived_at은 멱등 표식이라 잔존해도 금액은 틀어지지 않는다 — PayInstallment 원자화와 함께
  닫을 후속.
- **`pass.remaining` 스냅샷**은 완료·노쇼 경로에서 원장 합과 벌어진다. 모든 판정은 원장 재계산을
  거치므로 현행 버그는 아니지만, **DB에 권위 있어 보이는 틀린 숫자가 남는다.**
- **원장 동시각 정렬은 비결정**(두 스토어가 다름). 표시 순서에만 영향.

**v1 범위 밖으로 명시적으로 미룬 것(설계 문서 자체가 OUT으로 표시)**

- PG 결제 연동(Payment는 기록만, P19) · 인바디 기기 API 연동 · AI 루틴 자동생성 ·
  체형사진 배경 인물 자동 블러(온디바이스 처리, 앱 레이어) · 알림톡/웹푸시 실발송(어댑터 자리만
  전제, 이 백엔드엔 Notifier 인터페이스조차 아직 없음 — 필요 시 추가) · 고정 스케줄의 "매주
  자동 연장" 크론(현재는 생성 시점에 4주치만 즉시 생성, 재실행 없이는 4주 이후 슬롯이 안 생김).

**테스트 실행 관련(2026-08-23 갱신)**

- 로컬(go 1.26)에서 `go mod tidy` → `go build ./...` → `go vet ./...` → `go test ./...` 전부
  통과를 확인했다(go.sum 고정 완료). 현재 `func Test` 총 **182개**(api 111 · domain 60 ·
  store 9 · config 2). 실서버 E2E(curl)로 온보딩(join/match {phone} → confirm) → 패스 목록 →
  동의 철회/재동의 → 셀프 홀딩 상한 → 환불 골든값 → hw-checks date 필터 → 이중 complete 400 →
  트레이너 center 통계 금액 제외까지 실측 검증했다(work_log/P01 참고).
- **기본 `go test`로는 잡히지 않는 결함군이 있다.** Memory 스토어는 전역 뮤텍스 하나라 경합 창이
  나노초라서, v2.6이 잡은 동시성 결함들은 전부 초록으로 통과한다. 그 계층을 확인하려면 위
  "두 스토어 공통 계약 스위트" 절의 에뮬레이터 러너(`-tags firestore_emulator`, **JDK 21 필수**)를
  돌려야 한다. **CI 잡이 없으므로 아무도 자동으로 대신 돌려주지 않는다.**
