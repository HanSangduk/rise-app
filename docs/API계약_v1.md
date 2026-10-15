# 라이즈 v1 API 계약 (백엔드·어드민·앱 공용 — 이 문서가 단일 진실)

Base: `/v1` · 인증: `Authorization: Bearer <Firebase ID token>` (로컬 개발: `X-Dev-Role: owner|trainer|member` + `X-Dev-Uid` 허용)
에러: `{"error":"메시지"}` · 시간: RFC3339 · 날짜: "2026-08-14" · slotKey: "20260814-20" (YYYYMMDD-HH)

## 엔티티 JSON (json 태그 = 이 이름 그대로)
```jsonc
Member   {id, name, phone, channel, trainer_id, flags:[{type:"injury",note}], consent:{general,sensitive,signed_at,revoked_at}, app_linked, status:"active|dormant", last_visit_at}
Pass     {id, member_id, trainer_id, product, paid_amount, total_sessions, remaining, valid_from, valid_until, status:"active|scheduled|expired|refunded", holds:[{from,to,reason}], refunded_amount?, refunded_at?}  // refunded_*는 v2.37, 환불 마감 후에만
Ledger   {id, pass_id, member_id, delta, reason:"issue|complete|noshow|noshow_waived|revert|refund|hold|resume|transfer", ref_booking_id, by, at}
Slot     {slot_key, capacity, teams:[{booking_id, trainer_id, member_id, kind}]}
Booking  {id, slot_key, member_id, trainer_id, pass_id, kind:"pt|group|ot", status:"confirmed|waitlist|cancelled|noshow|completed", recurring_id, created_at}
Recurring{id, member_id, trainer_id, pass_id, days:["tue","fri"], hour:20, until}
Homework {id, trainer_id, scope:"individual|my_members|center_notice", target_member_ids:[], excluded:[], items:[{name,sets,reps,note}], schedule:{type:"once|weekly",days:[],from,to}}
HwCheck  {member_id, hw_id, date, done:[bool]}
Staff    {uid, role:"owner|trainer", name, color, payout:{type:"per_session|rate",value}, offdays:[]}
Payment  {id, member_id, pass_id, method:"card|cash|transfer", total, installments:[{due,amount,paid_at}], channel}
BodyPhoto{id, member_id, pose:"stand|tpose|fold|ohsquat", direction:"front|side|back", date, storage_path, blurred}
Inbody   {id, member_id, date, weight, smm, bfm, pbf, vfl, bmr}
Stats    {active_members, registered, rereg_rate, rereg_n, rereg_d, unassigned, long_absent, expiring, monthly:[{month,amount}], ytd, target, noshow_rate, hw_rate, by_trainer:[{uid,name,revenue,sessions,rereg_rate,rereg_n,rereg_d,noshow_rate,hw_rate}]}  // by_trainer는 owner만
```

## 엔드포인트
```
GET  /v1/me                                → {uid, role, center_id, member_id?, name?, join_request?}  (name은 v2.2, join_request는 v2.27 — {status, center_id, created_at} v2.34)
POST /v1/join/match                        회원: 번호 인증 후 자동 매칭 조회 → {member?, needs_confirm:true}
POST /v1/join/confirm                      {member_id, confirm:true|false}  이름확인 1탭(P48)
POST /v1/join/request                      {center_id} 가입 요청(409 본문 {error, code:"join_pending", center_id} v2.34) · POST /v1/join/approve {request_id} (owner — 같은 번호의 활성 회원이 있으면 409 v2.34)
POST /v1/join/reject                       {request_id} 거절 (owner, v2.27) — 이름·번호를 비우고 status만 남긴다

GET  /v1/members?trainer=&q=               역할 스코프 자동(트레이너=담당만)
POST /v1/members  PUT /v1/members/{id}
GET  /v1/members/{id}/ledger?pass=

POST /v1/passes                            발급(+원장 issue)
POST /v1/passes/{id}/hold {from,to,reason} POST /v1/passes/{id}/resume
POST /v1/passes/{id}/refund-quote {used}   → {per_session, usage, penalty, refund}  실결제가 기준(P5)

GET  /v1/slots?date=                       → [Slot] (용량·팀)
POST /v1/bookings {slot_key, member_id, pass_id}   트랜잭션: 용량3 + 트레이너동시1 + 잔여>0 (P35)
DELETE /v1/bookings/{id}                   컷오프 검사(24h)
POST /v1/bookings/{id}/complete|noshow     원장 차감·유예(P4·P7)
POST /v1/recurrings  DELETE /v1/recurrings/{id}    고정 스케줄(P47)
POST /v1/checkin {source:"tap|self_qr", booking_id?|qr_token?}   셀프체크인=예약·시간창 검증(P44)

GET  /v1/homeworks?member=  POST /v1/homeworks   부상 자동 제외(P39)
POST /v1/hw-checks {hw_id, date, done:[...]}

GET  /v1/stats?range=ytd&scope=me|center   scope=me → 본인 스코프(P45), by_trainer는 owner만
POST /v1/payments  POST /v1/payments/{id}/installments/{i}/pay
GET  /v1/body-photos?member=  POST /v1/body-photos (동의 검증 P8 · storage_path는 members/{member_id}/body/{file}만 v2.38)
DELETE /v1/body-photos/{id}  POST /v1/body-photos/{id}/restore  POST /v1/body-photos/purge (v2.14)
GET  /v1/inbody?member=  POST /v1/inbody
GET  /v1/staff  POST /v1/staff/{uid}/offdays

요청 빈도 제한(v2.38): POST join/match·join/confirm·join/request·consult-requests 는 회원 uid당 분당 30(순간 15),
POST checkin·hw-checks 는 회원 uid당 분당 120(순간 40), 무인증 GET public/business·public/center 는 IP당 분당 60(순간 30).
스태프·superadmin 요청은 세지 않는다. 넘으면 429 {error, code:"rate_limited"} + Retry-After(초, 올림). 그 외 경로는 제한 없음.
```

핵심 골든값(테스트 고정): 환불 1,000,000·20회·7회사용·10% → per 50,000 / usage 350,000 / penalty 100,000 / **refund 550,000**. 재등록 2/8+1/6+1/6=4/20=20%. 슬롯 용량 3, 동일 트레이너 중복 예약 거부.

## v1.1 정합 패치 (2026-08 — 빌더 갭 리포트 반영, 이 섹션도 계약의 일부)
```jsonc
Contract {id, member_id, pass_id, product, paid_amount, status:"draft|sent|signed", sent_at, signed_at, signer_ip, sha256, pdf_path}
```
```
GET  /v1/contracts?member=&status=         계약 목록(어드민 계약확인)
POST /v1/contracts {member_id, pass_id}    생성(발급 시 자동 생성 가능)
POST /v1/contracts/{id}/send               서명 요청(재)발송
GET  /v1/payments?member=                  결제 목록(분할·미수 확인 — 추가결제 = POST /v1/payments 기존)
GET  /v1/passes?member=                    (앱 가정 승인) 내/특정 회원 회원권 목록
GET  /v1/bookings?member=&from=            (앱 가정 승인) 내 예약 목록
GET  /v1/hw-checks?hw_id=&member=          (어드민·앱 가정 승인)
GET  /v1/join/requests                     (어드민 가정 승인) 가입 요청 목록
GET  /v1/center                            (어드민 가정 승인) 센터 정보·정책
Slot.teams[].status 필드 추가              "confirmed|completed|noshow"
GET /v1/members 응답에 passes:[] 임베드     (어드민 가정 승인)
Stats의 *_rate = 0~1 소수                  (어드민 가정 확정)
```
추가결제 플로우 확정: **추가 계약 = 새 Pass 발급(POST /v1/passes) → Contract 자동 생성(sent) → Payment 기록(분할 가능)**. 어드민 회원 상세에서 원스톱.

## v1.2 정합 패치 (2026-08-17 — 3계층 교차검증(work_log/P01) 반영, 이 섹션도 계약의 일부)

세 층(백엔드·어드민·앱)이 계약의 침묵 지점을 **서로 다르게 메워 실제로 연결이 끊어졌던 곳**을 확정한다.

### 바디·파라미터 명시 (기존에 미기재라 층마다 달랐던 것)
```
POST /v1/join/match {phone}                  빈 바디 아님 — 매칭할 전화번호 필수(Firebase 실연동 시 토큰의 phone_number로 대체 예정)
POST /v1/join/request {center_id?, name, phone}   center_id 비우면 서버 기본 센터로 폴백(v1 단일 센터)
POST /v1/checkin self_qr = {source, qr_token}     qr_token 필수(데스크 인쇄 QR 값 = 서버 CHECKIN_QR_TOKEN).
                                             booking_id는 무시 — 서버가 시간창(±30분) 내 내 confirmed 예약을 자동 탐색
GET  /v1/hw-checks?hw_id=&member=&date=      date 필터 추가(회원 앱 "오늘 체크 상태" — 과거 체크 오표시 방지)
POST /v1/payments                            installments[].due="YYYY-MM-DD"(날짜), paid_at=RFC3339(타임스탬프)
POST /v1/payments/{id}/installments/{i}/pay  {i}는 0-based 배열 인덱스
POST /v1/staff/{uid}/offdays {offdays:[]}    바디 명시
```

### 역할 스코프 확정 (회원 앱 셀프서비스 — 종전 백엔드는 전부 403이었음)
```
GET  /v1/members                 role=member → 본인 1건(passes 임베드) 반환("내 프로필"로 재사용)
PUT  /v1/members/{id}            ① 머지 시맨틱: 보낸 필드만 갱신(부분 PUT이 나머지 필드를 지우지 않음)
                                 ② role=member는 본인 consent만 수정 가능 — sensitive 전이 시각(signed_at/revoked_at)은 서버가 기록
POST /v1/passes/{id}/hold|resume  member 본인 패스 허용. member 호출은 정책 상한 강제
                                 (Policy.max_holds_per_pass 기본 2 · max_hold_total_days 기본 30 — P46 "신청→승인"의
                                  v1 단순화: 승인 큐 대신 상한 있는 셀프서비스. 스태프는 상한 없음)
POST /v1/passes/{id}/refund-quote member 본인 패스 허용(읽기 전용 계산 — 마이탭 환불 계산기)
GET  /v1/stats?scope=center       trainer 허용하되 금액(monthly/ytd/target)·by_trainer는 제외하고 비율 지표만
                                 (P45 "센터 평균 비교"용 · 금액은 P13에 따라 owner 전용)
회원인데 member_id 미연결(가입 매칭 전)이면 목록 엔드포인트는 403 — 빈 스코프로 센터 전체가 새는 것을 차단
```

### 예약·원장 규칙 보강
```
POST /v1/bookings                      슬롯 "날짜"도 패스 유효기간 안 + 홀딩 구간 밖이어야 함(기존 오늘 기준 검사에 추가)
POST /v1/bookings/{id}/complete|noshow confirmed 상태에서만 전이 허용 — 중복 호출은 400(이중 차감·취소 부활 방지)
노쇼 유예(P7)의 "최초 1회" 판정        noshow_waived 이력도 유예 소진으로 집계(안 하면 유예가 무한 반복됨)
POST /v1/recurrings                    패스 소유·잔여·유효기간 검증을 예약과 동일 적용 + 선행 생성은 잔여 세션 이내로 캡
```

### 기타 확정
```
에러 메시지 = 사용자향 한국어 문구      내부 마커·Go 에러 원문 노출 금지. 500 바디는 "서버 오류가 발생했습니다"(원문은 서버 로그)
Staff.payout.value                     rate는 0~1 소수(Stats 비율과 동일 규약) · per_session은 원 단위 정수
Policy 필드 추가                        max_holds_per_pass(기본 2) · max_hold_total_days(기본 30)
```

## v1.3 정합 패치 (2026-08-18 — 2라운드 로직·UI/UX 교차검증(work_log/P01) 반영, 이 섹션도 계약의 일부)

### 보안·무결성
```
POST /v1/join/confirm {member_id, confirm, phone}   phone 재대조 필수 — 유출·추측된 member_id만으로는
                                              연결 불가(Firebase 실연동 시 토큰 phone_number로 대체).
GET  /v1/homeworks (role=member)             응답에서 target_member_ids·excluded 명단 제거(회원 ID·
                                              부상 명단 비노출) + excluded 회원에겐 공지형도 미배달(P39 유지)
DELETE /v1/bookings/{id}                     confirmed 상태에서만(이미 처리된 예약 재취소 = 400 —
                                              complete/noshow와 동일 가드, 스토어 트랜잭션 내부에서도 재검증)
POST /v1/passes/{id}/hold (member)           시간축 검증 추가: 과거 시작·유효기간(연장 전) 밖 시작·
                                              기존 홀딩과 겹침 거부(공짜 연장·만료 부활 차단). 스태프는 예외(정정)
POST /v1/checkin                             예약당 체크인 기록 1건(멱등 upsert — 연타·재시도 무해)
GET  /v1/stats                               target(매출 목표)은 scope 무관 owner 전용. trainer의
                                              scope=center는 금액 제외·비율/인원수 운영 지표만
```

### 예약 시간축 확정 (v1.2 "오늘 기준+슬롯 날짜 추가"를 대체)
```
POST /v1/bookings, /v1/recurrings            상태(active)·잔여(>0)는 "지금" 기준, 날짜 적합성은 전부
                                              "슬롯" 기준: ① 이미 지난 시간대 거부 ② valid_from이 미래인
                                              패스도 유효기간 안의 슬롯이면 선예약 허용(재등록 선예약 플로우)
                                              ③ 홀딩 구간의 슬롯 거부
Booking.status "waitlist"                    예약어로만 유지 — v1 미구현(생성 경로 없음). 알림 인프라 없는
                                              자동 승격은 노쇼 함정이라 알림톡/푸시 어댑터와 함께 후속
```

### 직렬화·정책 규약
```
배열 필드는 항상 [] (null 금지)              Member.flags · Pass.holds · Staff.offdays · Payment.installments(v2.28)
                                              — 신규 생성 경로 포함 + **읽기 직전에도** nil→[] (v2.28: 이미 null로
                                              굳은 문서를 위한 바닥. Member.body_poses는 nil이 의미를 가져 제외)
Policy 홀딩 상한                             -1=명시적 무제한, 0=필드 부재(로드 시 기본값으로 승격 —
                                              v1.2 이전 정책 문서에서 상한이 풀리는 것 방지)
consent.signed_at/revoked_at                 항상 서버 기록(스태프 PUT이 보낸 값도 무시하고 전이 규칙만 적용)
홀딩 횟수 상한                                조기 종료(resume)된 홀딩도 1회로 소진(사용한 홀딩은 소진)
JSON 파싱 에러                                한국어 고정 문구로 응답(Go/encoding 원문 비노출), 이어붙인
                                              다중 JSON 문서 거부
POST /v1/staff/{uid}/offdays                 날짜는 "YYYY-MM-DD" 형식 검증(불량 값 400)
POST /v1/passes                              member_id 실존 검증(고아 패스·계약 방지)
Homework.items[].reps = string               "10-12"·"30초"·"각 15회" 표기 지원(sets는 int 유지) —
                                              앱·어드민 모두 string이었고 백엔드만 int였던 불일치 확정 해소
```

## v1.4 기능 패치 (2026-08-22 — 기능 갭 리서치(P02)·UX 여정 검수 반영, 이 섹션도 계약의 일부)

설계00 §4 코어 루프의 마지막 구멍(수업기록)과 owner 운영 여정의 데드엔드 4곳(환불 실행·정책
편집·미수금·고정 스케줄 관리), 회원 여정의 종착 단계(계약 서명)를 채운다. 근거: work_log/P02.

### 신규 엔티티
```jsonc
WorkoutLog {id, member_id, trainer_id, booking_id?, date, title, exercises:[{name, sets, reps, weight_kg, note}], coach_note}
// reps는 문자열(HwItem과 동일 규약) · weight_kg는 숫자(0=자중 — 진행 그래프 후속 대비) · exercises는 항상 []
```

### 신규 엔드포인트
```
GET  /v1/workout-logs?member=&from=          수업 기록 목록. member=본인 강제, trainer=본인 작성분, owner=전체
POST /v1/workout-logs                        스태프 전용(trainer는 본인 명의 강제). booking_id 연결 시 회원·담당 일치 검증.
                                              date 생략=오늘, title 생략="1:1 PT" — 완료 처리 직후 30초 기록(P29)
GET  /v1/recurrings                          고정 스케줄 목록(owner=전체, trainer=본인, member 403) — P47 관리 UI용
PUT  /v1/center {policy:{...}}               운영 정책 편집(owner 전용). 범위 검증: capacity 1~10 · cutoff 0~168h ·
                                              penalty_rate 0~1 · 홀딩 상한 양수 또는 -1(무제한) 등 — 위반 400
POST /v1/passes/{id}/refund {used}           환불 "실행"(owner 전용): 견적 재계산 → 원장 refund(잔여 0 마감, P3) →
                                              status=refunded 전이. 이미 refunded면 400. 응답 {pass, quote}
POST /v1/contracts/{id}/sign                 회원 자체서명(P27, member 본인 전용): sent→signed 전이,
                                              signed_at·signer_ip는 서버 기록(sha256·pdf_path는 실PDF 연동 후속)
```

### 기존 계약 변경
```
GET  /v1/center                              member에게도 공개 — 앱이 취소 컷오프·홀딩 상한을 실정책 값으로 표시
                                              (정책이 편집 가능해지며 하드코딩 문구는 거짓말이 됨). revenue_target은 owner만
Stats 필드 추가                               sessions(스코프 내 완료 세션 수 — 트레이너 scope=me면 본인 정산 근거) ·
                                              unpaid_total/unpaid_count(미수금 합계·건수, owner 전용 금액 지표)
POST /v1/bookings                            담당 트레이너 휴무일(Staff.offdays)의 슬롯 거부 — recurring 선행 생성만
                                              거르고 일반 예약은 뚫리던 비대칭 해소
```

### v1.4.1 검수 보완 (2026-08-22, P03 새눈 검수 — 이 절도 계약의 일부)
```
POST /v1/passes/{id}/refund              ① 해당 패스의 "미래 confirmed 예약"을 무차감 일괄 취소(슬롯 해제 —
                                            환불 후 예약 생존 시 원장 음수·정산 오집계 방지) ② used는 원장
                                            파생값(총-잔여)과 일치해야 함: 0/생략=파생값 사용, 불일치=400
POST /v1/bookings/{id}/complete|noshow   환불 처리된 패스의 예약은 400(이중 방어선)
POST /v1/passes/{id}/hold|resume         status=active 패스만(환불·만료 패스 홀딩으로 유효기간 연장 방지)
PUT  /v1/center                          머지 시맨틱: 보낸 필드만 갱신(누락 필드가 false/0으로 초기화되지 않음)
POST /v1/workout-logs                    date "YYYY-MM-DD" 형식 검증 · booking_id 연결 시 기록 명의(trainer_id)가
                                            예약 담당 코치와 일치해야 함(owner 대행 포함)
GET  /v1/workout-logs                    from 형식 검증
POST /v1/recurrings                      오늘 이미 지난 시각의 회차는 생성하지 않음(예약과 대칭)
GET  /v1/stats by_trainer                owner(대표) 행 제외 — 트레이너만
POST /v1/contracts/{id}/send             서명 완료된 계약 재발송 400(재발송↔동시 서명 클로버 방지)
모든 요청 바디                             이어붙인 다중 JSON 문서 거부(decodeJSON에도 적용)
signer_ip 주의                            RealIP(X-Forwarded-For) 기반 — 신뢰 프록시(Cloud Run) 뒤 배포 전제
정책 캐시 주의                             회원 앱은 새로고침 시 정책 재조회 — 서버 판정(컷오프·상한)은 항상
                                            요청 시점 정책이므로 강제는 즉시, 표시만 새로고침 지연
```

## v1.5 정산·정합 패치 (2026-08-22 — 예약·결제·전자계약 도메인 수직 감사(work_log/P04) 반영, 이 섹션도 계약의 일부)

세 도메인이 "환불"이라는 한 사건에서 절연돼 있던 것을 잇고, 돈 계산의 기준을 실수납으로 확정한다.

### 환불 정산 (P5 "실결제가 기준"의 실질 구현)
```
RefundResult에 paid_sum 추가                {per_session, usage, penalty, paid_sum, refund}
정산식                                       per·usage·penalty는 계약가(pass.paid_amount) 기준,
                                             refund = max(실수납(Σ 납부 회차) − usage − penalty, 0)
                                             — 분할 미완납 패스를 계약가로 환불하면 받은 적 없는 돈이 나간다(감사 실측)
위약금율                                     패스의 유효 계약 penalty_rate 스냅샷 우선, 없으면 현재 정책
                                             (정책 변경의 소급 적용 차단 — 회원이 동의한 요율로 정산)
결제 기록이 전혀 없는 패스                    계약가 폴백(레거시)
refund-quote와 refund 실행                   동일 정산식(계산기와 실행 금액이 어긋나지 않음)
환불의 부수효과(한 사건으로 묶임)             ① 미래 confirmed 예약 무차감 일괄 취소(v1.4.1) ② 미납 회차
                                             waived_at 마킹(청구 종결 — 미수금 제외) ③ 미서명(draft·sent)
                                             계약 voided 전환 ④ 순매출 집계에서 제외
```

### 결제 (Payment)
```
Installment.waived_at 추가                   환불로 청구 종결된 회차(삭제 아닌 표식 — P3 원장주의)
POST /v1/payments 검증 게이트                total>0 · method enum · pass 실존/소유 일치 · refunded 패스 거부 ·
                                             회차 금액>0 · due "YYYY-MM-DD" · Σ회차==total · trainer는 담당 패스만(쓰기 스코프)
POST /v1/payments/{id}/installments/{i}/pay  이미 납부(멱등 — 시각 증적 보존)·waived·refunded 패스 → 400.
                                             trainer는 담당 패스만(쓰기 스코프 — 생성과 대칭, P05 통합검수)
POST /v1/payments의 waived_at 선탑재          400(waived는 환불 정산의 결과 상태 — 생성 시 지정 불가)
POST /v1/passes/{id}/refund-quote            used 0~총 횟수 검증(음수 견적 왜곡 차단)
Stats 미수 재정의                             unpaid_total/count = 연체(due 경과)만 · upcoming_total = 미도래 미납(신규)
                                             — 시장 용례("미수금"=연체)와 정합. 환불 패스 결제는 집계 제외
매출 = 순매출                                 monthly/ytd/by_trainer.revenue에서 환불 거래 제외
```

### 전자계약 (Contract)
```
status에 voided 추가                          draft|sent|signed|voided — 환불 시 미서명 계약 자동 무효(종단).
                                             signed는 성립했던 거래의 기록으로 보존(무효화 불가)
penalty_rate 추가                             생성 시점 정책 요율 스냅샷(환불 정산의 기준).
                                             null=레거시(스냅샷 이전 계약 — 현재 정책으로 정산),
                                             0=동의된 0%(소급 인상 차단 — P05 통합검수 확정)
first_sent_at 추가                            최초 서명 요청 시각(재발송이 sent_at을 덮어도 최초 고지 증적 보존)
refunded 패스                                 계약 생성·발송·서명 전부 400
패스당 유효(비voided) 계약 1건 불변식          중복 생성 400
GET /v1/contracts?status= 값 검증             미지 status 400(조용한 빈 배열 금지)
signer_ip                                    XFF "마지막" 홉 채택(신뢰 프록시가 append한 값 — 첫 항목은 클라이언트
                                             위조 가능, 감사 실증)
```

### 예약 (Booking)
```
회원 동시 1팀 규칙 추가                        같은 회원이 같은 슬롯에 2팀 점유 불가(코치 달라도) — 409.
                                             미배정 담당("") 팀끼리는 트레이너 규칙 미적용
DELETE /v1/bookings/{id}?waive=true          스태프 전용 무차감 취소(운영 사유 — recurring 정리·코치 사정이
                                             회원 유예를 소진시키지 않게). member 요청에선 무시
tap 체크인                                    confirmed 예약만(취소된 예약 체크인이 last_visit_at 오염하던 경로 차단)
환불 패스의 잔존 예약 뒷정리 취소               페널티 원장 생략
POST /v1/recurrings 검증                      hour 0~23 · days는 mon~sun 소문자 · until 형식. 만료(until 경과)
                                             규칙은 GET /v1/recurrings에서 숨김
GET /v1/bookings?from= 형식 검증              불량 값 400(v1.4.1 workout-logs와 대칭)
GET /v1/slots (role=member)                  타인 팀의 member_id·booking_id 비노출(빈 값 — 점유율·본인 판정만 가능)
빈 슬롯의 용량                                 teams가 빈 슬롯은 예약 시 현재 정책 용량으로 갱신(옛 스냅샷 영구화 방지)
POST /v1/bookings kind 검증                   pt|group|ot 외 400
```

## v1.6 기능 패치 — 트레이너 프로필 (2026-08-22, P05 리서치 기반, 이 섹션도 계약의 일부)

회원이 코치의 이력을 보고 상담·재등록·수업 선택에 참고할 수 있게 한다(설계03 §9 "코치 프로필"
복원). 필드 구성은 시장 표준(운동닥터·다짐·포인티 조사 — work_log/P05)에서 도출. 리뷰/평점·
가격·SNS는 의도적 제외(마켓플레이스 맥락 — 단일 센터 CRM 부적합).

### 엔티티 변경
```jsonc
Staff.profile 추가(항상 객체 — null 금지, 배열은 항상 []):
  {photo_url, title, career_years, specialties:[], certifications:[], awards:[], bio}
```
```
photo_url        외부 이미지 URL(http/https만 — 스킴 주입 차단, ≤2048자). 빈 값 허용.
                 **v2.25부터 `POST /v1/staff/{uid}/photo`(owner 전용)가 이 필드를 서버에서 채운다** —
                 예고한 대로 클라이언트 계약은 불변이다(값이 외부 URL이든 Storage 토큰 URL이든
                 렌더 경로가 같다). URL 직접 입력도 계속 유효하다.
                 빈 값/로드 실패 시 클라이언트는 Staff.color 배경 + 이름 첫 글자 이니셜 아바타
title ≤40자 · career_years 0~50(0=미표기) · bio ≤500자 · 배열 원소 ≤80자·각 ≤20개
전 필드 회원 열람 전제의 공개 데이터 — payout 마스킹(P13)은 기존 그대로
```

### 신규 엔드포인트
```
PUT /v1/staff/{uid}/profile {profile}      owner 또는 본인 trainer(offdays와 동일 권한, member 403).
                                            "통 교체" 시맨틱 — 폼이 항상 전 필드 제출(머지 아님,
                                            빈 값으로 지우기 자연스러움). 범위 위반 400 한국어
                                            **예외(v2.31 개정)**: 우리 파일(`staff/photos/{uid}-…`)을
                                            가리키는 photo_url은 이 PUT으로 **새로 만들 수 없다** —
                                            그 포인터는 업로드 엔드포인트(v2.25)만 박는다. 저장된 값과
                                            다른 우리 파일 URL을 보내면 409(stale). 같은 값 되돌림·빈 값·
                                            외부 URL은 종전대로.
```

### 기존 계약 변경
```
GET /v1/staff                              응답에 profile 포함(하위호환 — 기존 클라이언트는 미지정 키 무시)
DEV_SEED                                   스태프 4명 프로필 시딩(경력·자격·수상 + t1/t2/t3는
                                            photo_url 외부 이미지 — 사진 아바타·프로필 시트·코치 소개
                                            목록 테스트용. owner1은 빈 값으로 남겨 이니셜 폴백도 재현.
                                            오프라인이면 이미지 로드 실패 → TrainerAvatar 폴백으로 무해)
```

### 운영(비계약) — DEV_SEED
`DEV_SEED=true`(인메모리 한정)면 데모 데이터 시딩: 스태프 4(owner1 박관장·t1 정혜린·t2 김태오·
t3 이수민 — t1/t2/t3 프로필 사진 포함), 회원 5(부상·휴면·미배정·만료임박 상태 포함),
패스·예약(완료/노쇼유예/예정)·고정 스케줄·홈워크·결제(미납 1건)·계약(signed/sent)·수업기록·인바디.
회원 앱 데모 uid는 `member1`(김민지 연결 — 패스 2개: PT 20회(t1)·모빌리티 8회(t3), 코치 전환 테스트용).

## v1.7 인증 실연동 패치 (2026-08-22, P06 Firebase 실연동, 이 섹션도 계약의 일부)

문서 첫 줄의 인증 규칙이 실제로 켜졌다(Firebase 프로젝트 `rize-218c1`). 3계층이 함께 지켜야
하는 규칙만 여기 못박는다 — 프로비저닝·배포 절차는 각 README 소관.

### 인증 모드 판정(서버)
```
FIREBASE_PROJECT 설정됨(프로덕션)  → Authorization: Bearer <ID token>만 신뢰. X-Dev-* 완전 무시(401)
FIREBASE_PROJECT 없음(로컬)        → 기존대로 X-Dev-Role/X-Dev-Uid
클라이언트는 두 헤더를 동시에 보내도 된다 — 서버가 모드별로 하나만 쓰므로 무중단 스왑이 된다
```

> ⚠ **이 절의 "있으면" 조건부 규칙은 v1.9에서 "필수"로 강화됐다** — 아래 v1.9 절이 우선한다.
> 조건부로 두면 phone_number가 없는 토큰(이메일 계정 등)이 바디 폴백으로 계정 탈취에 쓰였다.

### 전화번호 = 토큰의 phone_number (보안 승격)
```
POST /v1/join/match, POST /v1/join/confirm
  토큰에 phone_number가 있으면 그것이 진실 원천 — 바디의 phone은 무시된다(dev 모드 폴백 전용).
  근거: 바디 번호를 신뢰하면 member_id + 임의 번호로 타인 레코드에 연결되는 탈취 체인이 열린다.
  (v1.3의 "전화번호 재대조" 방어선은 유지 — 대조 대상이 클라이언트 값에서 토큰 값으로 승격된 것)

POST /v1/join/request
  같은 규칙이되 "대조"다 — 토큰 번호와 어긋나면 400, 미입력이면 토큰 번호로 채우고, 일치하면
  입력 표기를 그대로 저장한다(어드민 화면 가독성 보존). 승인(join/approve)이 이 번호를 그대로
  회원 레코드로 굳히므로, 타인 번호로 요청 → owner 승인 → 그 번호 선점 체인을 입구에서 끊는다.
```

### 전화번호 비교 정규화(3계층 공통 규칙)
```
비교 키 = 숫자만 남긴 뒤, 앞의 국가코드 "82"를 제거하고 국내 표기의 선행 0을 복원한 값.
  "+821012345678" == "010-1234-5678" == "01012345678"  → 모두 "01012345678"
  "+82 2 123 4567" == "02-123-4567"                    → 모두 "021234567"
어드민은 사람이 읽는 국내 표기로 저장하고 토큰은 E.164로만 번호를 싣기 때문에 필수다 —
단순 숫자만 남기기로 비교하면 두 표기가 영원히 불일치해 앱 회원의 가입 매칭이 전부 실패한다.
저장 값의 표기는 바꾸지 않는다(비교용 키일 뿐).
```

### 헬스체크
```
GET /health    (신규) — 운영 헬스체크는 이 경로를 쓴다
GET /healthz   유지 — 단, Cloud Run(run.app) 도메인에서는 Google 프론트엔드가 가로채 컨테이너까지
               도달하지 않으므로 외부 모니터링에는 쓸 수 없다
```

## v1.8 기능 패치 — 스태프 초대 (2026-08-22, P07, 이 섹션도 계약의 일부)

대표가 트레이너를 직접 등록할 수 있게 한다. v1.7까지는 스태프를 **만드는** 경로가 없어
(`SetOffdays`·`PUT /staff/{uid}/profile`는 둘 다 기존 레코드 수정 전용) 실운영 DB에 owner 1명만
존재했고, 트레이너 없이는 예약·수업기록·정산이 시작되지 않았다.

### 신규 엔드포인트
```
POST /v1/staff                                owner 전용(trainer·member 403)
요청 {name, email, role:"trainer"|"owner", color?, payout?:{type:"per_session"|"rate", value}}
응답 201 {uid, role, name, color, payout, offdays:[], profile:{...빈 값·배열은 []}}

uid 확보 규칙:
  Firebase 모드 — Admin SDK로 email 계정 생성(임시 랜덤 비밀번호). 그 이메일 계정이 이미
                  있으면 **그 uid를 재사용**한다(재초대 허용).
  dev 모드       — 합성 uid 발급(FIREBASE_PROJECT 미설정 시).
저장 부수효과: Staff 레코드 + UserIndex(uid → role, center_id) 동시 생성.
기본값: color 미지정 시 팔레트 자동 배정(기존 스태프와 중복 회피) · payout 미지정 시
        {type:"per_session", value:0}.

400 이름 공백·이메일 형식·role 값·payout 범위 / 403 owner 아님
409 그 uid가 이미 이 센터 스태프 · 그 uid가 이미 회원(member)으로 연결됨
```

### 초대 메커니즘 (계약의 일부 — 비밀번호는 응답에 없다)
```
백엔드는 임시 비밀번호를 만들지만 **응답에 담지 않는다.** 어드민이 201을 받은 직후 Firebase
클라이언트 SDK의 sendPasswordResetEmail(email)로 초대 메일을 보내고, 초대받은 사람이 스스로
비밀번호를 정한 뒤 로그인한다. 재발송은 로그인 화면의 "비밀번호를 잊으셨나요" 경로.
근거: 백엔드에 메일 발송 인프라가 없고 Firebase 자체 메일러는 클라이언트 SDK 전용이다.
임시 비번을 화면에 띄워 구두 전달하는 방식보다 안전하다.
```

### 배포 토폴로지(비계약 — 클라이언트 경로에 영향)
```
어드민은 Firebase Hosting(https://rize-218c1.web.app)에서 서비스되고 /api/** 요청은 Hosting이
Cloud Run(rize-api)으로 리라이트한다 — 같은 오리진이라 CORS가 발생하지 않는다.
Hosting은 경로 접두사를 벗기지 못하므로 백엔드는 /v1/* 과 /api/v1/* 을 **둘 다** 받는다.
그 덕에 개발(vite 프록시가 /api를 벗김)과 운영의 클라이언트 코드가 완전히 동일하다.
앱(Flutter)은 Cloud Run URL을 직접 쓰므로 /v1/* 경로 그대로다.
```

## v1.9 보안 패치 — 가입 경로 (2026-08-22, P08 새눈 감사, 이 섹션도 계약의 일부)

v1.7의 "토큰에 phone_number**가 있으면** 진실 원천" 규칙이 조건부였던 탓에, 번호가 없는 토큰은
바디 폴백으로 흘렀다. 프로젝트에 이메일 계정만 만들면(자체 가입은 기본 허용) 남의 번호를 바디에
실어 그 회원 레코드에 연결할 수 있었다 — 완전한 계정 탈취. 어드민 토큰(이메일 로그인)도 같은
성질이라 스태프 역시 이 경로였다. 조건부를 **필수**로 바꾼다.

### 검증된 번호 필수
```
POST /v1/join/match · /v1/join/confirm · /v1/join/request
  프로덕션(FIREBASE_PROJECT 설정): 토큰의 phone_number가 **없으면 403**. 바디 phone은 폴백이
                                   아니라 표기 대조용일 뿐이다(request의 표기 보존 규칙).
  로컬 개발(FIREBASE_PROJECT 없음): 종전대로 바디 값을 쓴다 — 토큰 자체가 없는 환경이다.
```

### 스태프는 회원으로 연결되지 않는다
```
POST /v1/join/confirm · /v1/join/request        호출자가 owner|trainer면 403
POST /v1/join/approve                            요청자(jr.uid)가 owner|trainer면 403
근거: 이 경로들이 UserIndex를 role=member로 덮어쓰는데 UserIndex는 역할의 단일 출처다.
      되돌릴 API가 없어 대상이 마지막 대표면 센터가 영구히 잠긴다(Firestore 직접 편집만 복구).
```

### 승인 멱등
```
POST /v1/join/approve   요청 상태가 pending이 아니면 409 "이미 처리된 가입 요청이에요"
근거: 목록이 pending 필터를 하지 않아 승인된 요청이 큐에 남는다 — 두 번 누르는 게 기본 동선인데
      상태를 안 보면 같은 사람의 회원 레코드가 둘 생기고 먼저 만든 쪽이 고아가 된다.
```

### 연결 전 응답 최소화
```
POST /v1/join/match 응답의 member는 이제 Member 엔티티 전체가 아니라 다음 5필드만:
  {id, name, phone, trainer_id, status}
제거: flags(부상 메모 = 건강정보) · consent · channel · last_visit_at · app_linked
근거: 본인 확인이 끝나기 **전**에 나가는 응답이다. 확인 1탭(name)과 연결 직후 홈 구성
      (trainer_id·status)에 필요한 것만 남긴다. 클라이언트 하위호환 — 앱 MemberDto의 필수
      필드(id·name·phone)는 유지되고 나머지는 옵션/기본값이라 파싱이 깨지지 않는다.
```

## v2.0 직원 생애주기 — 정정·이관·퇴사 (2026-08-22, P08, 이 섹션도 계약의 일부)

v1.8로 초대가 열렸지만 **되돌리기가 없었다** — 이름 오타·역할 오지정·정산 조건 변경·퇴사를
처리할 경로가 없어 잘못 초대하면 영구히 남았다. 특히 이메일 오타는 유령 스태프를 만든다:
다른 이메일 = 다른 Firebase 계정 = 다른 uid라 재초대는 성공하고, 앞서 만든 uid는 지울 수단이
없는 채로 모든 드롭다운·색상 범례·정산 비교표에 계속 남는다.

이 설계는 새 결정이 아니라 **미집행 결정의 집행**이다 — 설계 00 §Q5(*"trainer.active=false +
담당 이관, 과거 기록의 트레이너 참조는 유지"*)·설계 03 §9(*"원장에 이관 이벤트"*)·목업(*"퇴사 시
담당 이관 플로우"*)이 이미 정했고, `Ledger.reason`의 `"transfer"`는 v1 enum에 선언만 된 채
**전 코드베이스에서 한 번도 쓰이지 않은 예약된 자리**다.

### 하드 삭제를 하지 않는 이유 (설계 근거)
```
① 원장(Ledger)은 append-only이고 잔여 세션의 유일한 출처다 — 행위자 uid를 지울 수 없다
② Stats.by_trainer 행은 스태프 목록이 만든다 — 삭제하면 과거 정산 비교표가 소급 파괴되고
   센터 총매출과 트레이너 합계가 어긋난다
③ 7개 엔티티(Member/Pass/Recurring/Booking/Team/Homework/WorkoutLog)에 평문 uid가 박혀 있고
   Firestore에 외래키가 없다 — 삭제해도 아무것도 막히지 않고 아무도 감지하지 못한다
④ 근로자 명부 3년(근기법 §42)·정산 기록 5년(국세기본법 §85조의3②) 보존 의무
```

### 엔티티 변경
```jsonc
Staff.status  추가   "active|inactive"  필드 부재/""는 로드 시 active로 승격
                     (v1.3 Policy 상한 승격 규약과 동형 — 기존 Firestore 문서 마이그레이션 불필요)
Staff.left_at 추가   RFC3339 — inactive일 때만. 서버가 기록(클라이언트 값 무시)
Stats.by_trainer[].status 추가
```
```
GET /v1/staff        inactive도 계속 반환한다. 이름 해석을 잃으면 3계층 196개 참조 지점이
                     원시 uid·빈 문자열로 붕괴한다(회원 목록은 "미배정"으로 거짓말하고,
                     스케줄 그리드는 이름 자리에 uid를 찍는다). 필터는 클라이언트가 status로.
                     role=member 응답에선 inactive 스태프의 profile을 빈 객체로 마스킹 —
                     이름은 남기되 퇴사자 이력을 회원에게 계속 홍보하지는 않는다.
Stats.by_trainer     inactive 행은 **해당 기간에 활동(sessions>0 또는 revenue>0)이 있을 때만**
                     포함한다. 정산 이력 보존과 현재 팀 목록 정합을 동시에 만족시킨다
                     (2년 전 퇴사자가 올해 표를 어지럽히지 않는다). owner 제외 규칙은 그대로.
```

### 신규 엔드포인트
```
PUT  /v1/staff/{uid}                          정정(owner 전용) — 머지 시맨틱
     {name?, color?, payout?, role?}          (PUT /members·/center와 동일. profile의 "통 교체"와 다름:
                                               이름·색·정산·역할은 서로 다른 편집 지점에서 온다)
     role 변경 시 Staff.Role과 UserIndex.Role을 함께 갱신한다 — 갈리면 "화면엔 트레이너인데
     권한은 대표"가 조용히 생긴다(인증은 UserIndex만, 정산표·배지는 Staff.Role만 읽는다).
     400 값 범위 · 400 본인 role 변경(자기 강등 금지) · 403 owner 아님 · 404 미존재
     409 마지막 활성 owner의 강등

POST /v1/staff/{uid}/transfer                 담당 일괄 이관(owner 전용)
     {to_uid}                                 to_uid="" = 미배정으로 회수(""는 3계층 1급 상태)
     Member.trainer_id · Pass.trainer_id · Recurring.trainer_id · 미래 confirmed Booking
     (+Slot.teams 사본)을 한 번에 재지정한다. 패스마다 원장에 reason="transfer" delta=0 기록
     (설계 03 §9 요구 — "왜 이 패스의 담당이 바뀌었나"에 원장이 답한다).
     인수자가 같은 슬롯에 이미 수업이 있으면 그 예약은 **옮기지 않고 conflicts로 보고**한다
     (트레이너 동시 1건 규칙을 이관이 우회하면 안 된다). 남은 예약은 퇴사를 계속 막는다.
     응답 {moved:{members,passes,recurrings,bookings}, conflicts:[{booking_id, slot_key}]}
     400 to_uid == uid · 403 owner 아님 · 404 미존재 · 409 to_uid가 inactive

POST /v1/staff/{uid}/deactivate               퇴사처리(owner 전용)
     {left_at?}                               생략 = 지금
     선행 조건 — 아래가 전부 비어야 통과한다. 이관 없이 비활성화하면 담당 회원이
     "목록엔 미배정으로 보이는데 미배정 필터·KPI엔 잡히지 않는" 발견 불가능 상태가 된다.
     한국에선 트레이너 퇴사가 사업자 귀책으로 해석돼 잔여 회차 환급 리스크로 이어지므로,
     재배정은 편의가 아니라 손해 방지 장치다.
       ① Member.trainer_id == uid 인 회원
       ② status=active|scheduled 인 Pass.trainer_id == uid
       ③ until 미경과 Recurring.trainer_id == uid
       ④ 미래 confirmed Booking.trainer_id == uid
     409 {error:"...", blockers:{members:[], passes:[], recurrings:[], bookings:[]}}
     400 본인 비활성화 · 400 이미 inactive · 409 마지막 활성 owner
     성공 시: Staff.status=inactive + left_at · UserIndex 강등(즉시 차단 — 인증이 요청마다
     이 문서를 읽고 캐시가 없다) · Firebase 계정 Disabled + RevokeRefreshTokens(재로그인 차단)
     · 프로필 사진 파기(v2.31 — **이 uid 명의**의 `staff/photos/<uid>-…` 파일만 지우고 photo_url=""; 외부·남의 URL은 무변경, 미구성 purger면 포인터 유지.
       파기 실패 시 500이고 status는 active로 남아 재시도가 멱등으로 수렴한다).
     ID 토큰 검증은 폐기 확인을 하지 않으므로 발급된 토큰은 최대 1시간 유효하다 —
     즉시성은 UserIndex가 담당하고 Firebase 비활성화는 2차 방어선이다.

POST /v1/staff/{uid}/reactivate               재입사 복원(owner 전용)
     status=active · left_at 소거 · UserIndex 복원 · Firebase Disabled(false)
     400 이미 active
```

### 기존 계약 변경
```
POST /v1/staff              퇴사자(inactive) 재초대는 409가 아니라 **재고용으로 완결된다**:
                            status를 active로 되돌리고 요청의 name·role·color·payout을 반영하되
                            **profile·offdays는 보존**한다(실수로 다시 눌러 경력 데이터가 날아가지
                            않게 — 단 photo_url 제외: 퇴사 시 파기되어 비어 있다, v2.31).
                            응답은 신규와 같은 201 + Staff.
                            → 복직 경로가 둘(이 경로와 reactivate)이고 응답이 구분되지 않으므로,
                              어드민은 초대 화면에서 "이미 있던 계정이면 기존 비밀번호가 유지된다"를
                              함께 안내한다(초대 메일 문구가 사실과 어긋나지 않게).
                            단, 그 uid가 **회원으로 연결된 계정(member_id 보유)**이면 409 —
                            승격하면 member_id가 지워져 그 사람이 자기 앱에서 잠긴다.
PUT  /v1/members/{id}       트레이너 호출 시 trainer_id를 본인으로 **강제**한다(POST와 동일 규칙).
                            종전엔 권한 검사 뒤 바디가 trainer_id를 덮어써도 재검증이 없어
                            트레이너가 자기 담당 회원을 임의의 uid로 넘길 수 있었다 —
                            담당 이관은 owner 전용 전담 엔드포인트로만 이뤄져야 감사 가능하다
POST /v1/bookings           담당 트레이너가 inactive면 400(휴무일 거부와 같은 자리)
POST /v1/recurrings         동일
```

## v2.1 정합 패치 — 비율 분모·차단 사유·발급 검증 (2026-08-23, P09, 이 섹션도 계약의 일부)

P06~P08에서 **한쪽만 고쳐 열려 있던 루프**를 닫는다. 서버가 비율만 주고 분모를 감춰
클라이언트가 "성과 0"과 "모수 없음"을 가를 수 없었고, 퇴사 차단은 예약·고정스케줄만 막아
회원권 발급으로 다시 열렸다.

### 엔티티 변경
```jsonc
Stats.noshow_d 추가   노쇼율의 분모(집계 대상 예약 수 = 완료 + 노쇼)
Stats.hw_d     추가   홈워크 완료율의 분모(배정 대상 수)

Stats.by_trainer[].noshow_d 추가   같은 의미의 코치별 분모. 키 이름은 top-level과 동일하다
Stats.by_trainer[].hw_d     추가
```
```
by_trainer에도 분모가 필요한 이유: 이번 기간에 수업이 0건인 코치가 "노쇼율 0.0%"로 표시돼
**최우수처럼 보인다.** 같은 표의 재등록률 칸은 이미 rereg_d로 "—"를 내는데 노쇼·홈워크만
0%를 단정하고 있었다.

⚠ 현재 한계(구현 갭 — 계약 위반은 아니나 소비 시 알아야 함): `range` 파라미터가 아직 무시되므로
이 분모들은 "해당 기간"이 아니라 **전 기간** 집계다. 어드민에 기간 필터 UI를 붙이는 시점에
분자·분모가 함께 기간을 타도록 고쳐야 한다. `hw_d`도 스케줄 반복 횟수가 아니라 배정 대상 수다.
```
```
두 값은 **비율 계산에 쓰인 바로 그 분모**여야 한다 — 따로 세면 어긋난다(서버는 한 함수에서
분자·분모를 함께 반환한다). omitempty를 붙이지 않는다: 0은 "집계 대상 없음"이라는 정보이고,
필드가 사라지면 클라이언트가 "구버전 서버"와 구별할 수 없다.

클라이언트 규약 — **3상태로 갈라 쓴다.** `omitempty`를 금지한 이유가 이 구분을 가능하게
하려는 것이다(0과 필드 부재가 뭉개지면 아래 셋째 줄이 첫째 줄로 위장한다).

| 상태 | 조건 | 표시 | 문구 |
|---|---|---|---|
| 값 있음 | 분모 > 0 | 퍼센트 — **진짜 0.0%도 그대로 보여준다** | 근거 수치 병기("완료·노쇼 12건 기준") |
| 집계 대상 없음 | 분모 `=== 0` | `—` | 서버가 준 사실만("집계 대상 0건") |
| 미상 | 필드 부재·null | `—` | **단정 금지**("집계 기준을 아직 받지 못했어요") |

셋째 줄은 구버전 서버에 붙었을 때만 나온다. 여기서 "배정이 없어요" 같은 **원인을 지목하는
단정**을 쓰면, 모르는 것을 아는 것처럼 말하게 된다 — 이 패치가 없애려던 오독이 다른 경로로
되살아난다. 둘째 줄에서 서버가 준 수치를 사실대로 옮기는 것은 단정이 아니므로 허용한다.
```

### 기존 계약 변경
```
POST /v1/staff/{uid}/deactivate 의 409 blockers.bookings
  v2.0: ["booking_id", ...]
  v2.1: [{"id":"bkg_x", "slot_key":"20260828-15"}, ...]
  근거: 어드민이 막힌 이유를 사람이 읽는 시각으로 보여주려고 예약 목록을 한 번 더 조회했다.
        서버가 이미 아는 값이라 왕복을 없앤다. 클라이언트는 v2.0의 문자열 배열도 받아들이도록
        정규화해 두는 편이 안전하다(구버전 서버와의 과도기).

POST /v1/passes                 trainer_id가 미존재이거나 inactive면 400
  "등록되지 않은 코치예요" / "퇴사 처리된 코치예요 — 담당을 먼저 이관해주세요"
  근거: v2.0이 예약·고정스케줄만 막아 루프가 열려 있었다. 발급은 담당이 **처음 박히는 자리**라
        여기서 통과한 오타가 예약·통계·정산의 원천이 된다.
  **빈 문자열("")은 통과**시킨다 — 미배정은 3계층 공통의 1급 상태이고(v1.5),
  `transfer {to_uid:""}`가 실제로 미배정 패스를 만든다. 거부하면 회수 결과와 모순된다.

POST /v1/members, PUT /v1/members/{id}   trainer_id에 같은 검증을 적용한다
  근거: 퇴사 선행 조건 ①이 "담당 회원 없음"인데 회원 생성·수정이 담당 uid를 검사하지 않으면
        발급보다 더 싸고 앞선 경로로 차단 조건이 되살아난다. 세 진입점(회원·발급·예약)이
        같은 규칙을 써야 루프가 닫힌다.
```

### 저장 순서 규약(비계약이지만 3계층이 의존한다)
```
목록 조회의 기본 정렬 = **문서 ID 오름차순**. Firestore는 orderBy 없는 쿼리를 __name__ 순으로
주는데, 인메모리 스토어는 맵 순회 순서라 로컬과 운영이 달랐다 — 앱의 "기본 회원권 선택"이
로컬에서 새로고침마다 바뀌는 증상으로 드러났다. 두 스토어가 같은 정렬 함수를 쓴다.
```

### 검증 규약(이번 패치에서 못박은 것)
```
와이어 형태는 **라우터를 태워 JSON 키로** 검증한다. Go 구조체로 디코딩하는 테스트는 json 태그
오타를 잡지 못하고, 그 오타 하나로 어드민의 모든 비율이 "—"가 되는데 양쪽 게이트가 모두
초록으로 남는다.
```

## v2.2 정합 패치 — /v1/me 표시 이름 (2026-08-23, P10, 이 섹션도 계약의 일부)

`GET /v1/me`가 이름을 주지 않아 **앱과 어드민이 각자 다른 우회**를 하고 있었다. 하나를 추가해
둘을 동시에 없앤다.

### 기존 계약 변경
```
GET /v1/me → {uid, role, center_id, member_id?, name?}

name  화면에 띄울 본인 이름. staff면 Staff.name, 연결된 member면 Member.name, 그 밖(가입 매칭 전
      미연결 계정 등)은 생략된다(omitempty).

**best-effort다** — 이름 조회가 실패해도 이 호출은 성공한다. /v1/me는 모든 클라이언트가 가장
먼저 부르는 부트스트랩 엔드포인트라, 여기서 실패하면 앱은 온보딩을 시작할 수 없고 어드민은
로그인 화면에 갇힌다. 표시용 이름 하나 때문에 그 위험을 지지 않는다.
클라이언트는 name이 비어 있을 수 있다고 보고 기존 폴백을 유지한다.
```

### 이 필드가 없어서 생기던 일(추가 근거)
```
앱   — 세션 복원 후 홈 헤더가 "김민지 님"이 아니라 센터명으로 떨어졌다. 최초 로그인 때는
       매칭 응답에 이름이 있어 정상으로 보이지만, 앱을 껐다 켜면 /v1/me만으로 세션을 세운다.
       같은 화면이 실행 시점에 따라 다르게 보였다(P09 실기기 점검에서 발견).
어드민 — 헤더의 이메일 원문 노출을 감추려고 GET /v1/staff 목록을 받아 uid로 조인했다.
       이름 하나 때문에 목록 조회에 의존하는 구조였다.
```

## v2.3 정합 패치 — 고정 스케줄·Home Work 스케줄 (2026-08-23, P12 감사, 이 섹션도 계약의 일부)

고정 스케줄의 "잔여 이내" 보장이 규칙 단위라 규칙을 두 번 만들면 무력화됐고(잔여 10회 →
confirmed 21건), 규칙을 지워도 그 규칙이 만든 예약은 남았다. `Homework.schedule`은 **판정하는
코드가 어디에도 없어** 저장만 되고 있었다 — 계약에 적혀 있던 값이 실제로는 아무 의미가 없었다.

### 기존 계약 변경
```
POST /v1/recurrings                      선행 생성 캡을 "이 요청이 만든 건수"가 아니라
                                         **이 패스의 살아있는(confirmed) 예약 총량** 기준으로
                                         잡는다: 생성 가능 = remaining − 기존 confirmed.
                                         이미 잔여를 다 채웠으면 400(규칙도 만들지 않는다).
                                         잔여는 완료 시점 차감(P4)이라 예약이 늘어도 줄지 않는
                                         값이다 — 뺄셈 없이는 캡이 성립하지 않는다.

POST /v1/recurrings                      until이 **오늘보다 이전**이면 400. 형식만 보던 자리에
                                         값 검사를 더한다(종전: 200 + 예약 0건 + 목록에서
                                         숨겨져 지울 수도 없는 유령 규칙).

GET  /v1/recurrings?include_expired=true 만료(until 경과) 규칙까지 포함해 반환. 기본(생략)은
                                         종전대로 숨긴다 — 숨기기만 하면 UI에서 지울 수 없다.

DELETE /v1/recurrings/{id}?keep_bookings= 204(빈 응답) → **200 {cancelled, kept}**.
                                         규칙 해제 시 그 규칙이 만든 **미래 confirmed 예약을
                                         함께 취소**한다(무차감 — 노쇼 유예를 소진하지 않는다.
                                         waive=true와 같은 취급). 이미 지난 회차는 이력이므로
                                         건드리지 않는다(kept로 집계).
                                         keep_bookings=true면 예약을 그대로 두고 규칙만 지운다.

GET  /v1/homeworks?member=&date=          date(YYYY-MM-DD, 옵션): 그날 schedule상 유효한 배정만.
                                         **role=member는 date를 생략해도 오늘이 기본** — 이
                                         목록이 곧 "오늘의 운동"이다. 스태프는 기본이 전체(관리
                                         화면), date를 주면 같은 판정이 걸린다. 형식 오류는 400.
```

### schedule 판정 규칙 (계약에 정의가 없어 층마다 달랐던 것 — 서버가 진실)
```
type 없음      → 항상 노출(스케줄 미지정 레거시 데이터 호환)
once          → [from, to] 구간. to가 없으면 **from 당일만**("한 번만"이 기한 없이 남지 않게)
weekly        → [from, to] 구간 안 + 오늘 요일이 days에 포함. days가 비면 매일
알 수 없는 type → weekly로 폴백

요일 표기는 Recurring.days와 동일한 mon|tue|wed|thu|fri|sat|sun(소문자 3글자).
이미 출시된 회원 앱의 순수 함수(homework_schedule_rules.dart)와 같은 규칙이다 — 서버가 다른
해석을 들고 오면 같은 배정이 앱과 어드민에서 다르게 보인다.
```

### stats.hw_rate 분모 재정의
```
hw_d(분모)에서 **기간이 끝난 배정(schedule.to 경과)을 제외**한다.

종전엔 종료일을 아무도 보지 않아 분모가 단조 증가했다 — 지난달 끝난 4주 배정이 영원히 남아
완료율이 시간이 갈수록 구조적으로 하락했고, 센터가 무엇을 해도 그 하락은 멈추지 않았다.

"오늘 대상 요일인가"가 아니라 "기간이 끝났는가"로 가른다: 주3회(mon/wed/fri) 배정은 화요일에도
진행 중인 배정이라, 요일로 거르면 hw_rate가 요일마다 출렁인다.
```

### 검증 규약 (schedule 값)
```
schedule.type   "" | once | weekly 만 허용(한글·오타 400)
schedule.days   mon~sun 소문자 3글자
schedule.from/to YYYY-MM-DD, from <= to
once            from(수행일) 필수 — 종료일을 만들 수 없으면 영구 노출이 된다

종전엔 {"type":"매일매일","days":["월요일"],"from":"어제","to":"내일"}가 200으로 저장됐다.
```

`POST /v1/homeworks`는 위 검증을 스토어 접근 **전에** 건다. 거부된 요청은 배정을 남기지 않는다 —
배정은 회원 앱에 즉시 뜨는 데이터라 "저장은 됐는데 400"이면 유령 과제가 남는다.

---

## v2.4 돈 무결성 패치 — 환불 기준액·발급 검증 (2026-08-23, P12 감사, 이 섹션도 계약의 일부)

서버가 "이 거래로 실제 오간 돈이 얼마인지"를 스스로 판정하지 않고 **클라이언트가 보낸 기록을
그대로 믿었다**. 원장은 append-only(P3)라 잘못 박힌 기록을 지울 수 없으므로, 쓰기 게이트와
읽기 캡을 **이중으로** 건다 — 게이트만으로는 이미 저장된 레코드를 막지 못한다.

실측으로 재현된 것: 550,000원 회원권에 결제를 한 번 더 기록 → 환불 견적 **5,445,000원**.
반대로 일시불(회차 미기재)로 기록 → 환불 견적 **0원** + 회원권 `refunded` 확정(복구 API 없음).
즉 **결제를 정확히 기록할수록 손해가 커지는** 역방향 인센티브가 있었다.

### 기존 계약 변경
```
POST /v1/passes            total_sessions >= 1 (0·음수 400) · paid_amount >= 0 (음수 400)
                           paid_amount == 0은 **허용** — 무료 체험권은 실제 영업 조건이고
                           어떤 계산도 망가뜨리지 않는다. 0회 패스는 그 자체로 쓸 수 없어 거부.
                           검증은 스토어 쓰기 전 — 원장·계약에 흔적을 남기지 않는다.

POST /v1/payments          Σ(해당 패스의 기존 결제 total) + total <= pass.paid_amount 초과 시 400.
                           **건수 제한이 아니라 합계 상한** — 카드+현금 분할 기록은 그대로 통과한다.
                           기준축을 total로 잡은 건 매출 집계(revenueByMonth)와 같은 축이라서다:
                           중복 기록은 환불과 매출을 함께 부풀린다.

POST /v1/payments          installments[].paid_at 미래 시각 400 (시계 오차 5분 허용)
```

### 일시불 결제의 의미 확정
```
installments 생략(일시불) → 실수납 = total 로 집계. 필드는 여전히 **선택**이다.

"필수화"를 택하지 않은 이유: 계약이 필수로 못박은 적이 없고 어드민 일시불 경로가 실제로 이
필드 없이 보낸다(breaking change). 결정적으로 Outstanding()은 **이미** 같은 레코드를
"낼 것 없음(0)"으로 세고 있었다 — 청구 쪽과 수납 쪽이 정반대를 말하던 모순이 결함의 본체다.
불변식: PaidSum + Outstanding == Total
```

### 환불 정산식
```
refund = max( min(실수납, pass.paid_amount) − usage − penalty , 0 )

실수납의 **상한은 계약가**다. 실수납 집계에서 미래 paid_at 회차는 제외한다 — 쓰기 게이트와
읽기 정산이 같은 경계(now + 5분)를 써야, 게이트가 받아준 결제를 정산이 몇 분간
"받은 적 없는 돈"으로 떨어뜨리지 않는다.

트레이드오프: 계약가가 낮게 오입력된 패스는 덜 환불된다. 검증 안 된 기록을 믿고 더 주는 쪽보다
낫다 — 나간 돈은 돌아오지 않는다. 캡이 걸린 사건은 서버 로그에 남긴다(캡은 지혈이고,
중복 기록 자체는 사람이 정정해야 한다).
```

---

## v2.5 보안 패치 — 쓰기 경로 담당 경계 (2026-08-23, P12 감사, 이 섹션도 계약의 일부)

읽기 경로는 여러 라운드 감사를 거쳐 촘촘한데(`memberScopeID`·`checkMemberScope`), **쓰기 4곳에
스코프 검사 자체가 없었다**. 읽기는 "남의 것이 보이나"를 묻기 쉽고 쓰기는 "남의 것에 쓸 수 있나"를
물어야 하는데, 후자를 묻는 테스트가 없었다. 전부 curl 실측으로 재현됨.

```
POST /v1/workout-logs   booking_id **없이** 보내면 trainer는 담당 회원만(403).
                        booking_id가 있으면 종전대로 예약 기준 — 담당이 아닌 코치도 자기
                        예약에는 기록할 수 있다(의도적). 회원은 코치별로 패스를 따로 가질 수 있어
                        주담당과 그 회차를 실제로 가르친 코치가 다를 수 있고, 그때 담당 경계로
                        막으면 정상 기록이 거부된다.

POST /v1/homeworks      target_member_ids 검증: 미존재 404 · 스코프 밖 403 ·
                        my_members의 subset은 trainer_id 담당과의 교집합 ·
                        individual은 필수(빈 배열 400) · 중복 ID는 1건으로.
                        후보 집합과 부상 맵이 **같은 출처**에서 나온다 — 둘이 갈리면 한쪽만
                        검사되는 구멍이 다시 생긴다(부상 자동제외 우회, P39).
                        individual의 부상 자동제외 미적용은 종전대로(규칙 변경 아님).

POST /v1/hw-checks      hw_id 실존 404 · 그 회원에게 배달되는 배정이어야 함 403 ·
                        done 길이 = items 수 400 ·
                        date 생략 = 오늘(KST) · 형식 불량 400 ·
                        스태프 대행은 담당 회원만 403.
                        빈 date를 400이 아니라 오늘로 채우는 이유: 같은 파일의
                        POST /v1/workout-logs가 이미 "생략=오늘/불량=400"이라 같은 이름 필드가
                        다르게 동작하면 그 자체가 함정이다. 실제 해악은 "date 미전송"이 아니라
                        **어떤 질의로도 못 찾는 레코드**였다 — date:""는 앱의 ?date=오늘에
                        안 잡히는데 stats.hw_rate는 날짜를 안 보고 완료로 집계했다.

POST /v1/checkin (tap)  trainer는 본인 담당 예약만 403 — complete/noshow와 동일 규칙.
                        상태 검사보다 **앞에** 둔다(400/200 차이로 예약 상태를 캐지 못하게).
```

⚠ **운영 영향**: tap 체크인이 담당 예약으로 좁혀졌다. 데스크를 트레이너 계정으로 운영 중이면
**대표(owner) 계정을 써야** 한다.

### 아직 없는 것 (계약 갭 — 되돌릴 수단의 부재)
```
납부 취소     PayInstallment에 역이 없다. 오클릭이 영구 확정된다(어드민 2단 확인은 지혈).
환불 취소     RefundPass에 역이 없다. 실측에서 0원 환불이 확정까지 갔는데 복구 수단이 없었다.
노쇼·취소 되돌리기  LedgerReason에 revert가 정의돼 있으나 이를 만드는 코드가 없다.
계약가 정정   PUT /v1/passes/{id}가 없다 — paid_amount 오입력은 재발급이 유일한 경로다.

넷 다 "원장 append-only"와 정합하는 **역전 원장**으로 설계해야 한다(삭제가 아니라 상쇄 기록).
```

---

## v2.6 원자성 패치 — 돈·세션이 움직이는 경로의 트랜잭션화 (2026-08-23, P13, 이 섹션도 계약의 일부)

원자성이 제대로 된 곳은 **예약 상태 전이 하나뿐**이었다(`BookAtomic`·`CancelAtomic`·
`SetBookingStatusWithLedger` — 동시 8건 중 정확히 1건 통과, 슬롯 정원도 6명 동시에 3명만 통과 실측).
발급·환불·홀딩은 전부 스토어 트랜잭션 **밖에서** 2~3개의 독립 호출로 쪼개져 있었다.

**이 결함들은 Memory 스토어에서 재현되지 않는다**(전역 뮤텍스라 경합 창이 나노초). `go test`는
전부 통과하고 프로덕션에서만 터진다 — 전화번호 정규화 사고(v1.7)와 정확히 같은 종류다.
Firestore 에뮬레이터 실측으로 재현한 것: 동시 환불 2건이 **둘 다 200**(495,000원 두 번 승인,
원장 −10회) · 발급 3회 **HTTP 500 세 번인데 실제로는 60회 지급** · 동시 홀딩 5건이 전부 200인데
패스엔 1건만 남고 원장엔 5건 · 잔여 2회 패스에 4건 예약 후 완료 → **잔여 −2**.

### 기존 계약 변경
```
POST /v1/bookings          새 400: "이미 잡힌 예약 N건이 잔여 M회를 채웠어요 —
                           기존 예약을 정리하거나 회차를 추가해주세요"
                           ⚠ **remaining > 0 이어도 거부될 수 있다.** 잔여는 완료 시점에만
                           차감되므로(P4) 예약을 잡아도 줄지 않는다 — 뺄셈이 없으면 잔여 2회로
                           예약을 무제한 잡을 수 있다.
                           생성 가능 = remaining − (이 패스의 살아있는 confirmed 예약 수)
                           POST /v1/recurrings(v2.3)와 같은 규칙이다.

POST /v1/passes/{id}/hold  새 400: "같은 기간으로 이미 일시정지돼 있어요(중복 신청)"
                           재시도·더블클릭이 더는 유효기간을 공짜로 늘리지 않는다.
                           정책 상한(횟수·총 일수) 검사도 트랜잭션 안으로 내려 동시 신청 우회를 막았다.

POST /v1/passes/{id}/refund 동시 2건 중 1건은 400 "이미 환불 처리된 패스예요".
                           200은 항상 1회뿐이고, 응답 quote가 **실제 마감액**이다
                           (견적을 트랜잭션이 본 원장으로 계산 — 승인액과 마감이 어긋나지 않는다).

GET  /v1/passes            **정렬: valid_from 오름차순(동률 시 id).** 종전 계약은 순서를 규정하지
                           않았고, 문서 ID 체계가 두 스토어에서 달라 프로덕션에서는 사실상 무작위였다
                           (실측: 1→6 순서로 발급했는데 목록은 5,6,4,3,2,1). 회원 앱의 기본 패스
                           선택이 제비뽑기가 되고 있었다.

Update 계열 전반           없는 ID는 **404**. 종전 Firestore는 `.Set()` upsert라 **유령 문서를 만들고
                           200**을 돌려줬다(Pass·Payment·Contract·JoinRequest). Memory는 404였다.
DELETE /v1/recurrings/{id} 없는 ID면 404(종전 Firestore는 204).
```

### 신규 도메인 에러
```
domain.ErrNoSessionsLeft → 400 "남은 회차가 없어요 — 이미 잡힌 예약이 잔여 회차를 채웠어요"
```

### 두 스토어 시맨틱 통일 규약
```
Memory와 Firestore는 같은 인터페이스를 만족한다고 해서 같게 동작하지 않는다. 18개 프로브 중
13개에서 동작이 갈렸다. 앞으로의 드리프트를 막기 위해 **공통 계약 스위트**를 둔다:

  internal/store/conformance_test.go   — 같은 테스트 함수를 두 구현에 돌린다
  기본 `go test`                        → Memory
  `go test -tags firestore_emulator`   → 에뮬레이터 (JDK 21 필수, CI 옵트인 잡)

새 스토어 동사를 추가하면 이 스위트에 케이스를 함께 넣는다.
```

### 설계 제약 (새 동사를 쓸 때 지켜야 할 것)
```
UpdatePassWithLedger(centerID, passID, mutate PassMutator, entry *Ledger)
  — 환불·홀딩·재개·이관 4갈래가 공유한다. 갈래마다 전용 동사를 만들면 두 구현에 8개를 써야 하고
    판정 로직이 스토어로 샌다. 대신 두 제약을 인터페이스에 못박았다:
      ① mutate는 **순수**해야 한다 (트랜잭션이 재시도된다)
      ② mutate 안에서 **Store를 다시 부르면 안 된다** (Memory 스토어 교착)
    → 정책 같은 외부 값은 트랜잭션 **밖에서 미리 읽어 캡처**한다.

IssuePass(pass, ledger, contract)  — 발급 3단을 하나로. 계약은 조립만 하고 저장은 트랜잭션이 한다.
CancelAtomic(..., entry *Ledger)   — 컷오프 내 취소의 페널티 원장을 같은 트랜잭션에. 종전엔 취소는
                                     확정되고 페널티만 소실됐고, 재시도하면 "confirmed 상태의 예약만
                                     취소할 수 있어요" 400이라 **영구 소실**이었다.
```

### 남은 갭
```
환불 뒷정리 중 **미납 회차 종결(waived_at)**은 트랜잭션 밖이다 — 미서명 계약 무효화는 v2.15에서
마감과 한 트랜잭션이 됐다(후보 ID를 밖에서 추리고 안에서 점읽기 재판정 — 컬렉션 잠금 없이 접합).
결제는 여전히 센터 전체 스캔으로 찾으므로 마감을 먼저 확정하고 뒷정리 실패는 보이는 500으로
남긴다(재시도 시 "이미 환불 처리된 패스예요"라 이유는 설명된다).

pass.remaining 스냅샷은 완료·노쇼 경로에서 여전히 원장 합과 벌어진다. **모든 판정은 원장 재계산을
거치므로 현행 버그는 아니지만**, DB에 권위 있어 보이는 틀린 숫자가 남는다.

원장 동시각 정렬은 여전히 비결정(두 스토어가 다름). 표시 순서에만 영향.
```

---

## v2.7 정합 패치 — 센터 정책이 말하는 대로 집행되게 (2026-08-23, P14, 이 섹션도 계약의 일부)

정책 화면은 대표가 **돈과 약관을 정하는 자리**인데, 저장한 값과 실제로 집행되는 값이 달랐다.

### 위약금율 — 네 자리가 서로 다른 숫자를 말하고 있었다
`Policy`는 0~1을 전부 허용하는데 `RefundQuote`가 `MaxPenaltyRate`(10%)로 하드 캡했다. 그 결과:

| 자리 | 30% 저장 시 | |
|---|---|---|
| 어드민 화면 | "저장됐어요" + 푸터 "현재 위약금율 30%" | 거짓 |
| **계약서 스냅샷** | `penalty_rate: 0.3` — **회원이 이 조항에 서명한다** | 거짓 |
| 회원 앱 `GET /v1/center` | `0.3` | 거짓 |
| 실제 환불 공제 | **10%** | 유일한 진실 |

실측: 100만원 20회권 미사용 환불 → 견적 `penalty 100,000`(30%면 300,000).
대표는 30% 공제를 예상하고 회원은 30% 조항에 서명했는데 실제로는 10%만 공제된다.
반대편으로는 **집행하지 않을 조항을 발행**하는 것이라 계약서 자체가 무의미해진다.

```
PUT /v1/center   penalty_rate 유효 범위 0~1 → **0~0.1**
                 초과 시 400 "penalty_rate는 0~0.1 사이여야 해요
                             (상한 10% — 환불에서 실제로 공제되는 최대치)"

GET /v1/center   policy.penalty_rate는 항상 <= 0.1.
                 검증을 지나지 않은 값(구문서·콘솔 수기 수정)은 **읽는 자리에서** 접는다.
                 저장 시점에 접지 않는 이유: 머지 PUT이 초과값을 이어받아, 용량 하나만
                 바꾸려 해도 400이 나는 잠금이 생긴다.

계약 생성       contract.penalty_rate 스냅샷 = min(policy, 0.1). 정상 경로에선 정책값과 동일.

RefundQuote     런타임 캡은 **유지**한다 — 이미 30%로 서명된 계약이 실재할 수 있다.
```

**방향 판단**: "캡을 남기고 경고만"이 아니라 **상한을 정책으로 끌어올렸다**. 캡만 남기면 저장된
0.3이 아무 데서도 집행되지 않으면서 푸터·회원앱·계약서에는 계속 나타난다 — 거짓말하는 자리를
줄이는 게 아니라 늘린다.

### 정책 변경의 적용 시점 — 소급 여부를 명문화
```
즉시·소급  cancel_cutoff_hours · slot_capacity · 통계 임계값
           → **이미 잡힌 예약에 그대로 적용된다.** 취소 시점에 정책을 새로 읽기 때문이다.
계약 스냅샷 penalty_rate — 발급 시점 값이 그 계약에 고정된다(소급 안 됨)
```
실측: 24h에 예약 → 48h로 변경 → 취소 → **`noshow_waived` 원장 생성**(유예 소진), 2회차엔
`remaining` 실차감. 정책값은 되돌릴 수 있어도 **그 사이 생긴 원장 항목과 차감은 남는다.**
어드민은 컷오프를 **올릴 때만** 확인 단계를 세우고, 새로 페널티 구간에 들어가는 확정 예약
실건수를 세어 보여준다.

### 홀딩 상한의 적용 범위 (계약에 없던 한정어)
```
max_holds_per_pass · max_hold_total_days 는 **회원 셀프 홀딩에만** 걸린다.
owner·trainer가 어드민에서 거는 홀딩은 상한을 지나지 않는다(정책을 로드하지 않는다).
0은 저장할 수 없다(400) — "홀딩 완전 금지"를 표현할 방법이 현재 없고, 최소 1회는 항상 허용된다.
```

### 어드민 요청 형태 (계약 변경 아님)
```
PUT /v1/center 에 **바뀐 필드만** 싣는다. 서버 머지 시맨틱은 원래 그렇게 설계돼 있었는데
(클라이언트가 빠뜨려도 grace_once·revenue_target이 초기화되지 않게), 폼이 항상 10필드를
전송해 그 보호를 무력화하고 있었다 — 다른 창에서 먼저 저장한 값을 통째로 되돌린다.
```

### 남은 갭
```
P14 이전에 30%로 서명된 계약은 문서에 0.3이 남고 어드민이 그대로 표시한다(실공제는 10%).
서명된 문서를 소급 수정하지 않는다는 판단 — 표시에 "실제 공제 10%" 각주가 필요한지는 미결.

예약 단위 컷오프 스냅샷은 넣지 않았다. 넣으면 앱의 freeCancel 판정(센터 정책값 사용)과
서버가 예약마다 갈려 새 3자 불일치가 생긴다.
```

---

## v2.8 문서 정합 — 계약이 라우터와 벌어진 자리 (2026-08-23, P14, 이 섹션도 계약의 일부)

이 문서는 단일 진실 소스인데, 위 섹션들이 쌓이는 동안 **맨 앞 엔드포인트 요약 블록이 갱신되지
않아** 구현과 벌어졌다. 아래는 전부 라우터·서비스 소스를 직접 읽어 확인한 사실이다.

### 스태프 엔드포인트는 2개가 아니라 8개다
요약 블록에는 `GET /v1/staff`와 `POST /v1/staff/{uid}/offdays`만 있는데 실제 라우트는:
```
GET    /v1/staff                      목록(회원도 200 — payout은 0으로 비움, 퇴사자 profile 마스킹)
POST   /v1/staff                      온보딩: 계정+레코드+인덱스 (v1.8, owner 전용)
POST   /v1/staff/{uid}/offdays        휴무일 설정
PUT    /v1/staff/{uid}/profile        트레이너 프로필 (v1.6 — **어느 섹션에도 명시가 없었다**)
PUT    /v1/staff/{uid}                정정 (v2.0)
POST   /v1/staff/{uid}/transfer       담당 이관 (v2.0)
POST   /v1/staff/{uid}/deactivate     퇴사 (v2.0)
POST   /v1/staff/{uid}/reactivate     재입사 (v2.0)
POST   /v1/staff/{uid}/photo         프로필 사진 업로드 (v2.25, owner 전용 — 미구성이면 503)
```

### 모든 라우트가 `/api/v1`에도 미러돼 있다
```
r.Route("/v1", v1)  +  r.Route("/api/v1", v1)      (P07)

어드민은 Firebase Hosting에서 서비스되고 /api/** 가 Cloud Run으로 rewrite되는데,
Hosting은 경로 접두사를 벗겨주지 않아 서버에 /api/v1/... 로 도착한다. 이 미러 덕에
개발(vite 프록시가 /api를 벗김)과 운영이 같은 클라이언트 코드로 동작한다.
계약은 /v1/* 만 말하고 있었지만 **어드민이 실제로 쓰는 경로는 /api/v1/*** 이다.
```

### `GET /v1/center`의 마스킹 대상 (모호했던 것)
```
revenue_target: **owner가 아니면 0** — 즉 trainer도 0이다.
                종전 서술은 "member 공개, 매출 목표 제외"로 읽혀 trainer가 빠지는지 불분명했다.
penalty_rate:   GetPolicy(Normalize)를 거쳐 **실제로 공제되는 값**으로 내려간다(v2.7).
```

### 채워지지 않는 필드 — 계약에 있으나 서버가 쓰지 않는다
```
Contract.sha256    정의만 있고 쓰는 코드 0곳
Contract.pdf_path  정의만 있고 쓰는 코드 0곳

지금의 "서명"은 **동의 기록**이지 위·변조를 증명하는 문서가 아니다. 전자계약을 법적 근거로
쓰려면 이 둘을 실제로 채워야 한다 — 필드가 있다는 이유로 이미 된 것으로 읽히면 안 된다.
```

### 체형사진 `storage_path`의 형태 (서버·앱·규칙 3자가 묶여 있다)
```
members/{memberId}/body/{yyyyMMdd}-{pose}-{direction}-{epochMillis}.jpg

배포된 storage.rules가 강제하는 제약이고, 어기면 업로드가 403으로 조용히 막힌다:
  · 세그먼트가 정확히 4개 — 날짜를 폴더로 파면 {fileName} 와일드카드가 매칭에 실패한다
  · 경로 키는 **memberId**(uid 아님) — 규칙이 uid를 Firestore users/{uid}.member_id로 옮겨 심어 대조
  · contentType image/* · 10MB 미만 · **삭제 금지**(allow delete: if false)
서버는 이 문자열을 그대로 저장할 뿐 형태를 강제하지 않는다. 계약에 적어 두지 않으면
클라이언트가 경로를 바꾸는 순간 규칙에서만 터진다(서버 테스트는 통과한다).
```

### 검토가 필요한 갭
```
CHECKIN_QR_TOKEN을 돌려주는 엔드포인트가 없다. 어드민의 데스크 QR 화면은 대표가 값을
수기 입력하는 것에 의존하고, 그 값이 서버 설정과 다르면 스캔이 전부 실패하는데 **어디에도
그 사실이 드러나지 않는다**. GET /v1/center에 토큰 지문(해시 앞자리)만이라도 실어
어드민이 대조할 수 있게 하는 방안을 검토할 값어치가 있다.
```

---

## v2.9 인바디 쓰기 경로 — 회원 셀프 수기 입력 (2026-08-23, P18, 이 섹션도 계약의 일부)

`POST /v1/inbody`는 v1.9부터 **회원 본인 기록 생성을 허용**하고 있었지만(`checkMemberScope`의
`p.IsMember()` 분기), 그 경로를 앱에 노출할 준비가 되어 있지 않았다. 착수 전 실제 상태:

| 결함 | 결과 |
|---|---|
| 6개 숫자를 **한 번도 검증하지 않았다** | `weight: -5`, `bmr: 0`, `pbf: 999`가 전부 200 |
| 미래 측정일이 통과했다 | `2099-12-31`이 목록 맨 앞(최신) = 차트의 마지막 점 |
| 같은 회원·같은 날 중복 무제한 | 그날 점이 둘로 갈려 "직전 대비 증감" 기준 불명 |
| **정정 수단 0개**(PUT·DELETE 부재) | 오타 1건 = 차트 영구 오염, 복구는 콘솔 수기 편집뿐 |

오입력을 되돌릴 수단이 없는 상태에서 폼을 여는 것은 오류 생성 속도만 올리는 것이다 —
**폼보다 서버 안전장치가 먼저다.**

### 설계 결정 — 이미지 저장 없음 · OCR 없음 (v1)

- **결과지 이미지를 저장하지 않는다.** 결과지에는 ID·이름·나이·성별·신장이 함께 인쇄되어
  **식별정보와 건강정보가 결합된 원본**이고, Storage 규칙의 `allow delete: if false` + 서버
  삭제 API 부재로 동의 철회·탈퇴 시 **파기 수단이 0**이다. 숫자 6개만 받으면 그 결합이
  생기지 않는다. → `storage.rules` 무변경(교차 서비스 IAM·2문서 상한 영역을 통째로 회피).
- **OCR을 넣지 않는다.** 제품정의 문서가 이미 v1 OUT으로 결정한 항목이고("결과지 사진 파싱"),
  결정적 근거는 정확도가 아니라 되돌릴 수단이었다 — 이번에 DELETE가 생겨 그 근거는 절반
  해소됐지만, PBF=BFM/체중 항등식으로 검산되는 3개와 달리 **SMM·VFL·BMR은 검산 근거가 없어
  조용히 틀린다.** v2에서 넣더라도 **자동 저장은 하지 않는다** — OCR은 폼을 미리 채우는
  것까지이고 사람이 6칸을 확인하고 저장한다. **v2.9의 수기 입력 폼이 곧 v2 OCR의 실패 경로다.**
- 앱 "분석"의 범위: 6지표 수치 + 직전 대비 증감(방향 인식: SMM↑좋음 / PBF·BFM·VFL↑나쁨 /
  체중·BMR 중립) + SMM/PBF 2시리즈 추이선까지. 추세선·예측·목표 진척률은 넣지 않는다
  (인바디는 수분·식사·시간대로 흔들려 2~3점 추세로 미래를 말하면 틀린다 — 해석은 코치 몫).

### 기존 계약 변경

```
POST /v1/inbody   요청 필드는 종전 8개 그대로(member_id/date/weight/smm/bfm/pbf/vfl/bmr).
                  ⚠ source는 **요청으로 받지 않는다** — 실으면 400(DisallowUnknownFields).
                    서버가 Principal로 판정: 회원=member_self, 스태프=staff.
                    이 값이 곧 삭제 권한의 근거라 클라이언트가 정할 수 없어야 한다.

                  새 400 — 값 범위(6지표 전부 필수, 0 거부):
                    체중 20~300kg · SMM 5~120kg · BFM 1~200kg · PBF 1~70% ·
                    VFL 1~30 · BMR 500~5000kcal
                    ⚠ 0을 거부하므로 "선택 입력" 필드가 성립하지 않는다 —
                      JSON 미입력 숫자는 0.0으로 직렬화된다. 클라이언트는 6개를 다 받아야 한다.
                    VFL 상한 초과 힌트: "내장지방'레벨'이에요 — 단면적(cm²)이 아니에요"
                      (인바디 270은 레벨 1~20, 770/970은 단면적 cm² ~100을 인쇄한다)
                    BFM 상한 초과 힌트: "체지방량이에요 — 제지방량(FFM) 칸이 아니에요"

                  새 400 — 교차 검증(체/제 오기 차단):
                    smm < weight · bfm < weight · smm + bfm <= weight
                    FFM은 체중의 70~90%라 개별 범위는 태연히 통과한다 —
                    합계 검사만이 체/제 오기를 잡는다.

                  새 400 — 미래 측정일(KST): "측정일은 미래일 수 없어요"

                  새 409 — 같은 회원·같은 날 중복. **문구가 호출자의 실제 권한에 따라 갈린다**:
                    기존 기록을 지울 수 있는 호출자(스태프, 또는 자기 셀프 기록과 충돌한 회원)
                      → "{date} 인바디 기록이 이미 있어요 — 기존 기록을 지우고 다시 저장해주세요"
                    지울 수 없는 회원(기존 기록이 센터 입력분)
                      → "{date} 기록은 센터에서 입력한 거예요 — 정정이 필요하면 담당 코치에게
                         요청해주세요"
                    호출자가 할 수 없는 행동을 문구가 지시하면 안 된다(P14 인쇄 안내문과 같은 원칙).

GET /v1/inbody    응답에 source 추가: "member_self" | "staff" | ""(v2.9 이전 레코드 — 백필 없음).
                  ⚠ 클라이언트 DTO에서 **반드시 옵셔널**로: required 파싱이면 기존 레코드 전부가
                    던진다(파싱 실패 1건이 기록 탭 3개를 죽인 전례 — v2.5).
                  ""는 "회원 본인이 넣었다는 근거가 없다"로 해석한다 — 삭제 판정에서 staff와
                  같은 취급(member_self로 승격 금지).

                  목록 순서 확정: **date 내림차순, 동률이면 문서 ID 오름차순.**
                  종전엔 동률 순서가 Memory(맵 순회 — 호출마다 뒤바뀜)와 Firestore(고정)에서
                  갈렸다. 순서가 곧 화면이다(passes의 sortPasses와 같은 이유 — v2.6).
```

### 신규 엔드포인트

```
DELETE /v1/inbody/{id}    인바디 삭제 — **오입력을 되돌리는 유일한 수단**. 200 {"deleted": true}

  권한: checkMemberScope 통과 후,
        · 스태프: 출처 무관 삭제 가능(정정은 데스크의 일상 업무)
        · 회원 본인: source == "member_self"인 기록만 → 그 외 403
          (코치가 넣은 기록을 회원이 지우면 상담 근거가 사라진다. ""도 회원 삭제 불가)
  404: 없는 ID(재시도가 "지웠다"를 두 번 보고하지 않는다)

  동의(sensitive)는 검사하지 않는다 — 삭제는 동의 철회 **이후에** 더 필요한 동작이다
  (생성만 P8 게이트를 지난다).

  ⚠ PUT은 만들지 않는다. 정정 = 삭제 + 재입력(삭제 후 같은 날짜 재입력은 중복에 안 걸린다 —
    원본이 이미 없다). 6개 숫자 레코드에 부분 수정의 이점이 없고 API 면적이 절반이다.
    409 안내·삭제 확인 다이얼로그 문구가 이 사실에 직접 의존하므로 계약에 못 박는다.
```

### 남은 갭

```
중복 차단 경합         쓰기 직전 ListInbody 1회 기반 — 동시 요청 2건이 둘 다 통과할 수 있다.
                       완전 차단은 (회원,날짜) 합성 문서 ID upsert 또는 트랜잭션(hwChecks 방식)이
                       필요하고 그건 기존 문서 마이그레이션이 따라온다. v1 실사용의 사고 모양
                       (응답 유실 후 재탭)은 순차라 이걸로 잡힌다.

GET /v1/inbody 스코프  checkMemberScope다 — **owner는 동의 없이도 읽는다.** 체형사진
                       (checkBodyPhotoAccess)은 owner도 동의 게이트를 지난다(P37). 같은 P8
                       민감정보인데 비대칭 — 운영 파급이 있어 별도 결정 사항으로 남긴다.

OCR(v2) 착수 게이트    ① 서버 안전장치 완료(=이 절) ② 센터의 인바디 기종 1개 확정
                       ③ 실물 결과지 20~30장으로 필드별 정답률 + "6개 동시 정답률" 실측
                       ④ iOS 비용 수용(+38MB, iOS 15.5 강제, Podfile 부재) ⑤ 자동 저장 금지 유지
```

### 배포 순서

`decodeJSON`이 `DisallowUnknownFields`다 → **서버 먼저, 앱·어드민 나중.**
어드민 인바디 폼은 이 절과 함께 6지표 검증으로 갱신됐다(종전엔 체중만 검사 — 서버 검증이
켜지는 순간 100% 실패할 상태였다, P18 적대적 검증에서 발견).

---

## v2.10 회원별 체형 포즈 시퀀스 (2026-08-24, P21, 이 섹션도 계약의 일부)

포즈 4종(차렷·T자·전굴·OH스쿼트)은 **개발자가 임의로 정한 값**이었고 앱 enum·서버 상수·어드민
union 세 곳에 하드코딩돼 있었다. 센터마다 촬영 프로토콜이 다르므로 회원별로 정할 수 있게 연다.

### Member.body_poses 신설
```
타입      [{key: string, label: string}]  (선택 필드)

응답      GET/POST/PUT 응답에서 **항상 실효 시퀀스를 구체화**한다 — 비어있지 않은 배열 보장.
          회원 커스텀이 없으면 서버가 센터 기본 4종을 채워 내려보낸다.
          → 앱·어드민은 기본값을 몰라도 된다(구서버 대비 클라 폴백만 유지).

PUT       스태프 전용. 배열 = 교체 · null 또는 [] = 센터 기본으로 초기화 · **필드 생략 = 유지**.
          생략 시 유지가 핵심이다 — 어드민의 기존 회원 수정 페이로드는 body_poses를 싣지 않으므로,
          유지가 아니면 이름 한 번 고칠 때마다 대표가 짜 둔 시퀀스가 날아간다(회귀 테스트로 고정).
          회원 본인 PUT은 종전대로 consent 전용 — body_poses를 실으면 400(구조체가 다름).

저장      nil = "센터 기본 사용"이라는 **의미를 갖는다**. 다른 슬라이스 필드처럼 nil→[] 정규화를
          하지 않는다. 저장 상태는 nil 또는 검증된 커스텀 둘뿐이고, 구체화는 **응답 사본에만**
          한다 — 저장 객체에 하면 필드 없는 머지 PUT이 기본값을 커스텀으로 굳혀, 그 회원만
          이후 센터 기본 변경을 영영 못 따라온다.
          구 문서(필드 부재)는 json 라운드트립상 자동으로 nil → 기본. 마이그레이션 불요.

검증      key    ^[a-z0-9_]{1,24}$   ← **하이픈 금지가 핵심**
          label  트림 후 1~12자
          개수   1~8, key 중복 금지
          위반 시 400(domain.ErrInvalidBodyPoses).

          하이픈을 막는 이유: Storage 파일명이
          `{yyyyMMdd}-{pose}-{direction}-{epochMs}.jpg`로 **'-'를 조각 구분자**로 쓴다.
          key에 '-'가 들어가면 파일명 파싱이 모호해지고(고스트가 직전 사진을 고를 때 쓰는
          epochMs 타이브레이커), 대문자·슬래시·유니코드는 경로 세그먼트·URL 인코딩을 깬다.
          레거시 4종(stand/tpose/fold/ohsquat)은 이 규칙을 통과하므로 비파괴다.
```

### POST /v1/body-photos 검증 신설
```
pose          위 슬러그 규칙 위반 시 400. 종전엔 **무검증**이라 무엇이든 저장됐다.
storage_path  빈 문자열 400 — 가리킬 파일이 없는 레코드는 타임라인이 영구 실패 타일을 그리고,
              체형사진에는 삭제 API가 없어 되돌릴 수단도 없다.
```

### 레거시·미지 key 렌더 보장 (세 층 공통 규칙)
```
라벨 해석 순서   회원 body_poses의 label → 레거시 4종 고정 맵 → raw key 그대로
표시 목록        회원 실효 시퀀스 ∪ 사진 데이터에 실재하는 key (시퀀스 순 + 잔여 key 뒤에)

대표가 포즈를 바꿔도 **이미 찍은 사진은 계속 보여야 한다.** 앱의 fromWire가 미지 key를
stand로 폴백하던 것을 제거한다(폴백하면 남의 포즈 사진이 차렷 앨범에 섞인다).
```

### 범위 밖
```
storage.rules 무변경 — pose는 파일명 조각일 뿐이고 슬러그 규칙이 경로 안전을 보장한다.
규칙의 firestore.get 평가당 2문서 상한에 여유가 없어, 건드리지 않는 것 자체가 설계 목표였다.
GET /v1/body-photos 무변경 — 포즈 필터는 계속 클라이언트 몫.
```

---

## v2.11 회원탈퇴 — 인앱 계정 삭제와 파기·보존 경계 (2026-08-25, P22, 이 섹션도 계약의 일부)

서버에 회원을 지우는 경로가 **하나도 없었다.** 58개 라우트 중 DELETE는 bookings·recurrings·
inbody 셋뿐이었다. Apple App Store Review Guideline **5.1.1(v)** 는 계정 생성을 지원하는 앱에
**앱 안에서의 계정 삭제**를 요구하고, 고객센터 안내나 웹 링크로 대체할 수 없다 — 이 상태로는
심사를 통과하지 못한다(P21 껍데기 감사가 "스토어 심사 3종" 중 하나로 이미 지목했다).

### 하드 삭제를 하지 않는 이유 (v2.0 스태프 절과 같은 자리)

서로 반대로 당기는 두 의무가 동시에 걸린다.

| 축 | 근거 | 요구 |
|---|---|---|
| 파기 | 개인정보보호법 §21① — 처리 목적 달성 시 **지체 없이 파기** | 지워라 |
| 보존 | 전자상거래법 §6 + 시행령 §6① — **계약·청약철회 5년 / 대금결제·재화공급 5년** | 남겨라 |

충돌이 아니다. §21① **단서**가 "다른 법령에 따라 보존하여야 하는 경우"를 예외로 두고, §21③이
그때 **분리 저장·관리**를 요구한다. Guideline 5.1.1(v)도 같은 구조의 예외를 둔다 — *"법적
목적으로 보관해야 한다면 그 필요를 구체적으로 고지하고 나머지는 삭제하라."*

여기에 더해 이 시스템 고유의 제약이 둘 있다:

```
① 원장(Ledger)은 append-only이고 잔여 세션의 유일한 출처다(P3 불변식2) —
   행을 지우면 확정된 환불 정산액·통계가 소급으로 어긋난다. **가명화가 정답이다.**
② 회원 문서를 지우면 5년 보존하기로 한 Pass·Payment·Contract가 어드민 화면에서
   **누구 것인지도 모르는 채 깨진다**(전부 member_id로 조인한다). v2.0이 퇴사 스태프를
   GET /v1/staff에서 계속 반환하기로 한 것과 같은 근거다.
```

### 신규 엔드포인트

```
DELETE /v1/me                          회원탈퇴(회원 본인 전용). 바디 없음.

  응답 200 {
    deleted:true, member_id, withdrawn_at,
    purged:{body_photos, inbody, workout_logs, hw_checks, checkins, recurrings,
            consult_requests, join_requests},          ← 뒤 2칸 v2.26 신설
    retained:{passes, payments, contracts, ledger, bookings},
    cancelled_bookings, remaining_sessions
  }

  403 호출자가 owner|trainer — 스태프에겐 지울 회원 레코드가 없고, 회원으로도 연결된
      계정이면 UserIndex가 사라져 **센터가 대표를 잃는다**(복구 API 없음. v1.9 guardNotStaff·
      v2.0 락아웃 가드와 같은 계열). 스태프의 이탈 경로는 POST /v1/staff/{uid}/deactivate다.
  ~~404 member_id 미연결(가입 매칭 전) — 지울 대상 자체가 없다.~~
  ⚠ v2.27 개정: **미연결 계정도 200이다** — 지울 대상이 없다는 전제가 틀렸다. 가입 요청 시트에
      이름·번호를 직접 적은 사람(join_requests)과 Firebase 계정(전화번호)이 있다(P55 C-3, §36
      삭제 요구권). 미연결 분기(deleteUnlinkedAccount)는 Firebase 계정 삭제 → join_requests 파기 →
      UserIndex 삭제로 끝나고 응답 키 집합은 회원 경로와 같다(member_id는 빈 값, purged.join_requests
      외 전부 0). 상세는 v2.27 절 "DELETE /v1/me — 미연결 계정".
  400 이미 탈퇴한 계정(정상 경로로는 도달하지 않는다 — 인덱스만 남은 잔여 상태의 이중 방어선)

  ⚠ **잔여 회차가 남아 있어도 막지 않는다.** 검토 후 기각: Guideline 5.1.1(v)는 사업상 상태를
    이유로 앱 내 삭제를 막는 것을 예외로 인정하지 않는다. 막을 실익도 없다 —
    Pass·Payment·Contract·Ledger가 전부 보존되므로 탈퇴 후 환불 요구에도 정산 근거가 살아 있다.
    대신 응답의 remaining_sessions로 고지한다(앱이 확인 화면·완료 안내에 그대로 띄운다).

  ⚠ **되돌리는 API가 없다**(탈퇴는 종단 상태 — 복직이 있는 스태프 퇴사와 다르다).
    ~~성공하면 UserIndex가 사라져 같은 uid의 두 번째 호출은 404다.~~
    ⚠ v2.27 개정: 두 번째 호출은 404가 아니다 — 인덱스가 없으면 미연결 분기로 들어가
    200(purged 전부 0, Firebase DeleteUser는 없는 계정을 성공으로 본다)으로 끝난다. 즉 재시도가
    멱등이 됐다(토큰은 계정 삭제 후에도 최대 1시간 유효 — provision.go DeleteUser 주석).
```

### 파기·보존 경계 (계약의 핵심)

```
파기(즉시 삭제)
  Member.name → "탈퇴한 회원"(고정 라벨) · phone → "" · channel → "" · trainer_id → ""
  Member.flags(부상 메모=건강 관련 정보) · consent(전이 시각 포함) · last_visit_at ·
    app_linked → false · body_poses → nil
  체형사진 BodyPhoto — **Firestore 메타 + Cloud Storage 원본 파일**
  인바디 Inbody · 수업기록 WorkoutLog(coach_note 포함) · 홈워크 체크 HwCheck ·
    체크인 CheckinRecord · 고정 스케줄 Recurring
  가입 요청 JoinRequest(**이름·전화번호 원본**) · 재등록/상담 요청 ConsultRequest(note) ← v2.26 신설
  UserIndex(uid→member_id) · **Firebase Identity Platform 계정**

보존(비식별 상태로 5년)
  Ledger(append-only 불변식) · Pass · Payment · Contract · 과거 Booking
  → 이름·번호가 사라져 member_id라는 **가명만 붙은 거래 기록**으로 남는다.
  ⚠ v2.17 개정: 계약은 **무접촉이 아니다** — 미서명(draft/sent) 계약은 문서를 보존한 채
    voided로 종결된다(서명 주체가 파기된 뒤의 "서명 대기"는 사실이 아니다). signed는
    상태·증적 그대로 불가침. 문서 수는 변하지 않는다(retained.contracts 동일).
  ⚠ v2.26 개정: 위 "가명만 붙은"은 **Contract에 대해서는 문자 그대로가 아니다** — 스탬프된
    계약의 vars에 {{회원명}}·{{회원 전화번호}}가 얼어 있어 5년 동안 함께 남는다(v2.18 §D ①).
    의도된 잔존이고 파기하지 않는다(근거는 v2.26 절). **고지 대상**이라 개인정보처리방침·
    계정삭제 안내가 이 사실을 적어야 한다.
```

전자상거래법 §6②는 거래기록과 관련된 **성명 보존을 허용**하지만 **일부러 쓰지 않는다.**
허용은 의무가 아니고, 보존의 목적("그 거래가 있었다")은 금액·회차·날짜·계약 상태로 이미
완전하다. 남길 이유 없는 식별자를 남기면 그건 §21①이 말하는 불필요해진 개인정보다.

**phone을 비우는 것이 이 설계의 급소다** — 남기면 `FindMemberByPhone`이 계속 매칭해서 같은
번호로 재가입할 때 `join/match`가 탈퇴 레코드로 되돌려 붙인다(탈퇴가 조용히 무효화된다).

### 엔티티 변경

```jsonc
Member.status         "active|dormant" → "active|dormant|withdrawn"
                      필드 부재/""는 로드 시 active로 승격(v2.0 Staff.status와 동형 — 마이그레이션 불요)
Member.withdrawn_at   추가. RFC3339, omitempty. 서버가 기록(클라이언트 값 무시).
                      보존기간 5년의 **기산점**이라 재시도가 이 값을 미래로 밀지 않는다.
```

```
GET /v1/members       탈퇴 회원도 계속 반환한다. 필터는 클라이언트가 status로 한다
                      (v2.0 GET /v1/staff와 같은 규약 — 이름 해석을 잃으면 보존 기록이 깨진다).
                      어드민은 기본 목록에서 감추고 "탈퇴 N" 칩으로 꺼내 본다.
```

### 탈퇴 회원에 대한 후속 차단 (전부 400 — 호출자 권한이 아니라 대상 상태의 문제)

```
POST /v1/passes             "탈퇴한 회원이에요 — 회원권을 발급할 수 없어요"
POST /v1/bookings           "탈퇴한 회원이에요 — 예약을 잡을 수 없어요"
POST /v1/homeworks          대상에 탈퇴 회원이 있으면 400(배달될 앱이 없는데 hw_d 분모만 오른다)
PUT  /v1/members/{id}       "탈퇴한 회원이에요 — 정보를 수정할 수 없어요"
                            ⚠ 이 가드가 없으면 스태프 PUT 한 번으로 이름·번호가 다시 박혀
                              **파기가 조용히 무효화된다.** 회원 self(consent) 경로도 함께 막는다.
GET  /v1/stats              탈퇴 회원은 어느 지표에도 들어가지 않는다. 특히 **unassigned가 급소**다 —
                            가명화가 trainer_id를 ""로 회수하므로 거르지 않으면 탈퇴자 전원이
                            "담당 배정 필요"로 잡혀 대표가 영원히 줄지 않는 할 일을 보게 된다.
                            long_absent도 같다(last_visit_at을 지웠으니 전원이 장기미방문이 된다).
```

### 실행 순서 (계약이 아니라 운영 안전 규약 — 재시도 가능성이 여기서 결정된다)

```
① 체형사진 원본 파일(Storage)  ─┐ 외부 시스템. 실패해도 DB가 그대로라
② Firebase 계정 삭제            ─┘ **같은 ID 토큰으로 재시도**된다(둘 다 멱등)
③ 미래 confirmed 예약 무차감 취소  (CancelAtomic — 슬롯 사본까지 비운다. 페널티 원장 없음)
④ 미서명(draft/sent) 계약 voided 종결 (v2.17 신설 — TransitionContract CAS, signed 불가침)
⑤ 가입 요청 파기                  (v2.26 신설 — Store.DeleteJoinRequestsByUID. 최상위 컬렉션이라
                                  ⑥의 센터 스코프 스윕이 구조적으로 닿지 못한다)
⑥ 가명화 + 건강·이용 기록 파기     (Store.PurgeMemberPersonalData — 기록 먼저, 회원 문서 마지막)
⑦ UserIndex 삭제                 (호출자의 권한 자체를 없애므로 반드시 마지막)

메타보다 **파일을 먼저** 지운다: 반대로 하면 경로를 아는 유일한 문서가 먼저 사라져 민감정보
원본이 버킷에 영영 남고, 그 잔존은 어느 화면에도 드러나지 않아 발견조차 불가능하다.
VerifyIDToken은 계정 삭제를 확인하지 않아 토큰이 최대 1시간 유효하다 — ②가 앞에 있어도
④⑤⑥⑦의 재시도가 가능한 이유다(v2.0 퇴사 처리 주석과 같은 사실).

⑤가 ⑥보다 **앞**인 것이 규약이다(v2.26): 뒤에 두면 실패한 순간 회원 문서는 이미 가명화돼
재시도가 400("이미 탈퇴 처리된 계정이에요")에 막히고 **이름·전화번호가 영구히 남는다** —
④를 ⑥ 앞에 둔 것과 같은 이유다.
```

### 체형사진 원본 파기 — v2.9가 적어 둔 갭을 닫는다

```
v2.9: "Storage 규칙의 allow delete: if false + 서버 삭제 API 부재로 동의 철회·탈퇴 시
       파기 수단이 0이다."

Storage 보안 규칙은 **클라이언트 SDK에만** 적용되고 Admin SDK는 지나지 않는다. 규칙은
그대로 두고(`storage.rules` 무변경 — 교차 서비스 IAM·평가당 2문서 상한을 건드리지 않는다)
서버가 메타와 파일을 짝으로 지운다. 규칙 주석의 *"정리는 서버 몫"* 이 이제 실재한다.

새 환경변수 STORAGE_BUCKET (예: rize-218c1.firebasestorage.app)
  미설정이면 파일 파기가 no-op이 되고 **기동 로그에 경고**가 남는다. 기동을 막지는 않는다 —
  이 값이 없다고 예약·결제·수업기록이 멈춰야 할 이유가 없다.
  ⚠ Cloud Run 서비스 계정에 해당 버킷의 objects.delete 권한이 필요하다(IAM — 콘솔 작업).
```

### 앱 요구사항 (심사 대상)

```
마이 탭에 "회원탈퇴" 진입점 → 확인 화면(전체 화면) → 체크박스 + 확인 다이얼로그 → DELETE.
확인 화면은 **무엇이 지워지고 무엇이 왜 남는지**를 항목별로 고지한다 — Guideline 5.1.1(v)의
"구체적으로 고지" 요건이다. "일부 정보는 보관됩니다"로는 충족되지 않는다.
성공 시 즉시 로그아웃 + /login. 남아 있으면 이후 모든 새로고침이 403이라 성공한 탈퇴가
에러 화면으로 보인다.
```

### 남은 갭

```
탈퇴 사유 수집 없음      리텐션 분석에 유용하지만 v1은 수집하지 않는다 — 목적 외 개인정보를
                        파기 직전에 새로 받는 모순을 피한다. 넣는다면 회원과 분리된 익명 집계여야 한다.
보존기간 만료 후 자동 파기 없음  withdrawn_at + 5년이 지난 문서를 지우는 배치가 없다. 지금은
                        withdrawn_at이 "언제 지워도 되는지"의 근거로만 남는다(어드민 상세에 표시).
                        실제 파기는 사람이 판단한다 — 자동 삭제 배치는 되돌릴 수 없는 쓰기라
                        운영 신뢰가 쌓인 뒤에 붙인다.
약관·개인정보처리방침 화면  P21이 지목한 스토어 심사 3종 중 나머지 둘은 여전히 없다.
                        이 절은 그중 "계정 삭제" 하나만 닫는다.
```

---

## v2.12 회원권 상태는 유효기간에서 계산한다 (2026-08-25, P25, 이 섹션도 계약의 일부)

### 무엇이 바뀌나

`Pass.status`는 이제 **응답 시점에 오늘(KST) 날짜로 계산된 값**이다. 저장된 값이 그대로
나오지 않는다.

```
refunded  (저장된 종단 상태 — 날짜보다 우선)
scheduled (today < valid_from)
expired   (today > valid_until)
active    (그 외)
```

`valid_from`·`valid_until`이 비었거나 "YYYY-MM-DD"로 파싱되지 않으면 **저장값을 그대로**
돌려준다. 빈 `valid_until`을 문자열 비교하면 어떤 날짜보다도 작아 전 회원권이 expired로
뒤집히기 때문이다.

경계는 **예약 검사와 같다**: `valid_from` 당일·`valid_until` 당일 모두 active다
(예약은 `slotDate < valid_from || slotDate > valid_until`을 거부한다). 두 판정이 갈리면
"이용 중인데 예약이 안 되는" 날이 생긴다.

### 왜

종전에는 `expired`·`scheduled`를 **대입하는 코드가 서버에 한 줄도 없었다**. `POST /v1/passes`가
무조건 `active`를 저장하고, 그 뒤 상태가 바뀌는 건 환불뿐이었다. 그래서 유효기간이 지난
회원권이 영원히 `active`로 내려갔고, `GET /v1/stats`의 재등록률은 분모가 `status=expired`
개수라 항상 0이었다.

배치 잡으로 뒤집지 않는 이유: `remaining`이 이미 같은 방식(원장 합산의 파생값)이고, 잡은
"안 돌면 조용히 틀린다"는 실패 모드를 만들며, 홀딩이 `valid_until`을 연장했을 때 굳어버린
expired를 되살리지 못한다.

### 적용 범위

| 엔드포인트 | 적용 |
|---|---|
| `GET /v1/passes` | ○ |
| `GET /v1/members` (임베드 `passes[]`) | ○ |
| `POST /v1/passes` (발급 응답) | ○ |
| `POST /v1/passes/{id}/hold` · `/resume` · `/refund` | ○ (응답만) |
| `GET /v1/stats` | ○ (집계 입력) |

**저장은 바뀌지 않는다.** Firestore/Memory의 `status`는 계속 `active`(또는 `refunded`)다.

### 예약 가능 상태 (동작 변경)

`POST /v1/bookings`와 `POST /v1/recurrings`의 상태 게이트가
`status == "active"` → **`status ∈ {active, scheduled}`** 로 바뀐다.

이건 새 정책이 아니라 **원래 의도대로 고친 것**이다. 종전 게이트 바로 아래 주석이
"valid_from이 미래인 재등록 패스도 유효기간 안의 슬롯이면 선예약 허용(v1.3)"이라고
적혀 있었고, 그 동작을 검증하는 테스트도 이미 있었다 — 저장 상태가 늘 `active`라
게이트와 주석이 충돌하는 걸 아무도 못 봤을 뿐이다.

날짜 적합성은 종전대로 슬롯별로 따로 본다. `expired`·`refunded`·모르는 값은 거부한다
(화이트리스트 — 상태가 늘어도 "모르면 열어준다"로 기울지 않게).

### 클라이언트가 맞춰야 하는 것

- **`status == "active"`로 "쓸 수 있는 회원권"을 판정하던 곳**은 `scheduled`를 포함해야
  한다. 안 그러면 서버는 받아주는 선예약을 화면이 막는다.
- 반대로 `expired`가 **실제로 내려오기 시작한다** — 종전에 죽어 있던 "만료" 분기가 살아난다.
- 회원권 목록의 정렬·필터가 `active` 개수에 의존한다면 값이 달라진다(만료된 것이 빠진다).

---

## v2.13 사업자 정보 — 법정 고지를 등록된 데이터로 채운다 (2026-08-26, P26, 이 섹션도 계약의 일부)

### 무엇이 바뀌나

`GET /v1/center` 응답에 **`business`가 policy와 나란히** 붙는다. `PUT /v1/center`는
`{policy?, business?}`를 받는다(둘 중 하나 이상 필수). 그리고 **무인증 공개 경로가 하나
생긴다** — `GET /v1/public/business`.

법정 고지 문서 4장 + 목차(`admin/public/legal/*.html`)는 v2.12까지 상호·대표자·등록번호·
보호책임자를 `{{...}}` 플레이스홀더로 비워 두고 있었다. 그 자리를 HTML에 손으로 박으면
상호 한 번 바뀔 때 5장을 고쳐야 하고, 한 장을 빠뜨리면 **법정 고지가 서로 다른 사업자를
가리킨다**. 센터가 등록하고 서버가 제공하는 값으로 옮긴다.

### 엔티티 신설 — `Business` (12칸)

```
biz_name              사업자명(상호)
ceo_name              대표자명
biz_reg_no            사업자등록번호   — 숫자 10자리. 저장 시 ###-##-##### 로 정규화
address               사업장 주소
phone                 대표 전화        — 숫자 8~15자리 + '-' + 선행 '+'. 회원 휴대폰(010 정규화)과
                                        다른 규약이다 — 02·1544 같은 유선·대표번호가 정상이라
                                        010으로 접으면 실제로 거는 번호가 사라진다
email                 대표 이메일
privacy_officer_name  개인정보 보호책임자 성명   ┐ 개인정보보호법 §31 — 처리방침 필수 기재
privacy_officer_title 개인정보 보호책임자 직책   │
privacy_officer_email 개인정보 보호책임자 이메일 ┘
privacy_dept          권리행사 접수 부서명
privacy_manager       접수 담당자 성명
effective_date        약관 시행일      — YYYY-MM-DD. 실재하는 날짜여야 한다(2026-02-30 거부)
```

**`policy` 안이 아니라 옆에 둔다.** policy는 서비스 동작을 바꾸는 운영 다이얼이고 이쪽은
동작을 하나도 바꾸지 않는 신원 정보다. 섞으면 ① 두 종류의 실패가 한 sentinel로 뭉뚱그려지고
② 어드민 정책 폼의 "바뀐 필드만 저장" 비교가 중첩 객체를 참조 비교해 늘 "바뀜"으로 읽히며
③ **무인증 응답에서 정책을 걷어내는 일을 매번 손으로** 하게 된다 — 한 번 빠뜨리면 연 매출
목표가 익명에게 나간다.

### 부분 입력은 저장되지만 complete가 아니다 (이 절의 핵심)

```
Validate()    채워진 칸의 **형식만** 본다. 빈 칸은 통과 — 미등록·부분 입력은 오류가 아니다.
IsComplete()  12칸이 전부 채워졌는가. 공백만 있는 칸은 빈 칸으로 센다.
complete      서버가 계산해 응답에 실어 보내는 파생값(저장하지 않는다).
```

저장 가능 조건과 **게시 가능 조건을 분리한** 것이 이 설계다. 전부 채워야만 저장되게 하면
대표는 사업자등록증을 보며 아는 칸부터 채울 수가 없어 결국 메모장에 적어 두게 된다. 반대로
부분 입력을 완성으로 취급하면 개인정보처리방침이 보호책임자 연락처가 빠진 채 "시행 중"으로
게시된다 — 형식 미비가 아니라 **법정 기재사항 누락**이고, 고지 자체가 흠결이 된다.

`complete`를 클라이언트가 다시 세지 않고 서버가 내려보내는 이유도 같다: 층마다 세면 어느
문서는 시행 중이고 어느 문서는 초안인 상태가 만들어진다(위약금율이 네 자리에서 다른 숫자를
말하던 v2.7과 같은 모양의 결함).

### 기존 계약 변경

```
GET /v1/center  → {center_id, policy, business}
                  business = Business 12칸 + complete:bool
                  **역할별 마스킹 없음** — 애초에 법정 고지 대상이라 무인증으로도 나가는 값이다.
                  여기서만 가리면 화면마다 다른 답이 된다. revenue_target 마스킹(v2.8)은 그대로.

PUT /v1/center  → 바디가 {policy?, business?}. 둘 다 없으면 400.
                  **보낸 덩어리만 처리한다** — policy만 보내는 기존 호출이 business를 지우지 않는다.
                  응답은 GET과 같은 모양(저장 후 재조회) — 캐시를 그대로 갈아끼울 수 있다.
                  owner 전용(v1.4 그대로).

  policy   : 머지  (누락 필드 초기화 방지, v1.4)
  business : 통 교체 ← policy와 **반대**다.
             근거는 PUT /v1/staff/{uid}/profile과 같다: 폼이 늘 12칸 전부를 제출하고,
             **잘못 적은 칸을 비워서 지우는 일**이 실제로 필요하다. 머지면 한 번 들어간
             오타를 지울 방법이 없다. policy가 머지인 이유는 그쪽이 자주 만지는 운영
             다이얼이라 동시 편집 충돌이 실재하기 때문인데, 사업자 정보는 개업 때 한 번
             넣고 상호·주소가 바뀔 때만 손대는 값이다.
```

### 신규 엔드포인트 — 유일한 무인증 v1 경로 (v2.29부터는 둘 — `GET /v1/public/center` 참조)

```
GET /v1/public/business        인증 불필요. /api/v1/public/business 에도 미러(P07).

  응답 200 { biz_name, ceo_name, biz_reg_no, address, phone, email,
             privacy_officer_name, privacy_officer_title, privacy_officer_email,
             privacy_dept, privacy_manager, effective_date, complete }
  헤더     Cache-Control: public, max-age=300

  미등록이어도 200 + 빈 값 + complete:false다(404가 아니다) — 문서가 "불러오지 못함"과
  "아직 등록 전"을 구분해 초안 배너를 유지할 수 있어야 한다.
```

**왜 무인증인가**: 법정 고지 HTML은 로그인 없이 열리는 웹 페이지다. 앱 스토어 심사자·
미가입 방문자·회원이 모두 보는 문서라 인증을 요구할 수가 없는데 `/v1/*` 전체에는
`auth.Middleware`가 걸려 있다. 그래서 인증 그룹 **밖에** 이 경로 하나만 붙였다
(`router.go` — v1 클로저 안이 아니라 밖이다. 인증되는 라우트 목록 한가운데 무인증 경로가
섞이면 다음 사람이 그 줄을 인증되는 것으로 읽는다).

**의도적으로 내보내지 않는 것** — 이 목록이 계약이다.

```
✗ policy 전체            slot_capacity · cancel_cutoff_hours · grace_once · penalty_rate ·
                        rereg_window_days · long_absent_days · expiring_days ·
                        max_holds_per_pass · max_hold_total_days
✗ revenue_target        연 매출 목표. authenticated trainer에게도 안 나가는 값이다(v2.8)
✗ center_id             경로 스코프에 쓰이는 내부 식별자. 문서가 알 이유가 없다
✗ 회원·직원·예약 관련 일체
```

마스킹 목록을 관리하는 방식이 **아니라** 전용 응답 타입(`BusinessView`)으로 잠갔다 —
`GET /v1/center`에 필드가 늘어도 여기로 새지 않는다. 마스킹이었다면 언젠가 하나를 빠뜨린다.
테스트가 공개 응답의 **키 집합을 통째로** 고정하므로, 키를 늘리는 것은 반드시 의식적인
결정이 된다(`TestPublicBusinessExposesOnlyLegalFields`).

**파라미터를 받지 않는다.** 익명 호출자가 `center_id`를 고를 수 있으면 그 자체로 센터 존재
여부를 훑는 수단이 된다. v1은 단일 센터 전제(`config.DefaultCenterID`)라 고를 것도 없다 —
다센터가 되면 그때는 호스트명·문서 경로처럼 **요청자가 정하지 않는 축**으로 갈라야 한다.

**읽기가 문서를 만들지 않는다.** `GetPolicy`는 최초 접근 시 기본 정책을 지연 시딩하는데
`GetBusiness`는 하지 않는다 — 무인증 읽기가 쓰기를 유발하면 익명 요청으로 문서를 양산할 수
있는 자리가 된다.

### 저장 위치 (스토어 규약)

`business`는 `centers/{centerID}` 문서의 `business` 맵이다 — 정책과 **같은 문서**에 산다.
그래서 `SavePolicy`가 통 `Set`에서 **머지 쓰기(`firestore.MergeAll`)로 바뀌었다.**
안 바꾸면 대표가 예약 용량 하나 바꾼 순간 사업자 정보가 조용히 사라지고, 그 결과가
**법정 문서 5장이 동시에 초안으로 되돌아가는** 것으로 나타난다.

Memory는 맵이 둘이라 이 결함이 재현되지 않는다 — 공통 계약 스위트에
`BusinessAndPolicyDoNotClobberEachOther`를 넣어 에뮬레이터 러너에서 잡히게 했다
(실제로 뮤테이션 확인: 통 `Set`으로 되돌리면 에뮬레이터에서 사업자 정보가 전 칸 빈 값으로 돌아온다).

### 법정 문서가 값을 쓰는 방식 (계약이 아니라 규약 — 세 층이 여기서 만난다)

```
1. HTML에는 {{...}} 가 **한 글자도 없다.** 각 자리는
     <span class="ph" data-biz="biz_name">(사업자명 미정)</span>
   로 미리 렌더돼 있고, 스크립트는 그 위에 값을 덮어쓸 뿐이다.
   → fetch가 실패하든 JS가 꺼져 있든 **원시 플레이스홀더가 보일 수 없는 구조**다.

2. fetch는 상대 경로 /api/v1/public/business 하나뿐이다(firebase.json이 /api/** 를
   Cloud Run으로 리라이트 → 동일 오리진 → CORS 설정 불필요, 외부 호스트 0개).

3. 초안 배너(#draft-notice)는 **셋 다** 성립할 때만 사라진다:
     complete === true  &&  effective_date 비어있지 않음  &&  화면에 남은 미기재 0개
   무조건 지우면 반쪽짜리 문서가 "시행 중"인 척하게 된다. 실패 시에는 그대로 둔다(fail-closed).
```

### 배포 순서

`decodeJSON`이 `DisallowUnknownFields`다 → **서버 먼저, 어드민 나중**(v2.9와 같은 규약).
어드민이 `{"business":{...}}`를 보내는데 서버가 그 필드를 모르면 400이다. 반대 방향은 안전하다 —
서버가 먼저 올라가도 `business`를 안 보내는 기존 어드민은 그대로 동작한다(보낸 덩어리만 처리).

법정 문서 HTML은 어느 순서로 올려도 안전하다: 서버가 아직 없으면 fetch가 실패하고
사전 렌더된 `(항목명 미정)` + 초안 배너가 그대로 남는다.

### 남은 갭

- **사업자등록번호 체크섬을 서버가 보지 않는다.** 형식(10자리)만 강제하고, 체크디짓은
  어드민에서 **차단하지 않는 경고**로만 띄운다 — 오탐 한 번이 유일하게 고칠 수 있는 사람을
  영구히 막기 때문이다. 등록번호의 실제 유효성은 사람이 사업자등록증과 대조해야 한다.
- **문서 본문 자체는 여전히 사람이 검토해야 한다.** 이 절이 채우는 건 기재사항 12칸이지
  약관 조항의 법적 타당성이 아니다.
- 다센터가 되면 `GET /v1/public/business`의 센터 선택 축을 정해야 한다(위 참고).


## v2.14 체형사진 삭제 — 누가 눌렀느냐로 의미가 갈린다 (2026-08-27, P31, 이 섹션도 계약의 일부)

코드에는 라우트 3개가 이미 있었는데 이 문서에 없었다. 계약에 없는 라우트는 **없는 것과
같다** — 앱·어드민이 무엇을 기대해도 되는지 판정할 근거가 사라진다.

### 라우트

| 메서드 | 경로 | 권한 | 의미 |
|---|---|---|---|
| `DELETE` | `/v1/body-photos/{id}` | 본인 / 담당 코치 / 대표 | 아래 §분기 |
| `POST` | `/v1/body-photos/{id}/restore` | **스태프만** | 유예 중인 사진 복원 |
| `POST` | `/v1/body-photos/purge` | **대표만** | 기한 지난 것 즉시 파기 |

라우터에서 **정적 경로(`/purge`)를 `{id}` 앞에 둔다.** 뒤에 두면 `purge`가 id로 잡힌다.

### 분기 — 이게 이 절의 핵심이다

**회원 본인이 삭제하면 즉시 완전 파기한다(유예 0, 복원 경로 없음).** 정보주체의 삭제권
행사이고, 배포된 개인정보처리방침이 *"동의 철회, 삭제 요청 또는 탈퇴 시 **지체 없이**
파기"*라고 약속하고 있다. 30일 유예를 붙이면 그 문장이 거짓이 된다.

**스태프가 삭제하면 `deleted_at`만 찍고 30일 뒤 파기한다.** 이쪽은 운영 오조작이라
되돌릴 시간이 필요하다 — 잘못 지운 사진은 **그날의 몸이라 다시 못 찍는다.** 단 유예는
되돌리기 위한 것이지 계속 보이라는 게 아니므로 **목록에서는 즉시 사라진다.**

`restore`가 스태프 전용인 이유도 같다. 회원 삭제는 되돌릴 대상이 없는데 복원 경로가
열려 있으면 "지체 없이 파기"와 모순되는 문이 생긴다.

### 순서 — Storage 먼저, 메타 나중

메타를 먼저 지우면 오브젝트가 **기록 없이** 버킷에 영원히 남는다. 지웠다는 사실조차
추적할 수 없어 다음 훑기도 그것을 찾지 못한다. Storage 삭제가 실패하면 **메타를 남긴
채 에러를 돌려** 다음 훑기가 다시 시도하게 한다.

### 파기 훑기 — 스케줄러가 없다

Cloud Scheduler API가 이 프로젝트에 켜져 있지 않다. 그래서 `ListBodyPhotos`가 호출될
때마다 기한이 지난 것을 **최대 25건씩** 함께 파기하고(조회 지연을 늘리지 않기 위한
상한), 대표는 `POST /v1/body-photos/purge`로 직접 돌릴 수 있다. 스케줄러를 켜면 이
엔드포인트를 그대로 호출하면 된다.

### 응답

- `DELETE` → 스태프면 `deleted_at`이 찍힌 사진 객체, 회원이면 `204`.
- 유예가 지난 사진에 `restore` → `400`. 지나고도 되살아나면 "30일 뒤 파기"가 거짓이 된다.

### 앱이 함께 해야 하는 것

삭제에 성공하면 **로컬 바이트 캐시도 비운다**(`BodyPhotoLoader.evict`). 목록 갱신이
실패하면 방금 "완전히 지워졌다"고 들은 사진이 캐시에서 그대로 다시 그려진다.

### 문서 동기화 (배포 차단이었다)

배포된 `privacy.html`·`sensitive-consent.html`이 *"앱에서 직접 삭제하는 기능은 아직
제공되지 않습니다"*라고 적고 있었다. 앱에 삭제 버튼이 나가는 순간 그 문장이 거짓이 되므로
**같은 배포에 함께** 나가야 한다.

---

## v2.15 계약 전이 원자화 — 서명 증적은 경합으로 지워지지 않는다 (2026-08-29, P37, 이 섹션도 계약의 일부)

계약 상태 전이(send·sign·void)가 전부 read-modify-write였다(P36 감사 H). 스토어의
`UpdateContract`가 문서 통째 Set(CAS 없음)이라 ① 재발송 vs 서명 경합 시 **signed 문서가
sent 사본으로 덮여 signed_at·signer_ip(법적 증적)가 소실**될 수 있었고 ② 환불의 무효화
루프(마감 트랜잭션 **밖**) vs 서명 경합 시 "signed는 무효화 불가"(v1.5) 불변식이 깨질 수
있었다. v1.4.1의 "재발송↔서명 경합 가드"(저장 직전 재확인)는 트랜잭션 밖이라 창을 좁혔을 뿐
원리적으로 닫지 못했다. v2.6이 돈·세션 경로에 세운 트랜잭션 동사 패턴을 계약에도 적용했다 —
정책은 도메인·서비스 콜백에 남고, 스토어는 트랜잭션 안에서 다시 읽은 문서 위에 그 콜백을
집행만 한다.

### 라우트·표면 무변경

`POST /v1/contracts` · `POST /v1/contracts/{id}/send` · `POST /v1/contracts/{id}/sign`의
요청/응답/상태코드는 그대로다(전이 위반 400 · 없는 계약 404 · 권한 403 · 환불 패스 400).
바뀐 것은 **판정이 일어나는 자리**다: 전이 규칙(CanTransitionContract)·환불 패스 가드·
first_sent_at 한 번만 기록이 전부 스토어 트랜잭션 안에서 **다시 읽은** 문서 위에서 재판정된다.
경합 창에서의 에러 문구 하나가 통일됐다: 종전 v1.4.1 경합 가드가 그 창에서만 내던 "이미
서명이 완료된 계약이에요"는 이제 다른 전이 위반과 같은 "현재 계약 상태에서는 처리할 수
없어요"로 온다(400 동일 — 비경합 경로의 문구는 종전에도 이것이었다).

### 이제 보장되는 것
```
재발송 vs 서명            늦게 도착한 재발송은 400 전이 위반 — signed 문서와 증적
                         (signed_at·signer_ip)이 보존된다
환불 무효화 vs 서명        늦게 도착한 쪽이 진다: 서명이 먼저면 무효화 스윕이 signed를
                         스킵(보존 — CanVoidContract 재판정), 무효화가 먼저면 서명이 400
                         (voided 종단 전이 위반 + 환불 패스 가드 — 둘 다 트랜잭션 안)
환불 마감 + 계약 무효화    **한 트랜잭션**(UpdatePassWithLedgerAndContracts) — 중간 실패로
                         refunded 패스에 sent 계약이 잔존하는 상태가 더는 생기지 않는다
                         (v2.6 남은 갭의 계약 절반 종결. P04 후속)
패스당 유효 계약 1건       POST /v1/contracts의 중복 검사가 생성과 한 트랜잭션
                         (CreateContractGuarded) — 동시 2건 중 1건만 통과(P36 M2 봉인)
```

### 남은 갭
```
미납 회차 종결(waived_at)은 여전히 환불 트랜잭션 밖이다 — v2.6 남은 갭의 결제 절반.
계약과 달리 회차 인덱스 단위 재검증이 필요해 접합의 결이 복잡하고, waived_at은 멱등 표식이라
잔존해도 금액이 틀어지지 않는다. PayInstallment 원자화(같은 갭 목록)와 함께 닫는 후속으로 미룬다.

환불 진행 중 끼어든 수동 계약 생성(POST /v1/contracts)은 무효화 스윕이 못 본다 — 후보 선정이
트랜잭션 밖이라서다. 생성 가드(refunded 패스 400)와 send/sign의 트랜잭션 내 환불 패스 가드가
창을 좁히지만(그 계약은 발송도 서명도 못 한다) 원리적으로 닫히진 않았다. 수동 생성은 어드민
소비처가 0곳인 레거시 경로라 실위험 낮음(P36 L).
```

### 스토어 계약(공통 스위트에 고정 — 서브테스트 20종, 에뮬레이터 러너 검증 완료)
```
TransitionContract(centerID, contractID, mutate)   — 계약 + 그 패스를 같은 트랜잭션에서 읽고
                                                     mutate가 최신 문서 위에서 검증+변경.
                                                     mutate 제약은 PassMutator와 동일
                                                     (순수·Store 재호출 금지). 없는 계약 404
UpdatePassWithLedgerAndContracts(..., contractIDs, sweep)
                                                   — 환불 마감 전용. 계약 스캔은 밖(ID 사전
                                                     지목), 재판정은 안(점읽기 — 컬렉션 잠금
                                                     없음). sweep의 save=false는 스킵, 에러는
                                                     패스·원장까지 전부 롤백
CreateContractGuarded(centerID, contract, guard)    — 같은 회원 계약을 트랜잭션 내 질의 후
                                                     guard 판정, 통과 시에만 생성
UpdateContract                                      — 존치하되 **상태 전이 경로 사용 금지**
                                                     (문서 통째 교체 — 시딩·정정 전용)
```

## v2.16 관리 평면 — superadmin·센터 신원·센터 생성 (2026-08-29, P41, 이 섹션도 계약의 일부)

멀티센터 Phase A(PT데스크_설계_04). 데이터 평면(센터 스코프 격리)은 이미 전 경로에 깔려
있었고, 이 버전은 "센터를 만들고 최초 owner를 앉히는" 관리 평면을 신설한다.

### 새 롤 — superadmin
```
role: superadmin                            교차 센터 관리 평면 전용. 센터 소속 없음(UserIndex
                                            center_id=""), Staff 레코드 없음. IsStaff에 포함되지
                                            않아 기존 owner/staff 가드 전부가 무변경으로 403.
                                            인증 미들웨어가 /v1/admin/* 과 /v1/me 외 전 경로를
                                            403으로 차단(센터 스코프 API 진입 금지 — 개인정보
                                            최소접근 + CenterID="" store 호출 500 방지).
최초 시딩                                    Firestore 콘솔에서 users/{uid} = {role:"superadmin",
                                            center_id:""} 1회 수작업(이후 센터·owner 생성은 API).
dev 헤더                                     X-Dev-Role: superadmin 허용(로컬 개발).
```

### 새 엔티티 — Center(센터 신원)
```
Center { id, name, phone?, address?, status(active), created_at }
  id                                        소문자 슬러그 ^[a-z0-9][a-z0-9-]{1,29}$ — Firestore
                                            문서 키이자 storage.rules firestore.get 경로 세그먼트.
  저장                                       centers/{id} 문서의 `center` 맵(네스팅 — top-level
                                            Policy·`business` 맵과 동거, 상호 비덮어쓰기는
                                            스토어 계약 스위트로 고정).
```

### 새 endpoint (superadmin 전용)
```
POST /v1/admin/centers {id,name,phone?,address?,owner:{name,email}}
                                            → 201 {center, owner}. 순서: 정책 기본값 확보(지연
                                            시딩 재사용 — 센터 문서를 먼저 쓰면 지연 시딩이 영구
                                            비활성) → 센터 신원 → owner(계정+인덱스+레코드,
                                            CreateStaff 쓰기 순서 규약). owner.role은 서버가
                                            owner로 강제. 부분 실패는 같은 요청 재호출로 복구
                                            (멱등). 이름이 다른 기존 ID는 409. 임시 비밀번호
                                            비노출 — 초대 메일은 어드민 프론트가
                                            sendPasswordResetEmail로(CreateStaff와 동일).
GET  /v1/admin/centers                      → 200 [Center] — ⚠ v2.35 개정: **기본 센터 ∪ 신원 등록
                                            센터**. 기본 센터는 상호가 비어도 name:"" 그대로 맨 앞
                                            (v2.34까지는 신원 등록 문서만이라 운영 1호점이 빠졌다).
                                            그 외는 상호 등록 문서만, id 오름차순. v2.35 절 참조.
```

### 기존 계약 변경
```
GET /v1/center                              응답에 name 추가(하위호환 — 미지정 키 무시). 신원
                                            미등록 센터(기존 rise)는 "" — 클라이언트는 빈 값이면
                                            기존 하드코딩 상호로 폴백한다. 서버 먼저 배포.
PUT /v1/center                              응답에도 name 포함(정책 저장 응답으로 캐시를 갱신하는
                                            클라이언트에서 상호가 깜빡이지 않게).
POST /v1/staff                              교차 센터 가드 추가: 초대 이메일의 계정이 **다른
                                            센터**에 연결돼 있으면 409("이미 다른 센터에 연결된
                                            계정이에요") — UserIndex는 uid당 1건이라 종전엔
                                            그 사람의 원래 센터 접근이 조용히 덮였다.
storage.rules                               회원 문서 조회 경로의 센터 세그먼트를 "rise" 하드코딩
                                            → 요청자 UserIndex.center_id로 일반화(문서 수 2개
                                            상한 유지, center_id 없으면 fail-closed).
                                            ⚠ 배포 후 실 토큰 업로드 1회 실측 필수(TestRuleset은
                                            firestore.get을 모킹해 이 계층을 못 잡는다).
```

### 남은 갭 (Phase B~D, 설계04)
```
어드민 superadmin UI(센터 목록·생성 마법사) / 센터명 동적 표시(어드민 3곳·앱 AppConfig 폴백
연결) / 가입 요청의 센터 차원(초대 코드/QR — 설계04 §4) / UserIndex memberships[](한 사람
다센터) / 스태프 사진 서버 업로드.
```

---

## v2.17 탈퇴는 미서명 계약을 종결한다 — 서명 주체가 사라지면 "서명 대기"는 거짓이 된다 (2026-08-29, P40, 이 섹션도 계약의 일부)

v2.11의 탈퇴는 계약을 **문자 그대로 무접촉 보존**했다: draft/sent도 상태 그대로 남았다.
P37·P38 적대 리뷰(2026-08-29)가 이것이 거짓 상태임을 확정했다([H]) — DELETE /v1/me가
Firebase 계정(서명 주체)을 파기하므로 그 계약은 **영원히 서명될 수 없는데**, 어드민 미서명
카운트와 계약 여정 CTA는 그것을 "행동 가능한 할 일"로 계속 세었다. 어드민에서 문구만 갈라
내는 증상 수리를 기각하고 원인을 수리한다: **탈퇴가 미서명 계약을 voided로 종결한다.**

### 무엇이 바뀌나 (라우트·응답 표면 무변경)

DELETE /v1/me의 실행 순서(v2.11 절, 위에서 개정)에 ④가 들어간다:

```
④ 미서명(draft/sent) 계약 voided 종결 — 계약별 TransitionContract(CAS, v2.15 동사)

  응답 스키마 그대로: void는 삭제가 아니라 retained.contracts 수가 변하지 않는다.
  무효화 건수는 서버 감사 로그(voided_contracts)로만 관측된다.
```

### 규칙

```
근거           서명 주체가 ②에서 파기됐다 — "서명 대기"는 사실이 아니다. 환불이 미서명
               계약을 void하는 것(v1.5)과 같은 논리의 다른 트리거.
signed 불가침   CanVoidContract(draft/sent만 허용)가 **트랜잭션 안에서 재판정**된다(v2.15
               TransitionContract). 성립했던 거래의 법적 기록은 상태·증적(signed_at·
               signer_ip) 그대로. 스윕과 경합한 막판 서명도 보존이 최종 판정(스킵)이고,
               반대로 void가 먼저 커밋되면 그 서명은 400(voided 종단 전이 위반).
재시도 멱등     각 void는 독립 CAS. 부분 실패 → 전체 500 → 같은 토큰 재시도(P22 순서 규약,
               ⑥ UserIndex가 마지막이라 가능) → 이미 voided는 스킵. 몇 번을 돌아도 같다.
보존 비저촉     문서는 남는다 — §21① 단서·전자상거래법 시행령 §6①은 기록 보존 의무지 상태
               동결 의무가 아니다. 발송 증적(sent_at·first_sent_at)도 유지된다.
자리           ②(계정 파기)보다 뒤 — 외부 파기가 실패해 탈퇴가 좌초되면 살아 있는 회원의
               계약이 이유 없이 voided로 남는다. ⑤(가명화)보다 앞 — 실패가 가명화 전에서
               멈춰 미완료가 눈에 보인다.
```

### 후속 차단 목록에 한 줄 추가 (v2.11의 누락 자리)

```
POST /v1/contracts    "탈퇴한 회원이에요 — 계약을 만들 수 없어요" (400)
                      탈퇴 void가 "패스당 유효(비voided) 계약 1건" 가드(v2.15)의 분모를
                      비우는 순간, 이 경로가 같은 패스에 새 draft를 재생산할 수 있었다 —
                      서명 주체가 없어 영원히 미서명인 계약을 방금 닫은 자리에서 다시 만드는
                      유일한 경로였다. send/sign은 추가 가드 불요: 탈퇴 회원의 잔여 계약은
                      전부 종단 상태(signed/voided)라 전이 규칙이 이미 막는다.
```

### 따라오는 사실 (의도된 결과)

```
탈퇴 후 그 패스를 환불하면 위약금율은 정책 폴백을 탄다 — 유효(비voided) 계약이 없어
refundBasis(v1.5)가 스냅샷을 찾지 못한다. 결함이 아니다: 미서명 계약의 요율은 회원이
동의한 적 없는 숫자라 스냅샷 자격이 애초에 없었다(signed는 불가침으로 남아 스냅샷도 산다).
```

### 하드닝 동봉 (P37 리뷰 권고 채택 2건 — 행동 무변경)

```
스윕 중복 지목 dedup      UpdatePassWithLedgerAndContracts의 contractIDs에 같은 ID가 두 번
                         와도 Firestore가 같은 문서를 한 트랜잭션에서 두 번 쓰지 않는다.
                         공통 스위트에 중복 지목 케이스 고정(Memory·에뮬레이터 러너 통과).
ContractMutator 규약      포인터 필드는 재할당만(c.SentAt = &t) — 경유 쓰기(*c.SentAt = t)는
                         Memory의 얕은 사본 롤백을 오염시킨다. 인터페이스 주석에 명문화.
```

### 남은 갭

```
void 후보 선정(계약 목록)은 스윕 트랜잭션 밖이다(컬렉션 잠금 회피 — v2.15 환불 스윕과 같은
구조). 목록 조회와 void 사이에 생성된 계약은 이번 탈퇴가 못 본다 — 창은 밀리초 단위고
(후보를 외부 호출 ①② 뒤에서 다시 읽는다), POST /v1/contracts의 탈퇴 가드가 탈퇴 **확정
이후**의 재생산은 막지만, 이 창 자체는 원리적으로 닫히지 않았다(v2.15 남은 갭과 동형).
잔존해도 어드민 관측에서 발견되는 상태이지 돈이 움직이는 상태는 아니다.
```

## v2.18 계약서 문서 스냅샷 — send가 확정하고, 재발송이 재확정하고, 서명이 봉인한다 (2026-08-29, P39, 이 섹션도 계약의 일부)

계약서doc §D (다)안(버전 고정 템플릿 + 변수 스냅샷 + 해시)의 서버 축이다. 렌더는
클라이언트가 하고(템플릿은 앱 자산 번들 — 서버는 템플릿 원문을 들지 않는다), 서버는
**무엇이 채워졌는가**(vars)와 **그것이 서명 당시와 같은가**(sha256)에만 답한다.
**발행 래치는 꺼진 채 배포된다** — 켜기 전까지 이 섹션의 어떤 필드도 실제로 생기지 않고,
모든 경로가 v2.17까지의 동작과 바이트 동일하다(명시 테스트로 고정).

### Contract 스키마 추가 (additive)

```
template_version  string             이 계약에 확정된 계약서 템플릿 버전(예: "pt-v1").
                                     빈 값 = 스탬프 전(래치 OFF 동안의 계약·레거시 전부)
vars              map[string→string] send 시점에 확정된 슬롯 → 값 스냅샷(§C). 이후 원본
                                     (Pass.ValidUntil·Policy·Business)이 바뀌어도 불변 —
                                     PenaltyRate 스냅샷과 같은 이유(P14), 같은 자리
```

두 필드 모두 omitempty 없음(P37 리뷰 규약 — toDoc 통문서 Set의 무손실 왕복). **클라이언트
호환**: 순수 additive라 앱·어드민은 모르는 필드를 무시하면 되고(현행 파서 전부 그렇다),
빈 값 분기는 §D ⑥의 레거시 분기와 동일하다 — vars 없는 계약은 지금 문구(요약 고지)를 유지.

### 발행 래치 (registry)

서버 템플릿 레지스트리(내부 정책, 와이어 아님): 버전 → {요구 슬롯 22종, issuable}.
`pt-v1`은 **issuable=false**로 등록 — 래치가 꺼진 동안 발급/send는 스탬프를 **아예 하지
않는다**(P39 결정 1). 미완성 값이 인쇄된 계약서(방판법 §30 기재 누락)도, 발급 차단(계약
자동 생성이 회원권 발급을 겸하므로 게이트가 발급을 막는 부작용)도 아닌 제3의 길이다.
켜는 조건은 람 결정 2건(체육시설업 신고·사업자 등록) + 계약서doc §F 체크리스트.

요구 슬롯 22종 = §C 29종 − {{계약 체결일}}(아래) − 신규 사업자 3종(Business 필드 미결,
P39 결정 6) − 부가상품 3종(조문 미결). 사업자 6칸은 실시간 조회가 아니라 **vars에 얼린다**
(D-4 재현성 — legal 문서처럼 실시간이면 서명 당시 문서가 재현 안 됨).

`{{계약 체결일}}`은 vars **밖**이다(P39 결정 3): send 시점엔 signed_at이 없고, 서명 직전
보강은 해시 입력 순서 의존을 만든다. 클라이언트가 엔티티 필드(signed_at, 미서명이면
first_sent_at)에서 렌더한다 — sha256과 같은 트랜잭션에서 기록되는 불변 증적이라 재현성이
성립한다.

### 스탬프 시점 — send=확정 · 재발송=재확정 · sign=봉인

```
발급(CreatePass)   자동 생성 계약(sent)도 스탬프를 시도한다. 단 확정 플로우상 결제 기록은
                   발급 **뒤**라(발급 → Payment 기록) 결제 2키(결제방법·납부일정)가 비어
                   통상 스킵된다 — **첫 완전 스탬프는 결제 기록 후 운영자의 재발송에서
                   찍히는 것이 정상 경로다**(시점 현실, 결함 아님).
send               조립은 트랜잭션 밖(ContractMutator 순수성), 반영은 mutate 안 재할당.
                   **재발송도 매번 재확정한다**(P39 결정 2) — 회원이 서명 화면에서 보는
                   것은 저장된 vars 렌더이므로 재확정이어야 "본 것 = 서명한 것"(D-4).
                   배포 전 sent 잔존 계약도 재발송으로 vars를 얻는다.
sign               vars가 있으면 서명 트랜잭션 **안에서** sha256으로 봉인. 없으면 봉인 없음.
POST /v1/contracts 수동 draft 생성은 스탬프하지 않는다 — vars는 send 의미론이다(§D ⑤).
```

스킵 조건(전부-아니면-전무 — 요구 슬롯 하나라도 조립 불가면 스탬프 전체를 건너뛴다):
결제 기록 없음(발급 직후) · 사업자 6칸 미완(래치 ON 후에도 조용한 열화가 아니라 문서화된
완성 조건) · 위약금율 스냅샷 없음(v1.5 이전 레거시 — 0%가 아니라 "모름") · 담당 코치/회원
문서 결측 등. **스킵돼도 send 자체는 오늘 경로로 성립한다**(스탬프는 부가물, 발송이 본체).

**보존 규약**: 스탬프가 성립하지 않는 재발송(래치 OFF·조립 불완전)은 기존
template_version/vars를 **건드리지 않는다**. 이미 완전한 문서를 받아 본 회원의 열람물을,
나중에 조립 불가능해진 재발송이 파괴하면 안 된다 — 마지막 완전 스탬프가 살아남고, 그때
회원이 보는 문서와 서명이 봉인하는 문서는 그 마지막 스탬프다.

**{{위약금율}}만은 재확정에서도 움직이지 않는다** — 출처가 Policy가 아니라
Contract.penalty_rate(생성 시점 스냅샷)이므로, 정책 요율 변경은 재발송을 타고 소급되지
않는다(§C 비고 · P14 교훈). 나머지 C-2 정책 5종은 send 시점 값으로 재확정된다.

### 값 직렬화 (해시 입력 — **여기 명세로 동결**, 사후 변경 불가)

```
납부일정      "n회차 {금액}원 ({YYYY-MM-DD} 납부예정|납부완료)" 행을 "\n" 결합 (P39 결정 4).
              회차 번호는 결제 문서 순 × 저장된 회차 순의 전체 통산. 분할 회차가 하나도
              없으면 "일시불". waived 회차가 있으면 결측(동결 포맷이 표현 못 함 — 실무
              도달 불가: 환불 패스의 send는 트랜잭션 안 가드가 막는다). 골든 테스트로 고정.
금액          콤마 3자리 구분, 단위 없음("1,000,000" — 템플릿이 "{{계약금액}}원"으로 단위를
              든다). 어드민 ko-KR KRW 표기와 같은 그룹핑.
위약금율      percent, 소수 첫째 자리 반올림, 정수면 소수점 없이("10", "7.5") — 앱 계약
              시트 표기 정밀도와 동일(0.1×100의 부동소수점 잔여가 인쇄되지 않게).
결제방법      카드/현금/계좌이체(앱·어드민 라벨과 동일). 복수 수단은 canonical 순서
              (card→cash→transfer) "·" 결합("카드·현금") — 분할 수납은 정상 영업(v2.4).
노쇼 유예     "적용"/"미적용".  홀딩 상한 -1은 "무제한".  그 외 숫자는 단위 없는 십진수.
```

### 봉인 공식

```
sha256 = hex( SHA-256( template_version + "\n" + canonical_json(vars) ) )      — §D ②

canonical_json  키 정렬(유니코드 코드포인트 순 = UTF-8 바이트 순) + 공백 없음 + 최소
                이스케이프(" \ 제어문자만 — \b \f \n \r \t 축약형, 그 외 \u00xx 소문자
                hex. 비ASCII는 원문 그대로). JS JSON.stringify와 동일 규칙 — 어드민이
                표준 직렬화기로 재검증할 수 있어야 한다(Go json의 HTML 이스케이프 불채용).
```

서명 트랜잭션 안에서 계산·저장한다(그래야 "서명된 순간의 내용"). 골든 벡터(구현과
독립적으로 python으로 재도출)로 고정. 이 해시는 사후 변조를 **검출**한다(재계산 대조) —
변조를 막지는 못한다(§D ②, append-only 원장의 영역).

**sha256 비어 있음 ⟺ 본문 렌더 없이(요약 고지로) 진행된 서명** — 래치 OFF 동안의 모든
서명과 레거시가 여기 해당하고, 거짓 신호는 없다(P28이 적법화한 현행). pdf_path는 §D (나)
연동 전까지 계속 비워 둔다.

### 검증

```
전 스위트          go build/vet/test 전부 green + -race 클린. latch-off 불변은 P37 계약
                  스위트 상시 통과 + 명시 단언 테스트(스탬프 재료 완비 상태에서도 발급·
                  재발송·서명에 세 필드가 생기지 않음).
래치 ON 경로       테스트 전용 픽스처 버전으로만: 발급 스킵(결측 = 정확히 {결제방법,
                  납부일정}) → 결제 후 재발송 22키 전체 스탬프 → 정책 변경 재발송 재확정
                  (위약금율 불변 대조) → 불완전 재발송 보존 → 서명 봉인(재계산 일치) →
                  vars 없는 서명 무봉인.
뮤테이션 6/6       래치 반전 · 전부-아니면-전무 제거 · 보존 제거 · 무조건 봉인 · canonical
                  정렬 제거 · 재확정→1회만 — 각각 테스트로 사멸(생존 0. 보존·재확정은
                  단일 킬러 테스트가 유일 방어선임을 함께 실증).
에뮬레이터         컨포먼스 통과(Center 신원 서브테스트 1건 실패는 v2.16/P41 소관 —
                  이 변경과 무관, 별도 세션 진행 중).
```

## v2.20 재등록/상담 요청 — 앱 데드엔드를 데스크로 잇는 손잡이 (2026-08-29, P42-consult-request, 이 섹션도 계약의 일부)

> 번호 정정(2026-08-29, 세션 경합): 이 섹션은 원래 v2.17로 기재됐으나 :1833의 v2.17(P40 탈퇴
> 종결)과 **중복 클레임**이었다 — 동시 작업 세션이 서로 모르고 같은 번호를 잡은 것. 내용 무변경,
> 번호만 다음 빈 번호(v2.20)로 옮겼다. 본문·코드 주석에서 이 기능을 v2.17로 인용한 곳이 있다면
> v2.20으로 읽을 것. 파일 내 위치가 v2.19보다 앞인 것은 append 시점 차이(무해).

앱의 재등록 관련 안내가 전부 "센터에 문의해주세요"로 끝나는 데드엔드였다(홈 빈 상태·잔여 0
배지·예약 재등록 안내 — home_screen 주석이 "회원이 앱에서 갈 경로가 없는 약속"이라 자각).
가입 요청(join)과 같은 "회원발 요청 큐" 패턴으로 의사 전달 경로만 연다 — **결제·상품·가격은
없다**: 처리의 실체는 어드민의 기존 수기 플로우(회원권 발급+결제 기록)이고 이 큐는 그 앞의
손잡이다.

### 새 엔티티 — ConsultRequest (센터 스코프 컬렉션 consult_requests/{id})
```
ConsultRequest { id, member_id, kind(renewal|consult), note?, status(pending|done), created_at }
  note                                       ≤200자(서버 검증). 상담 내용이 아니라 힌트 —
                                             긴 사연은 데스크 상담의 몫.
  목록 정렬                                   created_at 오름차순 → id(동률 안정) — 데스크 큐는
                                             오래 기다린 요청이 위.
```

### 새 endpoint
```
POST /v1/consult-requests {kind, note?}      회원 본인 전용(매칭 전 member_id 없는 계정 403).
                                             → 201 ConsultRequest. **pending 중복은 409**
                                             ("이미 보낸 요청이 있어요 — …") — 연타·불안
                                             재전송으로 큐가 같은 사람으로 쌓이지 않게.
                                             done 이후 재요청은 정상(재등록은 반복되는 일).
GET  /v1/consult-requests                    역할 스코프: member=자기 것만(앱이 "요청 보냈어요"
                                             상태를 복원하는 출처, member_name 없음) /
                                             owner=센터 전체+member_name(응답에서 해석 —
                                             저장하지 않아 개명·정정이 즉시 반영. 회원 문서가
                                             사라진 요청은 이름 없이 owner에게만) /
                                             trainer=담당 회원 것만(P37 스코프 경계).
POST /v1/consult-requests/{id}/done          스태프 전용(trainer는 담당 회원 건만). 상담 종료
                                             표식 — 발급·결제와 묶지 않는다("상담했지만 미등록"
                                             도 정상 결말). **done→done은 멱등**(200 — 두
                                             스태프가 나눠 처리하는 데스크 동선. JoinApprove가
                                             409인 것과 다른 이유: 그쪽은 재실행이 회원 레코드를
                                             하나 더 만들지만 여기는 상태 표식 하나다).
```

### 클라이언트 규약
```
앱 CTA                                       홈 빈 상태(만료·환불)·회원권 경고 배지 줄 두 곳.
                                             pending이면 버튼 대신 "요청 보냈어요" 상태 문구
                                             (눌러서 409 받는 흐름을 만들지 않는다 — 사전 판정
                                             원칙). 목록 조회 실패/로딩은 fail-open(버튼 유지 —
                                             중복 최종선은 서버 409).
어드민                                       대시보드 "해야 할 일"에 pending 목록(가입 요청 다음
                                             — 의사가 확인된 사람이라 "잔여 부족 후보"보다 우선).
                                             회원 이름 링크 → 회원 상세(기존 발급·결제 플로우로
                                             마감) + [완료].
```

## v2.19 계약서 템플릿 2종 — 시설 신고 상태가 버전을 고른다 (2026-08-29, P42, 이 섹션도 계약의 일부)

계약서doc :818의 갈래("신고 대상이 아니라는 유권해석을 받았다면 이 행을 뺀다")를 P39 버전
아키텍처 위에 구현한다. 선택지는 서식 취향이 아니라 **신고 상태의 선언**이다: 대표가 어드민에서
3단 상태를 선언하면, 스탬프 시점의 템플릿 버전이 그 선언의 함수가 된다. 발행 래치는 여전히
꺼져 있다(v2.18) — 이 섹션의 어떤 스탬프도 래치 전에는 실제로 생기지 않고, 선언·저장·응답만
오늘부터 동작한다.

### 센터 문서 확장 — `facility` 절 (additive)

```
centers/{id}.facility {                      Business 밖의 별도 절 — Business에 칸을 늘리면
  report_status  "unknown"|"reported"|"exempt"  IsComplete(12칸) 판정에 끼어들어 법정 문서
  report_no      string                         4장이 초안 배너로 회귀한다(P39 결정 6 회피).
  insurance      string                         저장은 facility 절만 머지 쓰기 — Policy·
}                                               Business 불침범(P27 SavePolicy 교훈, 회귀
                                                테스트 고정).
report_status                                unknown = 아직 선언 안 함(기본값 — 절이 없던
                                             문서도 이 값으로 읽힌다) / reported = 체육시설업
                                             신고 완료(신고번호 보유) / exempt = 신고 대상
                                             아님을 확인함(지자체 유권해석·기구 미비치 강습
                                             전용 — 면적 하한이 없어 "소규모 면제"는 성립하지
                                             않는다, 계약서doc :812).
```

### GET /v1/center 응답 확장 (additive)

```
facility {report_status, report_no, insurance}   전 역할 공개(Business와 같은 이유 — 계약서에
                                                 그대로 인쇄되는 값이라 민감 정보가 아니다).
                                                 미선언이면 {"unknown","",""}.
GET /v1/public/business                          **불변** — 키 집합이 전용 타입으로 고정돼
                                                 있고(v2.13), facility는 실리지 않는다.
GET /v1/public/center                            (v2.29) {name, phone, address} 3칸 고정 — 여기도
                                                 facility·policy는 실리지 않는다.
```

### 새 endpoint

```
PUT /v1/center/facility                      owner 전용(member/trainer 403). 바디는 고정
  {report_status, report_no, insurance}      3필드(절 통 교체 — 폼이 늘 전부 제출, 비워서
                                             지우기 가능). PUT /v1/center의 {policy?,business?}
                                             덩어리에 얹지 않은 이유: 상태와 신고번호가 한
                                             검증으로 묶여 부분 제출 개념이 없다.
검증(400, 친절 한국어)                        report_status ∉ 3값 → 400. reported인데
                                             report_no 빈 값 → 400("신고 완료로 선택하면
                                             체육시설업 신고번호를 입력해야 해요") — 번호 없는
                                             "신고했음"은 검증 불가능한 주장이라 저장 게이트에서
                                             막는다. insurance는 자유 서술(선택, ≤200자).
응답                                         **저장된 facility 그 자체**(정규화 반영 3필드 —
                                             GET /v1/center 전체가 아니다). 어드민은 이
                                             응답으로 폼만 재장전하고 센터 캐시는 쿼리
                                             무효화(GET 재조회)로 맞춘다.
```

### 템플릿 레지스트리 — pt-v1 폐기, 2변형 등록 (내부 정책, 와이어 아님)

```
pt-v1-reported   요구 슬롯 25종 = 공유 22종(v2.18) + 약관 게시 주소 + 보증보험 종류·보장내용
                 + 체육시설업 신고번호. issuable=false(발행 스위치는 여전히 §F 체크리스트 뒤).
pt-v1-exempt     요구 슬롯 24종 = 위에서 신고번호 제외 — 결측 허용이 아니라 **요구의 부재**다
                 (전부-아니면-전무의 분모에서 빠져, 미신고 센터도 완전 스탬프가 성립한다).
pt-v1(v2.18)     **폐기(레지스트리에서 삭제)**. 지난 버전 보존 규칙(§D ①)의 예외인 근거:
                 래치가 한 번도 켜진 적 없어 이 버전으로 스탬프·봉인된 계약이 0건 — 보존이
                 지키려는 대상(스탬프된 문서의 재현·검증)이 존재하지 않는다. 저장된 계약의
                 버전 문자열 렌더 가능 여부는 앱의 버전 표가 답한다(레지스트리는 발행 정책).
```

### 스탬프 버전 선택 — 래치와 합성되는 두 번째 게이트

```
게이트 순서       ① 발행 래치(스토어 읽기 없음 — OFF면 facility 읽기조차 없이 오늘 경로
                 그대로: latch-off 불변은 스토어 접근 횟수까지 포함하며 카운트 테스트로 고정)
                 → ② facility.report_status 읽기 → ③ 상태별 버전 선택.
reported         → pt-v1-reported로 스탬프 시도(이후는 v2.18 규칙 그대로 — 전부-아니면-전무).
exempt           → pt-v1-exempt로 스탬프 시도.
unknown(기본)     → **스탬프 스킵**. 래치 OFF·요구 키 결측에 이은 세 번째 스킵 갈래로,
                 철학은 같다: 모르는 상태로 문서를 만들지 않는다. 발송 자체는 성립한다
                 (오늘 경로 그대로 — 요약 고지 서명). 선언은 언제든 가능하고, 선언 후
                 재발송이 재확정한다(P39 결정 2).
적용 지점         발급 자동 생성(buildContractForPass)과 send 재확정 — 두 경로가 같은 게이트를
                 쓴다. 이미 스탬프된 계약의 보존 규약(불완전 재발송이 마지막 완전 스탬프를
                 지키는 것, v2.18)은 그대로다.
```

### 신규 슬롯 3종의 값 규칙

```
{{약관 게시 주소}}            서버 상수 https://rize-218c1.web.app/legal/terms.html — 제23조②
                             (계약서의 교부와 약관)의 게시 위치. P27 §F가 배포한 법정 문서
                             URL이자 앱 legal_links와 동일 원천. 센터 입력이 아니다(게시
                             주체가 시스템이라 센터마다 다를 수 있는 값이 아니다). Vars에
                             얼리는 이유는 사업자 6칸과 같다(D-4 — 서명 당시 안내 주소 보존).
{{보증보험 종류·보장내용}}     facility.insurance. **빈 값 → "가입하지 않았습니다"** — 제20조③
                             이 스스로 설계한 결측 표기라("가입하지 않은 경우 …로 기재")
                             유일하게 빈 값이 스탬프를 막지 않는 슬롯이다. 미가입은 숨길
                             결측이 아니라 고지 대상.
{{체육시설업 신고번호}}        facility.report_no — reported 변형 전용(exempt 목록에 키 자체가
                             없다). 손편집 방어로 빈 값은 결측(스탬프 스킵)이다.
{{부가상품 목록}} 외 3종       슬롯 소멸 — 시스템이 부가상품을 팔 수 없으므로(Pass 모델에 부재)
                             조문을 통째로 대체(:1275 "빈 표 금지", P28 "코드가 하는 것만
                             약속"). 부가상품 도입 시 새 템플릿 버전으로 온다.
```

### 배포 순서

서버 먼저(이 계약), 어드민(설정 → 시설 신고 카드)·앱(변형 템플릿 자산 2종 + 버전 표) 나중.
facility 미선언 센터는 모든 것이 오늘과 동일하므로(unknown 기본값 + 래치 OFF 이중 안전)
중간 상태에 사용자 가시 변화가 없다.

## v2.21 자필 서명 캡처 — 서명란에 실제 서명이 들어간다 (2026-08-29, P44, 이 섹션도 계약의 일부)

P44 리서치 확정에 따라 sign에 자필 서명 이미지를 **옵션**으로 싣는다. 법적 요건이 아니라
관행·체감·증거 보강이다(전자서명법 §2는 기술중립 — 효력의 뿌리는 여전히 휴대폰 인증 계정 +
동의 행위이고, 자필 패드는 인앱·현장 계약의 사실상 표준이라 채택). 이미지로만 보관하고
특징점 추출은 하지 않는다(생체인식 민감정보 비해당 구조 — PIPC 2024.12 안내서 기준 체계,
명문 아님을 병기).

### POST /v1/contracts/{id}/sign — 옵션 바디 (additive)

```
요청 바디(옵션)                              {"signature_png": "<base64>"} — 서명 패드 PNG
                                             원본 바이트의 base64(표준 인코딩·패딩 포함,
                                             data URI 프리픽스 없음). 바디 없음·빈 JSON({})·
                                             빈 문자열은 전부 **바디 없는 구버전 요청과 동일**
                                             하게 유효하다 — 클릭(체크 동의) 서명으로 성립.
빈 값 신호 정의                              signature_png 빈 값 ⟺ 체크 동의만으로 성립한
                                             서명(구버전 앱·레거시). sha256 빈 값(⟺ 본문
                                             렌더 없는 요약 고지 서명)과 동형의 정직한 신호 —
                                             거짓 신호를 만들지 않는다(P44 결정 6).
검증(400, 친절 한국어)                       ① base64 불가 → "서명 이미지 인코딩(base64)이
                                             올바르지 않아요" ② PNG 매직 불일치(JPEG 등) →
                                             "서명 이미지는 PNG 형식이어야 해요" ③ 디코드
                                             원본 64KB 초과 → "서명 이미지가 너무 커요(최대
                                             64KB)" ④ 매직은 맞는데 헤더 손상 → "서명
                                             이미지를 해석할 수 없어요" ⑤ 치수 밖(가로
                                             50~2000px·세로 20~2000px) → "서명 이미지 크기가
                                             올바르지 않아요(…)". 검증은 전이 트랜잭션 **전**
                                             — 거부된 요청은 계약을 1바이트도 건드리지 않는다.
                                             크기 상한 근거: 패드 실측 5~18KB의 3배+ 여유.
                                             치수 하한은 캔버스 위생 거부다 — "빈 서명 방지"
                                             (최소 획·바운딩 박스)는 앱 몫(P44 결정 5).
응답                                         형태 불변(계약 JSON 그대로) — 새 2필드가 자연
                                             포함될 뿐이다. 구버전 앱은 미지 필드를 무시한다.
```

### Contract 문서 확장 — 두 필드, 두 해시 (additive)

```
contracts/{id} +=                            signature_png    string  (omitempty 금지)
                                             signature_sha256 string  (omitempty 금지)
signature_png                                서버가 수신 바이트를 **재인코딩한 정규 base64**만
                                             저장한다(클라이언트 문자열 재사용 아님 — 패딩·
                                             공백 변형이 저장값·해시를 흔들 수 없다). 서명
                                             트랜잭션에서 signed_at·signer_ip와 함께 기록.
signature_sha256                             서명 이미지 **원본 PNG 바이트**의 SHA-256 소문자
                                             hex. 내용 봉인 sha256과는 역할이 분리된 별개
                                             해시다(Dropbox Sign 2해시 모델과 동형): sha256은
                                             send 확정물(template_version+vars)을 봉인하고
                                             서명 유무와 무관하게 **불변**, signature_sha256은
                                             서명 이미지의 사후 변조 검출만 맡는다. 서명
                                             이미지는 contractSeal 입력에 절대 들어가지 않는다
                                             (직렬화 명세 동결 + send 시점에 존재하지 않는 값,
                                             P44 결정 3 — 쌍 골든 테스트로 고정).
법적 지위(정직 고지)                         두 해시 모두 **법정 추정력 주장이 아니다** —
                                             현행법상 추정은 공인전자문서센터(전자문서법
                                             §31조의7)만이고, 자체 해시는 입증 수단이다(P44
                                             리서치 확정). 체결 정보 표시는 이 구분을 그대로
                                             말한다 — "봉인된 것처럼 보이는 비봉인 요소"를
                                             만들지 않는다.
저장 위치 근거                               Storage 파일이 아니라 계약 문서 안이다(P44 결정
                                             2): 실측 5~18KB는 문서 한도(1MiB)의 1~4%이고,
                                             5년 보존·탈퇴 비파기(P22 계약 비접촉)·환불 후
                                             보존(v1.5 signed 불가침)을 저장 위치만으로 자동
                                             상속한다 — 규칙·수명주기·오프라인 열람의 3중
                                             비용이 사라진다.
```

### Firestore 인덱스 — 예외(exemption) 불요 판정 (2026-08-29 문서 검증)

```
판정                                         signature_png에 단일 필드 인덱스 예외를 **만들지
                                             않는다**. firestore.indexes.json·firebase.json
                                             변경 없음.
근거(1차 출처, 2026-08-29 확인)              Firestore quotas: "Maximum size of an indexed
                                             field value: 1500 bytes — Field values over
                                             1500 bytes are truncated. Queries involving
                                             truncated field values may return inconsistent
                                             results." — 대형 값은 쓰기 실패가 아니라 인덱스
                                             엔트리만 잘린다. (firebase.google.com/docs/
                                             firestore/quotas · docs.cloud.google.com/
                                             firestore/native/docs/quotas 동일 문구 교차 확인)
                                             signature_png는 어떤 쿼리에도 쓰이지 않으므로
                                             (계약 조회는 member_id·status 등호 필터뿐)
                                             잘린 인덱스는 무해하다.
권고 사항(후속, 비긴급)                      best practices는 쿼리에 안 쓰는 대형 문자열
                                             필드의 예외를 **저장 비용 절감** 목적으로 권고
                                             한다(정합성 요건 아님). 도입하려면 콘솔에서
                                             기존 복합 인덱스를 먼저 덤프해 indexes.json에
                                             포함해야 한다 — 인덱스 파일 배포는 파일에 없는
                                             인덱스·예외를 **삭제**하므로 빈 파일 선배포가
                                             더 위험하다. 지금은 안 만든다.
```

### 배포 순서

서버 먼저(이 계약) — 구버전 앱의 바디 없는 sign이 그대로 유효하므로 중간 상태 무해. 앱(서명
패드 시트 2단, P44 결정 5)·문서 표시(서명란 직하단 도킹 블록, P44 결정 4)는 뒤따른다.

## v2.22 발행 래치 ON — 계약서 발행 스위치를 올린다 (2026-08-30, P48, 이 섹션도 계약의 일부)

대표(센터 대표) 명시 결정으로 템플릿 레지스트리의 두 변형(`pt-v1-reported`·`pt-v1-exempt`)을
**issuable=true**로 올린다. v2.18이 세워 두고 v2.19가 변형 2종으로 확장한 문서 스냅샷 기계를
실제로 가동시키는 한 줄이다.

**v2.18 정정 — "발행 래치는 꺼진 채 배포된다"는 이 섹션으로 대체된다.** v2.18 본문의 그 문장과
"pt-v1은 issuable=false로 등록", v2.19의 "발행 래치는 여전히 꺼져 있다"·"issuable=false(발행
스위치는 여전히 §F 체크리스트 뒤)"는 **2026-08-30부로 효력이 없다**. 두 섹션의 나머지(스탬프
시점·전부-아니면-전무·버전 선택·봉인 규칙)는 전부 그대로 유효하다 — 바뀐 것은 래치 한 칸이다.

### 무엇이 바뀌었나 (내부 정책, 와이어 불변)

```
와이어                                       **변화 없음**. 요청·응답 스키마, 상태 전이, 에러
                                             문구 어느 것도 바뀌지 않는다. 이 섹션은 이미
                                             계약에 있는 필드(template_version·vars·sha256)가
                                             언제 실제로 채워지기 시작하는가만 바꾼다.
pt-v1-reported / pt-v1-exempt                issuable: false → **true**.
게이트 개수                                   3 → **2**(래치가 상시 통과로 바뀌었을 뿐, 나머지
                                             둘은 그대로다 — 아래).
스토어 접근                                   래치가 열렸으므로 발급(CreatePass)·발송
                                             (SendContract)이 이제 매번 `facility`를 **1회 더
                                             읽는다**(센터 문서 1건). v2.19의 latch-off 불변
                                             ("꺼져 있으면 facility 읽기조차 없다")은 이제
                                             롤백 구성의 보장이고, 그 구성에서는 여전히
                                             성립한다(테스트가 픽스처로 증명).
```

### 지금 이 순간의 관측 가능한 변화는 0이다 (그러나 안전 장치가 아니라 잠금 해제다)

래치는 세 게이트 중 첫 번째일 뿐이고, 프로덕션에서 실제로 문서 발행을 막고 있는 것은 나머지
둘이다. 2026-08-30 기준 프로덕션 Firestore의 상태:

```
② facility 신고 상태 선언                    센터가 아직 **미선언** → 읽기 기본값
                                             `report_status="unknown"` → 스탬프 스킵
                                             (모르는 상태로 문서를 만들지 않는다, v2.19).
                                             ← 지금 발행을 막고 있는 것은 이 게이트다.
③ 전부-아니면-전무 조립                       Business(사업자 6칸)가 **미등록** → 요구 슬롯
                                             24/25종 중 6종이 조립 불가 → ②를 통과해도 여기서
                                             스킵(v2.18).
결론                                         래치를 올린 것만으로는 어떤 계약에도 스탬프가
                                             찍히지 않는다. **다만 이것은 "안전해서 아무 일도
                                             없다"가 아니라 "남은 잠금이 데이터 입력 2건뿐"
                                             이라는 뜻이다** — 코드·배포·승인은 더 이상 사이에
                                             없다.
```

### 발행이 실제로 시작되는 조건 (대표가 할 일)

```
1. 사업자 정보 등록                           어드민 설정 → 사업자 정보의 계약 6칸(사업자명·
                                             대표자명·사업자등록번호·사업장 주소·대표 전화·
                                             대표 이메일). IsComplete(12칸)가 아니라 **이 6칸**이
                                             조립 조건이다(v2.18 C-3).
2. 시설 신고 상태 선언                        어드민 설정 → 시설 신고(PUT /v1/center/facility,
                                             v2.19). `reported`면 신고번호 필수 → 25종 변형,
                                             `exempt`면 24종 변형. `unknown`으로 두는 한
                                             발행은 시작되지 않는다.
그 순간부터                                   **다음 발급부터** 자동 생성 계약이 스탬프를 시도
                                             하고(결제 기록 전이라 통상 스킵 — v2.18의 정상
                                             경로), **다음 발송/재발송부터** 완전 스탬프가
                                             찍힌다. 이미 sent인 잔존 계약은 재발송해야 vars를
                                             얻는다(P39 결정 2 — 재발송 = 재확정).
회원이 보는 것                                요약 고지 → **계약서 본문 렌더**로 바뀐다(앱이
                                             template_version으로 번들 자산을 골라 vars를
                                             채운다). 그 뒤 서명은 sha256으로 봉인된다.
되돌리기                                      issuable을 false로 내리면 종전 경로로 즉시 복귀
                                             한다(스토어 읽기 횟수까지). 단 **이미 찍힌
                                             스탬프·봉인은 지워지지 않는다** — 되돌림은 "앞으로
                                             안 찍는다"이지 소급 삭제가 아니다.
```

### 템플릿 동결 시점 — 첫 서명이 경계다

```
첫 서명 전                                    **템플릿 교체 자유**. 스탬프·봉인된 문서가 0건인
                                             동안은 재현·검증 대상이 없어 문구·슬롯을 같은
                                             버전 키로 고쳐도 잃는 것이 없다(v2.19가 pt-v1을
                                             레지스트리에서 삭제한 것과 같은 근거).
첫 서명 후                                    **그 버전은 동결**. 봉인(sha256 = 버전 +
                                             canonical_json(vars))이 버전 문자열에 매달려 있어
                                             문구를 고치면 서명 당시 문서의 재현이 깨진다.
                                             변경은 **새 템플릿 버전 키**로 온다(§D ① 버전
                                             고정). 지난 버전은 레지스트리에서 지우지 않는다.
지금 위치                                     pt-v1-reported·pt-v1-exempt는 실서명 0건 — 아직
                                             교체 자유 구간이다. 앱 자산(템플릿 2종)·마스터
                                             문서와의 바이트 동기를 이 구간에 끝내는 것이
                                             권고다(P48 시점 기준 후속 과제).
```

### 데모 훅

```
EnableContractTemplatesForDemo               **사실상 no-op이 됐다**(이미 true인 엔트리를 true로
                                             쓴다). 제거하지 않는다: ① 래치를 되돌려도 데모
                                             경로는 켜진 채 남아야 한다(데모의 정직함이
                                             프로덕션 스위치에 인질로 잡히지 않는다) ② 이 훅을
                                             호출하는 통합 테스트가 **호출 전에** 레지스트리
                                             리터럴 상태를 단언해, 리터럴이 조용히 뒤집히는
                                             사고를 잡는 고정점 역할을 계속한다.
```

### 배포 순서

서버 단독(이 계약) — 와이어가 안 바뀌므로 앱·어드민 배포 의존이 없다. 대표의 데이터 입력 2건이
곧 스위치이므로, **입력 전에 앱의 템플릿 자산 2종이 실기기에 나가 있는지 먼저 확인**하는 것이
운영 순서다(자산이 없으면 vars는 찍히는데 회원 화면은 여전히 요약 고지로 폴백 — 거짓은 아니지만
"본 것 = 서명한 것"의 값어치가 반감된다).

---

## v2.23 데스크 체크인 QR — 서버가 발급하는 센터 비밀 (2026-08-30, P49, 이 섹션도 계약의 일부)

셀프 체크인(`POST /v1/checkin {source:"self_qr", qr_token}`)의 대조값을 **환경변수
`CHECKIN_QR_TOKEN`에서 센터 문서에 저장되는 서버 발급 비밀로** 옮긴다. 와이어에 엔드포인트
2개가 늘고, 체크인 요청·응답 자체는 한 글자도 바뀌지 않는다.

### 왜 (실사용 불능이었다)

종전 구조에서 QR을 인쇄하려면 대표가 **자기가 알 수 없는 문자열을 알아야** 했다. 값은 Cloud
Run 설정 안에만 있는데, 어드민 화면은 그 값을 대표에게 손으로 입력하라고 요구했고 그 위에
`sha256sum`으로 서버 값과 대조하라는 셸 명령까지 안내했다. 개발자가 옆에 붙지 않으면 끝나지
않는 화면이었다 — 센터 대표는 배포 설정을 볼 수 없고 서버 셸도 없다.

부수적으로 이 구조는 비밀 위생도 나빴다: 사람이 아는 비밀은 사람이 흘리고(메신저·메모),
손으로 옮기는 값은 손으로 틀린다(붙여넣기 공백·따옴표·비ASCII — 어드민이 그 사고를 진단하는
코드를 따로 들고 있었다는 것 자체가 증거다). 그리고 토큰이 샜을 때 대표가 스스로 되돌릴
수단이 **없었다**(재배포는 개발자의 일이다).

### 와이어 (신설 2개 — 둘 다 owner 전용)

```
GET  /v1/center/checkin-qr           → 200 {issued, token, issued_at}
POST /v1/center/checkin-qr/rotate    → 200 {issued, token, issued_at}   (요청 바디 없음)
```

```
issued      bool          발급된 적이 있는가. 어드민이 "발급"/"재발급" 버튼을 이 값으로 고른다.
token       string        인쇄 QR에 그대로 들어가는 원문. 미발급이면 "".
                          32자 URL-safe base64(crypto/rand 24바이트, RawURLEncoding).
                          문자셋 `A-Za-z0-9-_` — 전부 ASCII.
issued_at   string|null   마지막 발급 시각(RFC3339 UTC). 미발급이면 null.
```

`GET`은 **미발급도 200**이다(404 아님) — `{issued:false, token:"", issued_at:null}`. 미발급은
오류가 아니라 어드민이 그리는 정상 상태이고, 404로 만들면 진짜 오류와 구분이 사라진다.

`POST rotate`는 **바디를 읽지 않는다**. 읽는 순간 언젠가 "원하는 토큰을 지정" 같은 필드가 붙고,
그러면 사람이 고른 비밀이 다시 들어와 이 변경이 없앤 문제가 그대로 돌아온다. **토큰의 출처는
crypto/rand 하나뿐이라는 것이 계약이다.** 응답은 200이다(201 아님 — 새 리소스가 아니라 같은
리소스의 새 값이고 돌려줄 Location이 없다).

최초 발급과 재발급은 **같은 동사**다. 나누면 "이미 발급됨" 409 분기가 생기고 어드민이 상태를
먼저 조회해 버튼을 고르게 되는데, 조회와 실행 사이에 다른 창에서 발급이 끼면 대표는 무엇이
실패했는지 알 수 없는 에러를 본다. 발급은 애초에 멱등할 수 없는 행위(늘 새 값이다)라 확인은
UI의 몫이고, 서버는 "누르면 새로 난다"는 한 가지 의미만 갖는 편이 정직하다.

### 보안 규약 (이 절이 계약의 핵심이다)

```
owner 전용                                   trainer·member는 **두 엔드포인트 모두 403**이다.
                                             조회만 막으면 트레이너가 rotate로 새 토큰을 받아
                                             그 응답에서 값을 읽는다 — 한쪽만 잠근 문은 잠긴
                                             문이 아니다. 트레이너를 막는 것이 과하지 않은
                                             이유: 이 값은 "보는 권한"과 "가지는 권한"이 같다
                                             (한 번 보면 찍어서 영구 보관, 퇴사해도 사본은
                                             남는다). 트레이너가 회원 출석을 찍는 정당한
                                             경로는 tap 체크인으로 이미 따로 있다.
회원·트레이너 응답에 절대 없다                `GET /v1/center`(5키: center_id·name·policy·
                                             business·facility)와 무인증 `GET /v1/public/
                                             business`에 이 값은 **실리지 않는다**. 위협
                                             모델 전부가 한 줄이다 — 토큰을 아는 회원은 집에
                                             누워 출석을 찍는다. 전용 응답 타입으로만 나가고
                                             (마스킹 목록 방식이 아니다 — 그랬다면 다음에
                                             필드를 늘릴 때 잊어서 샌다), 키 집합 테스트가
                                             세 역할 × 두 엔드포인트로 고정한다.
재발급 = 직전 인쇄물 즉시 무효                절 통 교체라 이전 토큰이 남지 않는다. 이것이
                                             이 동사의 값어치다(유출 시 대표가 스스로 되돌릴
                                             유일한 수단). **어드민은 누르기 전에 경고해야
                                             한다** — 데스크에 붙은 종이가 그 순간 죽는다.
저장 위치                                    `centers/{id}` 문서의 `checkin_qr` 맵. 클라이언트는
                                             Firestore에 직접 접근하지 않는다(firestore.rules
                                             전면 차단) — 노출면은 이 API가 전부다.
읽기가 문서를 만들지 않는다                   `GetCheckinQR`는 지연 시딩을 하지 않는다. 읽기가
                                             토큰을 만들면 회원의 체크인 시도가 곧 발급이 되어
                                             **대표가 인쇄하지도 않은 QR이 유효해진다**.
                                             발급은 owner의 명시적 행위(POST rotate)뿐이다.
머지 쓰기                                    `checkin_qr` 절만 머지로 쓴다(Policy·Business·
                                             Facility·center 불침범 — P27 SavePolicy 교훈의
                                             네 번째 절). 반대 방향도 고정한다: 정책·사업자·
                                             시설 저장이 토큰을 지우면 증상이 "체크인이 안
                                             돼요"로만 보여 원인에 도달하지 못한다.
```

### `CHECKIN_QR_TOKEN`은 삭제됐다 — 폴백도, 기동 검증도 없다

세 안을 놓고 골랐다. **DB가 유일한 진실**(택함) / env를 DB 공백 시 폴백으로 유지 / 비기본
env 토큰을 최초 1회 DB로 흡수(이미 인쇄한 QR 보존).

```
env 폴백을 버린 이유                          폴백이 있으면 **재발급이 이전 토큰을 무효로
   (가장 결정적)                             만들지 못한다.** 유출된 env 토큰이 영원히
                                             통과하는데 어드민 어디에도 안 보여서, 대표는
                                             자기가 되돌렸다고 믿는다. 위에서 계약으로 박은
                                             "재발급 = 직전 인쇄물 무효"가 그 순간 거짓이
                                             된다 — 조용히 안전하지 않은 상태가 하나라도
                                             남는 안은 이 작업의 목적과 정면으로 어긋난다.
지연 흡수(c)를 버린 이유                     없는 문제를 푼다. 제품 미출시 — 온보딩된 회원 0,
                                             발급된 계약 0, 인쇄된 QR 0이다. 대가는 실재한다:
                                             읽기가 문서를 만드는 형태이고(이 코드베이스가
                                             GetBusiness·GetFacility에서 의도적으로 거부한
                                             모양), `CHECKIN_QR_TOKEN`이 Cloud Run 설정에
                                             남아 **다음 사람이 그것을 살아 있는 값으로
                                             읽는다**. 죽었는데 살아 보이는 설정은 덫이다.
기동 검증을 함께 지운 이유                    그 검증(`USE_FIRESTORE=true` + 저장소 기본값이면
                                             기동 거부)은 "env 미설정 → 저장소에 적힌 공개
                                             기본값으로 승격"이라는 **fail-open을 막던 것**
                                             이다. 읽는 코드가 사라져 승격될 기본값 자체가
                                             없어졌다. 아무도 안 읽는 변수 때문에 기동을
                                             거부하면 그 자체가 새로운 거짓말이 된다.
fail-closed는 어디로 갔나                     기동 검증에서 **요청 경로로 내려갔다.** 미발급
                                             센터의 self_qr은 폴백 없이 400이고, 문구가 조치를
                                             말한다: "데스크 체크인 QR이 아직 발급되지
                                             않았습니다 — 어드민 설정에서 발급해 주세요".
                                             `qr_token이 유효하지 않음`만 나오면 대표는
                                             인쇄물과 앱을 의심하며 헤맨다(고칠 곳은 어드민
                                             설정이다). 종전 공개 기본값 `rise-desk-checkin`
                                             을 보내도 통과하지 않는다.
레거시 배포 설정                              Cloud Run에 `CHECKIN_QR_TOKEN`이 남아 있어도
                                             **무해하다** — 읽히지 않고 기동을 막지도 않는다.
                                             지우는 것이 권고지만 배포 순서에 걸리지 않는다.
                                             config 테스트가 "env가 Config를 바꾸지 않는다"를
                                             고정해, 폴백이 되살아나는 회귀를 잡는다.
```

DEV_SEED 데모는 **고정 토큰**(`rise-desk-checkin` — 앱의 `CHECKIN_QR_TOKEN` dart-define
기본값과 같은 문자열)을 심는다. 실발급이면 매 구동마다 값이 달라져 카메라 없는 시뮬레이터·CI가
셀프 체크인을 끝까지 돌려볼 통로가 사라진다. 이 값이 공개돼 있어도 안전한 이유는 **범위**다:
`SeedDemo`는 `DEV_SEED=true`이고 **인메모리 스토어일 때만** 호출된다(`cmd/server/main.go`).
종전 구조의 위험은 "문자열이 알려졌다"가 아니라 "알려진 문자열이 **실 DB에 붙은 서버**에서
통했다"는 것이었고(그래서 기동 검증이 있었다), 그 조합이 여기서는 성립하지 않는다.

### 배포 순서

**서버 먼저, 어드민 나중.** 어드민이 먼저 나가면 두 엔드포인트가 404다.

배포 직후 프로덕션 센터는 **미발급 상태**다(env에 있던 종전 운영 토큰은 DB로 옮겨가지 않는다 —
위 (c) 기각). 즉 **대표가 어드민에서 발급을 누르기 전까지 셀프 체크인은 거부된다.** 제품
미출시(회원 0)라 실사용 중단이 아니지만, 순서상 사실이므로 명시한다. 데스크에 이미 붙어 있는
인쇄물이 있다면 그것도 무효다 — 발급 후 새 QR로 다시 인쇄해야 한다.

앱은 **무변경**이다. 스캔한 문자열을 가공 없이 보내는 규약(v1.2)이 그대로이고, 토큰 모양을
검증하지 않는다(대조는 전부 서버). 앱의 `CHECKIN_QR_TOKEN` dart-define은 여전히 스캔값이 빈
경우의 dev 폴백으로만 쓰이며, 그 기본값은 DEV_SEED 데모 토큰과 계속 일치한다.

## v2.24 센터 운영시간 — 09~21은 이제 정책 값이다 (2026-08-30, P51, 이 섹션도 계약의 일부)

`Policy`에 `open_hour`·`close_hour` 두 칸이 는다. 다른 엔드포인트는 늘지 않는다 — 기존
`GET /v1/center` 응답에 두 키가 실리고, 기존 `PUT /v1/center {policy}`가 같은 머지 시맨틱으로
그 두 칸을 받는다.

### 왜 (지금은 아예 표현할 수 없다)

어드민(`Schedule.tsx DEFAULT_HOURS`)과 회원앱(`booking_rules.dart openHour/closeHour`)이
각자 09~21을 하드코딩했고, 서버에는 그 개념을 담을 **필드가 어디에도 없었다.** 06시에 여는
센터와 23시까지 하는 센터는 그 시간대에 예약을 만들 수단이 없다 — 설정이 불편한 게 아니라
기능이 없는 것이다. 설계00 §3.1 "정책은 설정값(하드코딩 금지)"이 남겨 둔 마지막 조각이다.

### 필드

```
open_hour   int   첫 슬롯의 **시작 시각**(0~23). 기본 9
close_hour  int   마지막 슬롯의 **시작 시각**(0~23, 포함). 기본 21
```

**⚠ 이 두 칸은 "슬롯 시작 시각"이고 양끝을 포함한다.** `9~21`은 09:00 시작 슬롯부터 21:00
시작 슬롯까지 **13칸**을 뜻한다 — 21:00에 끝나는 것이 아니라 21:00에 **시작하는** 수업이
마지막이다(그 수업은 22:00에 끝난다).

```
올바름   for (h = open_hour; h <= close_hour; h++)     → 9~21이면 13칸
틀림     for (h = open_hour; h <  close_hour; h++)     → 21시 수업이 사라진다(영업 1시간 증발)
틀림     for (h = open_hour; h <= close_hour + 1; h++) → 없던 22시가 생긴다(예약 후 서버 거부 없음 —
                                                        서버는 시간대를 강제하지 않는다. 아래 참고)
```

이 한 줄을 틀리면 증상이 **조용하다**: 13칸이 12칸이 되어도 화면은 정상으로 보이고, 사라진
한 시간의 매출은 아무 에러도 내지 않는다. 서버 `domain.Policy.SlotHours()`가 같은 규칙으로
목록을 만드니, 의심스러우면 그 함수와 개수를 맞춰 본다.

### 검증

```
0 <= open_hour < close_hour <= 23
```

위반 시 400 + 두 숫자를 모두 담은 한국어 문구:
`"운영시간이 올바르지 않아요 — 여는 시각(21시)이 닫는 시각(9시)보다 앞서야 하고, 둘 다 0~23 사이여야 해요"`.
폼이 두 칸인데 어느 칸이 틀렸는지 말하지 않으면 대표는 같은 400을 반복해서 만난다.

`open_hour == close_hour`는 **거부**한다(하루 한 칸만 여는 센터는 v1 범위 밖 — 열려면 계약을
고친다). 그 결과 `(0,0)`은 **저장될 수 없는 조합**이 되고, 그 사실이 아래 기본값 규약을 성립시킨다.

### 기본값과 구문서 승격 — "0시"를 살려 두기 위한 선택

```
저장된 값이 (0,0)  → 읽을 때 (9,21)로 승격     v2.24 이전 문서에는 필드가 없어 제로값이 온다
명시적으로 (0,0)   → 400                        조용히 9~21로 바꿔 저장하지 않는다
open_hour = 0      → 그대로 0                   close_hour ≥ 1이면 **자정 개점은 정상 값이다**
```

이 코드베이스의 이웃 규약(`max_holds_per_pass`·`max_hold_total_days`, v1.2)은 "0 = 필드 부재
→ 기본값 승격"을 **필드 하나씩** 판정한다. 운영시간에는 그 규약을 그대로 옮길 수 없었다 —
**0시는 24시간 헬스장의 실제 여는 시각**이라, 0을 필드 단위 부재로 읽으면 자정 개점이 영원히
표현 불가능해진다(`-1`을 부재 센티널로 쓰는 안도 같은 이유로 안 된다: 구문서의 제로값은 어차피
0이라 구분이 되지 않는다).

그래서 부재 판정을 **개별 필드가 아니라 `(0,0)` 쌍**에 건다. `open < close` 검증이 그 쌍을
애초에 불법으로 만들어 두었으므로, 그 쌍만이 "필드가 없던 문서"의 서명으로 안전하게 쓰인다.
읽기는 관대하고 쓰기는 엄격한 비대칭은 홀딩 상한과 동일하다(0 읽기=승격 / 0 쓰기=400).

**기본값 9·21은 종전 하드코딩과 글자 그대로 같은 값이다.** 대표가 어드민에서 바꾸기 전까지
동작이 1분도 달라지지 않는 것이 이 기본값의 유일한 목적이다.

### 머지 시맨틱 (기존 그대로, 두 방향 모두)

`PUT /v1/center {policy}`는 머지다 — `{"open_hour":6}` 한 칸만 보내도 `close_hour`와 나머지
정책이 보존된다. **반대 방향이 더 중요하다**: `{"slot_capacity":3}`처럼 운영시간을 모르는
다른 폼이 저장해도 대표가 맞춰 둔 06~23이 9~21로 되돌아가지 않는다.

### 서버는 예약 시각을 운영시간으로 강제하지 **않는다** (v2.24 범위)

이번 변경으로 서버가 새로 거부하는 요청은 **없다.** `POST /v1/bookings`·`POST /v1/recurrings`는
종전대로 `hour 0~23`(슬롯키 형식 위생)만 보고, 운영시간 밖 예약을 막지 않는다. 의도한 범위다:

- 운영시간은 **화면을 그리는 값**이다. 서버가 강제하면 대표가 `close_hour`를 21→20으로 줄이는
  순간 **이미 잡혀 있는 21시 예약을 취소·이동조차 할 수 없게** 된다(그 예약을 만지는 모든
  경로가 400이 되어 잠긴다). 정책 변경이 과거를 소급 파괴하지 않는다는 이 코드베이스의 규칙
  (v2.0 "하드 삭제를 하지 않는 이유", 이관 시 과거 정산 귀속 보존)과 같은 근거다.
- 예약 시간대는 원래 사람이 정한다 — 데스크에서 대표가 특별히 잡아 주는 영업시간 외 수업은
  실재하는 정상 영업이다.

클라이언트는 운영시간 밖 슬롯을 **그리지 않는 것**으로 충분하다. 강제가 필요해지면 그때
별도 절로 추가한다(그때는 기존 예약의 유예 규칙을 함께 정해야 한다).

### 배포 순서 — **앱이 나가기 전까지 회원에게는 반영되지 않는다**

```
서버        먼저. 두 칸이 응답에 실리고 편집이 열린다(기존 클라이언트는 미지정 키를 무시 — 무해)
어드민      다음. DEFAULT_HOURS를 policy 값으로 바꾸고 편집 UI를 낸다
회원앱      **스토어 심사·배포가 끝나야 반영된다**
```

**명시한다: 회원앱은 `booking_rules.dart`에 09~21을 하드코딩한 빌드가 나가 있다.** 대표가
어드민에서 06~23으로 바꿔도, 그 값을 읽는 앱 빌드가 스토어에 올라가기 전까지 **회원 화면의
예약 가능 시간대는 09~21 그대로다.** 서버 배포만으로 "운영시간 변경이 회원에게 반영됐다"고
가정하면 안 된다 — 대표에게도 그렇게 안내해야 한다(어드민에는 이미 반영되므로 대표는 바뀐
것처럼 본다. 그 어긋남이 이 절의 존재 이유다).

---

## v2.25 트레이너 프로필 사진 업로드 — 서버가 올리고 토큰 URL로 읽는다 (2026-08-30, P51, 이 섹션도 계약의 일부)

`POST /v1/staff/{uid}/photo` 하나가 는다(owner 전용). `Staff.profile.photo_url`의 **모양과
의미는 바뀌지 않는다** — 채우는 수단이 하나 생길 뿐이라 기존 클라이언트 렌더 경로
(`TrainerAvatar`)는 무변경이다.

### 왜 (반쯤 만들어진 채 잠겨 있었다)

v1.6이 `photo_url`을 "외부 이미지 URL(http/https)"로 열면서 *"업로드는 Storage 트랙 후속"*
이라고 적었고, `storage.rules:90-95`는 그 설계를 **경로까지 예약**해 뒀다:

```
match /staff/photos/{fileName} { allow read, write: if false; }
// 서버(Admin SDK)가 올리고, 클라이언트는 **다운로드 토큰 URL**로 읽는다.
```

그런데 그 서버 경로가 존재한 적이 없었다. 그 사이 어드민 설정 화면은 대표에게 텍스트 박스
하나로 **"사진 URL(http/https …)"를 만들어 오라**고 요구했다 — 휴대폰이나 바탕화면에 있는
사진에는 URL이 없고, 제품 안에 URL을 만드는 수단도 없다. 규칙 주석이 적어 둔 설계를 그대로
구현해 잠금을 푼다.

### 와이어

```
POST /v1/staff/{uid}/photo    owner 전용
  요청  {"image": "<base64>", "content_type": "image/jpeg"|"image/png"|"image/webp"}
  응답  200 {"photo_url": "https://firebasestorage.googleapis.com/v0/b/{bucket}/o/staff%2Fphotos%2F{uid}-{난수}.{ext}?alt=media&token={토큰}"}
```

**호출 한 번으로 끝난다.** 서버가 파일을 올리고 `Staff.profile.photo_url`까지 갱신하므로
어드민이 이어서 `PUT /v1/staff/{uid}/profile`을 부를 필요가 없다 — 그 왕복 사이에 다른 편집이
끼면 사진이 되감긴다(프로필 PUT은 통 교체다).

프로필의 **다른 칸(직함·경력·자격증·소개문)은 건드리지 않는다.** 이 엔드포인트는
`photo_url` 한 칸만 만진다.

### 권한 — owner 전용 (프로필 편집 PUT과 다르다)

`PUT /v1/staff/{uid}/profile`은 owner **또는 본인 트레이너**가 되지만, 사진 업로드는
owner만이다. 근거: 이 호출은 센터 공용 버킷에 **파일을 만든다** — 되돌리는 수단·용량·비용이
전부 대표 쪽에 있다. 스태프 관리 계열(생성·정정·이관·퇴사·복직)이 전부 owner 전용인 것과
같은 경계다. trainer·member는 403.

### 검증 (전부 업로드 **전**의 400 — 버킷에 올라가는 것은 통과한 것뿐이다)

순서대로, 층마다 다른 한국어 문구를 낸다(어느 층이 잡았는지가 사용자 안내에 그대로 쓰인다):

```
① content_type  화이트리스트 image/jpeg · image/png · image/webp.
                 `; charset=…` 파라미터와 대소문자는 접는다. 그 외 → "사진은 JPG·PNG·WEBP 형식만 올릴 수 있어요"
② base64        표준 인코딩(패딩 포함). `data:image/...;base64,` **접두는 빼고** 보낸다 —
                 조용히 벗겨 주지 않는다(계약이 두 개가 된다). 문구가 무엇을 뗄지 말해 준다
③ 매직바이트     선언한 형식과 **실제 바이트가 일치**해야 한다(헤더는 클라이언트가 쓰는 값이라
                 신뢰하지 않는다). JPEG=FF D8 FF · PNG=89 50 4E 47… · WEBP="RIFF"
④ 크기          디코드된 원본 **2MB** 이하. 어드민이 클라이언트에서 축소하므로 예산이 아니라 백스톱
⑤ 완결성        "헤더는 멀쩡한데 몸통이 없는 파일"을 막는다(P44 서명 PNG의 IEND 교훈을 형식별로):
                   PNG  — IEND 청크(길이0+"IEND"+고정 CRC 12바이트)로 **끝나야** 한다.
                          절단본과 IEND 뒤 쓰레기를 접미 검사 하나로 함께 막는다
                   JPEG — EOI(FF D9)가 **존재**해야 한다(일부 인코더가 뒤에 패딩을 붙여
                          접미 일치는 정상 사진을 거부한다 — 존재로 본다)
                   WEBP — "WEBP" 시그니처 + RIFF 헤더의 **선언 길이가 실제 길이와 맞아야** 한다
                          (WebP에는 종료 청크가 없다. 잘린 파일은 선언한 수보다 짧다)
⑥ 치수          image.DecodeConfig로 헤더만 읽는다(픽셀을 풀지 않는다 — 디코드 폭탄 표면 불변).
                 가로·세로 각각 **64~4096px**(양끝 포함)
```

`uid`는 오브젝트 경로에 실리므로 `^[A-Za-z0-9_-]{1,128}$`만 받는다(경로 주입 차단, 400).
없는 스태프면 **404이고 파일을 만들지 않는다** — 아무도 가리키지 않는 오브젝트는 메타에서
출발하는 어떤 경로로도 발견되지 않는다.
퇴사 처리된 스태프(inactive)면 **400** `"퇴사 처리된 스태프의 사진은 올릴 수 없어요 — 재입사 처리 후
올려주세요"`(v2.31) — 역시 업로드 전이라 파일을 만들지 않는다. 퇴사가 파기한 것을 실수 한 번으로
되살리지 않기 위해서다.

요청 바디 상한은 이 경로만 **4MiB**다(공용 1MiB). base64가 3바이트를 4자로 부풀려 2MB 이미지가
약 2.67MiB가 되므로, 공용 상한으로는 계약이 허용하는 정상 사진이 먼저 막힌다.

### 저장 경로와 토큰 URL

```
staff/photos/{uid}-{난수8자}.{jpg|png|webp}
```

난수를 붙이는 이유는 두 가지다: **경로가 곧 버전**이라 교체본이 CDN·브라우저 캐시에 가려
옛 사진으로 보이지 않고(그래서 `Cache-Control: public, max-age=31536000, immutable`을 안전하게
건다), uid만으로 경로를 추측해 훑는 것도 막는다.

읽기는 **Firebase 다운로드 토큰 URL**로만 가능하다. 서버가 오브젝트 메타데이터에
`firebaseStorageDownloadTokens`(crypto/rand 16바이트 hex)를 붙이면 그 URL이 보안 규칙을
거치지 않고 열린다. `storage.rules`의 전면 차단(`allow read, write: if false`)과 모순이
아니라 규칙 주석이 명시한 설계 그대로다 — **클라이언트 SDK 직접 접근은 막고, 토큰을 아는
쪽만 읽는다.** 회원앱·어드민은 이 URL을 평범한 이미지 주소로 렌더한다(무인증).

`storage.rules`는 **변경하지 않는다.** Admin SDK는 보안 규칙을 지나지 않으므로(v2.11
MediaPurger와 같은 사실) 규칙을 열 이유가 없다.

### 교체 — 옛 파일은 지운다 (v2.31에서 개정 — best-effort 아님, 저장 앞, 실패 전파)

~~프로필에 이미 `staff/photos/…` 오브젝트를 가리키는 URL이 있으면 **새 URL이 저장된 뒤에**
그 오브젝트를 지운다. 삭제 실패는 업로드를 실패시키지 않는다(로그만 남긴다).~~
→ **v2.31 개정**: 순서는 "새 파일 업로드 → 옛 파일 삭제 → 프로필 저장"이고, 옛 파일 삭제가
실패하면 방금 올린 새 파일을 best-effort로 되지운 뒤 **에러를 전파**한다(프로필 무변경, 옛
URL·옛 파일 그대로). 저장 뒤 best-effort 삭제는 실패 시 옛 파일을 발견 경로 없는 고아로 만들었고,
privacy.html "교체하거나 지우면 이전 파일은 삭제되며"를 실패한 삭제 뒤에 숨기는 고지로 만들었다.
새 순서와 실패 창은 v2.31 "교체(⑤)" 절 참조. 위 문단은 v2.25 당시의 판단 기록으로 남긴다.

**`staff/photos/{uid}-` 명의가 아닌 URL은 절대 지우지 않는다**(v2.31 개정 — 종전엔 접두
`staff/photos/`만 봤다). 대표가 손으로 넣어 둔 외부 URL(v1.6부터 정상 경로다), 회원 체형사진
경로를 가리키는 토큰 URL, **다른 스태프 명의의 우리 파일**, 다른 버킷의 URL이 프로필에 들어
있어도 사진 교체 한 번이 남의 파일을 지우는 일이 없어야 한다. 호스트·경로 모양·접두·uid 명의·
버킷(STORAGE_BUCKET 설정 시)을 모두 본다.

오브젝트 경로를 프로필에 따로 저장하지 않고 **URL에서 되뽑는** 이유: `PUT /v1/staff/{uid}/
profile`은 통 교체라 어드민이 보내지 않은 필드는 지워진다. 서버만 관리하는 `photo_path` 칸을
두면 프로필 저장 한 번에 조용히 비고, 그때부터 교체가 옛 파일을 영원히 남긴다.

반대로 **프로필 저장이 실패하면 방금 올린 파일을 그 자리에서 지운다** — 아무도 가리키지 않는
오브젝트를 남기지 않는다(P22가 체형사진에서 겪은 상태: 회원 한 명의 버킷에 고아 50개).

### 미구성이면 **503**이다 (조용한 성공 금지)

`STORAGE_BUCKET`이 비어 있거나 서버가 Firebase 모드가 아니면 이 엔드포인트는 **503**을 낸다:
`{"error":"사진 업로드 저장소가 설정되지 않았어요(관리자에게 STORAGE_BUCKET 설정을 요청해주세요)"}`.

400이 아니라 503인 이유: 요청은 옳고 **서버가 준비되지 않았다**. 400으로 내리면 대표가 사진을
계속 바꿔 보며 원인을 찾지 못한다 — 고칠 사람은 배포 설정을 쥔 쪽이다.

파기(`MediaPurger`, v2.11)가 버킷 미설정 시 조용한 no-op으로 떨어지는 것과 **의도적으로
반대**다. 파기는 없어도 예약·결제가 멈출 이유가 없지만, 업로드가 no-op이면 어드민은
"저장됨"을 보고 회원앱은 빈 아바타를 본다. 그 조용한 no-op이 실제로 버킷에 고아 50개를
남긴 사고의 모양이다(v2.15).

**즉 `STORAGE_BUCKET`은 이제 업로드에 필수 설정이다**(파기에는 여전히 선택). 로컬 개발
(`FIREBASE_PROJECT` 미설정, 인메모리)에서는 항상 503이다 — 로컬에서 사진을 넣어 보려면
v1.6의 URL 입력 경로를 계속 쓴다.

### 퇴사·탈퇴와의 관계 (범위 밖 — 확인만) (v2.31에서 개정 — 퇴사 시 파기한다, 아래 v2.31 참조)

스태프 퇴사(`POST /v1/staff/{uid}/deactivate`)는 **소프트 전이**라 Staff 레코드도 프로필도
남는다(v2.0 "하드 삭제를 하지 않는 이유"). 따라서 **퇴사 시 사진 파일을 지우지 않는다** —
복직(`reactivate`)이 프로필을 그대로 되살리는데 파일만 없으면 깨진 이미지가 남는다. 회원탈퇴
파기 경로(`PurgeMemberPersonalData`, v2.11)는 회원 개인정보 전용이며 스태프 사진과 무관하다.
→ **v2.31**: 퇴사 시 파일을 파기하면서 `photo_url`도 함께 비우므로 "깨진 이미지" 우려는 사라진다 —
복직·재고용은 이니셜 아바타로 시작한다. 위 문단은 v2.25 당시의 판단 기록으로 남긴다.

현재 스태프를 **영구 삭제하는 경로는 서버에 없다.** 그래서 "지워진 스태프의 사진이 영원히
남는" 상태도 아직 존재하지 않는다. 그 경로가 생기는 날 사진 파기를 함께 정해야 한다 —
`staff/photos/` 접두를 훑는 reconcile(`POST /v1/body-photos/reconcile`의 스태프판)이 없다는
것도 그때의 과제다. 이번 절의 범위 밖이며, 여기 적어 둔 것이 전부다.

### 배포 순서

**서버 먼저, 어드민 나중.** 어드민이 먼저 나가면 이 경로가 404다. 앱은 **무변경**이다 —
`photo_url`을 이미지 주소로 렌더하는 규약이 v1.6 그대로이고, 값이 외부 URL이든 토큰 URL이든
앱은 구분하지 않는다.

v1.6의 URL 직접 입력은 **그대로 유효하다**(제거하지 않는다). 이미 외부 URL로 사진을 넣어 둔
센터가 깨지지 않아야 하고, 업로드가 미구성인 환경에는 그 경로가 유일한 수단이다.

---

## v2.26 탈퇴 파기 사각지대 — 요청 큐 2종이 이름·번호·메모를 남기고 있었다 (2026-08-30, P53, 이 섹션도 계약의 일부)

엔드포인트는 늘지 않는다. `DELETE /v1/me` 응답의 `purged`에 **칸 두 개가 는다**
(`consult_requests`·`join_requests`). 와이어 변경은 그게 전부이고, 실제 변경은 그 두 칸이
가리키는 **파기 자체가 종전에 일어나지 않았다**는 것이다.

### 왜 (지금까지 "지웠다"고 보고하면서 안 지우고 있었다)

Google Play 데이터 보안 심사 점검 중 발견. v2.11의 파기는 컬렉션 목록이 아니라 **모양**으로
정의돼 있었다 — "`centers/{centerID}/…` 아래에서 `member_id`가 일치하는 문서". 그 모양을
벗어난 개인정보 두 벌이 조용히 살아남았다.

```
join_requests      **최상위 컬렉션**(승인 전엔 센터 귀속 전) + member_id 없음(uid 키)
                   → 센터 스코프 스윕이 **구조적으로** 닿지 못한다. 담긴 것: 신청자가 직접
                     적은 **이름·전화번호 원본**(POST /v1/join/request, v1.2)
consult_requests   센터 스코프 + member_id 보유 → 닿을 수 있었는데 **목록에 없었다.**
                   v2.11(08-25)보다 v2.20(08-29)이 나중이라, 새 컬렉션이 파기 목록에
                   등록되지 않은 채 배포됐다. 담긴 것: 회원이 남긴 **자유 서술 note**
```

두 결함의 성격이 다르다 — 하나는 추상화의 사각지대, 하나는 등록 누락. 그래서 수리도 둘로
갈린다(아래 ⑤ 신설 vs 스윕 목록 추가).

무게: 개인정보보호법 §21①은 목적이 끝나면 **지체 없이** 파기하라고 하고, 이 두 컬렉션은
계약·결제 기록이 아니라 §21① 단서의 예외를 타지 못한다. 앱의 계정 삭제 화면과 배포된
개인정보처리방침이 *"지체 없이 파기"*를 약속하고 있으므로 **화면이 서버가 지키지 않는 약속을
하고 있었고**, Play 데이터 보안의 "사용자가 삭제를 요청할 수 있음" 답변도 그 두 항목에 대해서는
사실이 아니었다.

특히 join_requests는 하나 더 있다: `JoinApprove`가 `jr.name`·`jr.phone`을 **그대로 새 회원
레코드로 굳힌다**(v1.7). pending 요청 하나가 남아 있으면 대표의 승인 한 번으로 파기한
이름·번호가 되살아난다 — v2.11이 *"phone을 비우는 것이 이 설계의 급소"*라며 세운 방어선을
컬렉션 하나 옆에서 우회하는 경로다.

### 파기·보존 판정 (컬렉션별로 따로 내렸다 — 일괄 적용하지 않는다)

```
JoinRequest      **완전 삭제**(익명화 아님)
  근거   처리 목적 = "이 사람을 센터 회원으로 매칭·승인". 계정이 사라지면 그 목적은
         **영구히 달성 불가능**하다(승인해도 붙일 계정이 없다).
  왜 익명화가 아닌가  이름·번호를 지우면 남는 것은 {center_id, status, created_at}뿐이다 —
         가리키는 사람도, 할 수 있는 일도 없는 껍데기다. 가명화는 **남은 것에 쓸모가 있을 때**
         쓰는 수단이고(Ledger가 그렇다), 여기엔 그 쓸모가 없다.
  범위   **센터로 좁히지 않는다**(uid 전체). 다른 센터 큐에 남은 요청도 같은 사람의
         이름·번호이고, 그 계정은 이제 존재하지 않아 어느 센터도 승인할 수 없다.
  상태   pending·approved·rejected **전부**. 거절된 요청도 이름·번호를 그대로 품는다.

ConsultRequest   **완전 삭제**(익명화 아님)
  근거   거래 기록이 아니다 — 이 큐에서 결제·발급은 일어나지 않는다(v2.20 본문). 데스크가
         상담 후 남기는 실제 사업 기록은 Pass·Payment·Contract이고 **그쪽은 전부 보존된다.**
         상담 요청은 그 앞의 손잡이일 뿐이라 5년 보존의 대상이 아니다.
  note   회원이 직접 쓴 자유 서술이라 무엇이 적혔는지 서버가 알 수 없다. 실제로 "무릎이
         아파서" 같은 건강 서술이 들어온다 — v2.11이 파기로 분류한 coach_note·flags[injury]와
         같은 성격이고, 보존 근거는 없다.
  왜 note만 비우지 않는가  탈퇴 후의 상담 요청은 **처리 자체가 불가능**하다(연락 수단이
         전부 파기됐다). 남기면 데스크 큐에 영원히 처리 불가능한 유령 행이 남는다 —
         v2.17이 미서명 계약을 voided로 종결한 것과 같은 판단인데, 그쪽은 **문서 보존
         의무가 있어서** 상태만 바꿨고 이쪽은 그 의무가 없어 문서째 지운다.
  집계   어떤 통계·KPI도 이 컬렉션을 읽지 않는다(삭제해도 숫자가 흔들리지 않는다).
```

### 실행 순서 — ⑤ 신설(v2.11 절의 실행 순서, 위에서 개정)

`consult_requests`는 `PurgeMemberPersonalData`의 **스윕 목록에 한 줄 추가**로 끝난다(이미
사정거리 안이다). `join_requests`는 그 동사가 닿지 못하므로 **새 스토어 동사 +
새 단계**다.

```
Store.DeleteJoinRequestsByUID(ctx, uid) (int, error)
  · 최상위 컬렉션을 uid로 훑는다(센터 무관, 단일 필드 필터 — 복합 인덱스 불요)
  · 없는 uid도 성공(0건) — DeleteUserIndex와 같은 규약. 재시도가 막히면 이름·번호가 영구 잔존
  · **빈 uid는 아무것도 지우지 않는다** — Firestore의 `uid == ""`는 uid가 빈 레거시 문서에
    실제로 매칭한다(Memory만 보면 안 보이는 차이. 두 구현 모두 가드하고 적합성이 고정)
```

⑤의 자리가 ⑥(가명화)보다 **앞**인 것이 규약이다. 뒤에 두면 실패한 순간 회원 문서는 이미
탈퇴 상태라 재시도가 400에 막히고 이름·번호가 영구히 남는다 — v2.17이 ④를 ⑤ 앞에 둔 것과
같은 이유이고, 같은 성질(멱등)이라 부분 실패 후 재시도가 몇 번을 돌아도 결과가 같다.

### 파기 목록에 없는 것 — Contract.vars의 이름·전화번호는 **남는다**

v2.18(§D ①)이 send 시점에 `{{회원명}}`·`{{회원 전화번호}}`를 `vars`에 얼린다. 계약은 5년
보존이므로 **이름·전화번호가 계약 스냅샷 안에서 그만큼 살아남는다.** 검토했고 **파기하지
않기로** 했다.

```
① 봉인이 vars를 덮는다   sha256 = SHA-256(template_version + "\n" + canonical_json(vars)) (§D ②)
                        vars에서 한 글자만 바꿔도 재계산 대조가 깨져 **서명된 계약의 사후
                        변조 검출이 영구히 불가능**해진다. 봉인을 함께 다시 계산하는 것은
                        더 나쁘다 — 그 연산은 진짜 변조와 구별되지 않는다.
② 문서의 내용이다        계약서의 당사자 표시는 그 문서를 계약서이게 하는 것이다. 5년 보존의
                        목적이 "그 거래가 있었다"의 입증인데, 당사자가 빈칸인 처분문서는
                        그 목적을 잃는다. 전자상거래법 §6②는 거래기록과 함께 식별정보 보존을
                        **명시적으로 허용**한다(v2.11이 회원 문서에서 쓰지 않기로 한 그 허용).
```

v2.11의 *"성명 보존을 일부러 쓰지 않는다"*와 모순처럼 보이지만 아니다. 그쪽에서 이름은
**거래 기록을 가리키는 색인**이라 없어도 기록이 완전했다(그래서 불필요해진 개인정보였다).
여기서 이름은 **기록 그 자체의 내용**이다. 같은 조문을 한쪽에선 쓰지 않고 한쪽에선 쓰는 것이
일관된 판단이다.

⚠ **다만 이것은 고지의 대상이다.** 개인정보처리방침·계정삭제 안내가 *"이름·휴대폰 번호는
삭제됩니다"*라고만 적고 있으면 그 문장이 부정확해진다. 문서 수정은 이 절의 범위 밖이고
P53에 필요한 문장이 적혀 있다.

미서명(draft/sent) 계약에 한해 봉인이 아직 없으므로(§D ② — 봉인은 sign의 일) vars 레닥션이
**기술적으로는** 가능하다. 채택하지 않았다: 탈퇴 void 스윕과 서명이 경합하면(v2.17이 실제로
방어하는 창) 레닥션된 vars 위에 봉인이 찍혀 **당사자가 "[파기됨]"인 서명 계약**이 생긴다 —
지금 상태보다 나쁘다.

### 검증

```
파기 완전성   탈퇴가 그 회원의 가입 요청(pending·rejected 전부)과 상담 요청을 실제로 지우는가
격리          같은 센터 이웃 회원의 상담 요청 · 아직 회원이 아닌 이웃 신청자의 가입 요청은 온전한가
              (uid가 **빈** 레거시 문서도 살아남는가 — 빈 uid 가드)
멱등          ⑤ 부분 실패 → 가명화 전에 멈추고 UserIndex 보존 → 같은 토큰 재시도가 완결
정직성        응답 purged의 두 칸이 실제 삭제 건수와 일치(건수를 믿지 않고 다시 읽어 대조)
계약 vars     탈퇴 후에도 회원명·전화번호가 그대로이고 **봉인 재계산이 여전히 일치**
와이어        라우터를 태워 JSON 키로(purged에 consult_requests·join_requests 존재)
```

### 남은 갭

`Contract.signature_png`(v2.21)도 계약 문서 안에 있어 5년 보존을 상속한다. vars의 이름·번호와
같은 성격의 잔존이고 같은 결론(문서의 내용이므로 보존)이지만, v2.11의 *"가명만 붙은 거래
기록"*이라는 표현은 그것까지 포함해 **문자 그대로는 사실이 아니다.** 위 v2.11 절에 개정
주석을 달아 두었다.

보유기간(5년) 만료 후 자동 파기는 여전히 없다(P22 후속 5) — 그 배치가 생기면 계약 문서의
이름·번호도 그때 함께 사라진다. 그때까지는 고지가 그 자리를 대신한다.

## v2.27 대기실(Lobby) — 대기 상태의 주인을 로컬에서 서버로 옮긴다 (2026-09-02, P55, 이 섹션도 계약의 일부)

센터에 연결되지 않은 회원이 앱에서 **막다른 길에 갇혀 있었다.** 화면 제목은 "센터 선택"인데
아래에 센터 목록이 없고, 있는 것은 "가입 요청을 보냈어요" 카드와 [연결됐는지 확인]
[다시 요청] 두 버튼뿐이다. 그 상태의 주인은 **앱의 SharedPreferences**였다.

이 절은 게이트를 옮기지 않는다(미연결 회원은 여전히 홈에 못 들어간다). 게이트를 **진실하고
유용하게** 만든다. 그리고 그 과정에서 발견된, **이미 배포돼 있던 CRITICAL 2건**을 고친다.

### 왜 (고친 것 중 둘은 이미 사용자를 다치게 하고 있었다)

```
C-2  좀비 가입 요청이 회원 기록을 통째로 날린다        (데이터 손실 · 되돌릴 API 없음)
C-3  미연결 계정은 자기 이름·전화번호를 지울 수 없다   (개인정보보호법 §36 삭제 요구권)
```

**C-2의 재현 경로**(전부 정상 동선이다 — 어느 단계도 오용이 아니다):

```
① 회원이 앱에서 가입 요청       join_requests에 pending 1건 (이름·전화번호 원본)
② 대표가 데스크에서 그 사람을    members에 진짜 레코드 생성
   어드민에 직접 등록
③ 회원이 번호 인증 → match      UserIndex.member_id = ②의 레코드
   → confirm 으로 **연결**       회원권·예약·수업기록·체형사진이 전부 여기 붙는다
④ ①의 pending은 **그대로 남는다**  JoinConfirm이 join_requests를 건드리지 않았다
⑤ 며칠 뒤 대표가 큐를 정리하다   SaveMember가 **빈 회원 레코드를 새로 만들고**
   ①을 승인                      SaveUserIndex가 신원을 그리로 옮긴다
                                 → 회원권·예약·기록·사진 전부 상실. 되돌릴 API 없음
```

`JoinApprove`의 멱등 가드(v1.9)가 이것을 못 본다 — 그 가드는 **그 요청 문서의 status만**
보는데 ①은 여전히 정직하게 pending이고, 진실은 다른 문서(UserIndex)에 있었다. 게다가
목록이 pending 필터를 하지 않아 **처리된 요청이 큐에 남는 것이 기본 상태**였고, 대표가
큐를 줄일 수단은 승인 하나뿐이었다(거절이 없었다) — ⑤는 예외 동작이 아니라 유일한 동선이었다.

**C-3**: `DeleteMyAccount`가 `p.MemberID == ""`이면 `store.ErrNotFound`(404)로 **진입부터**
막았다. 근거는 "지울 대상 자체가 없다"였는데 사실이 아니었다 — join_requests에는 신청자가
직접 적은 **이름·전화번호 원본**이 있고 Firebase 계정에는 인증된 번호가 있다. v2.26이 만든
파기 경로(`DeleteJoinRequestsByUID`)에 도달할 길이 **회원이 된 사람에게만** 열려 있었던 것이다.

### 와이어 변경 (엔드포인트 1개 신설 · 필드 3자리 추가)

```
POST /v1/join/reject {request_id}                  신설(owner 전용)
GET  /v1/me                     → join_request?    member_id가 없을 때만
PUT  /v1/center                 ← center{...}      덩어리 3번째(policy·business 옆)
GET  /v1/center                 → center{...}      상호·전화·주소 되읽기
DELETE /v1/me                                      미연결 계정도 200(종전 404)
GET  /v1/join/requests          → pending만        (필터는 응답에만 — 문서는 남는다)
POST /v1/join/request           → 409 추가          같은 uid의 pending 중복
```

#### GET /v1/me — `join_request`

```jsonc
// 미연결(대기실) — member_id가 없다
{ "uid":"u_abc", "role":"member", "center_id":"rise",
  "join_request": { "status":"pending", "created_at":"2026-09-02T05:14:00Z" } }

// 요청한 적 없음 — **키 자체가 없다**(omitempty)
{ "uid":"u_abc", "role":"member", "center_id":"rise" }

// 연결된 회원 · 스태프 — **키 자체가 없다**
{ "uid":"u_abc", "role":"member", "center_id":"rise", "member_id":"mem_1", "name":"김민지" }
```

```
status     "pending" | "approved" | "rejected"   (store.JoinRequest.Status 그대로)
created_at RFC3339 UTC
```

**두 칸뿐인 것이 규약이다.** `id`·`name`·`phone`·`center_id`는 싣지 않는다 —
`JoinMatchMember`(연결 전 최소 노출, v1.9)와 같은 규율이다. 이름·번호는 신청자가 방금 자기
손으로 적은 값이라 서버가 되돌려줄 이유가 없고, `id`는 승인·거절이 owner 전용 동사라
신청자에게 쓸모가 없다(있으면 "그 id로 무엇을 할 수 있나"를 찾게 만드는 표면만 는다).
`center_id`는 v1 단일 센터라 진실이 아닌 선택지를 암시한다.
⚠ v2.34 개정: **`center_id`를 싣는다**(3칸). 위 근거는 v2.33이 센터 선택을 열면서 소멸했다 — 이제는
감추는 쪽이 거짓이다(요청은 2호점에 있는데 대기실은 1호점 연락처를 찍는다). 조회도 센터가 아니라
**uid 기준**이다. v2.34 절 참조.

**오라클 표면 없음**: 자기 uid로만 스코프된다. 남의 존재를 캐낼 수 없다.

**best-effort다** — 조회가 실패해도 `/v1/me`는 200이다(표시 이름 `name`과 같은 규약).
이 호출이 실패하면 앱은 온보딩도 시작하지 못하는데, 대기 상태 하나 때문에 그 위험을 지지 않는다.

**`approved`가 나올 수 있는 유일한 경우**는 승인 도중 `SaveUserIndex`만 실패한 부분 잔여다
(정상 승인은 member_id가 생기므로 이 필드가 사라진다). 앱은 그 값을 "승인됐는데 아직
연결 중"으로 다루고 재조회하면 된다 — 잘못된 상태가 아니라 드문 중간 상태다.

#### POST /v1/join/request — pending 중복 409

```jsonc
// 409
{ "error": "이미 보낸 가입 요청이 있어요 — 센터에서 확인하면 연결돼요" }
```

`CreateConsultRequest`(v2.20)와 **같은 규칙·같은 문구 형태**다 — 새 패턴이 아니라 같은
"회원발 요청 큐"에 이미 있던 규칙을 이쪽에도 맞춘 것이다. uid 스코프이므로 다른 신청자는
막히지 않는다. **pending이 아닌 요청은 판정 대상이 아니다** — 거절된 뒤에는 다시 요청할 수 있다.

#### POST /v1/join/reject — owner 전용

```jsonc
// 요청
{ "request_id": "jreq_1a2b" }

// 200 — 갱신된 요청 문서(name·phone이 빈 값이다)
{ "id":"jreq_1a2b", "center_id":"rise", "uid":"u_abc",
  "name":"", "phone":"", "status":"rejected", "created_at":"2026-09-02T05:14:00Z" }
```

```
403  owner가 아님 · 남의 센터 요청(JoinApprove와 같은 두 겹 가드)
404  **없는 request_id — 이 하나뿐이다**
409  이미 처리된 요청("이미 처리된 가입 요청이에요")
```

⚠ **상태 충돌에 404를 쓰지 않는다.** 어드민은 이 엔드포인트의 404를 "이 배포에 아직 거절
기능이 없음"으로 접어 안내 문구를 띄운다 — 두 사건이 같은 코드로 겹치면 이미 거절한 요청을
다시 눌렀을 때 "거절 기능이 아직 서버에 올라가지 않았어요"가 뜬다.

#### PUT/GET /v1/center — `center` 덩어리

```jsonc
// 요청 — 셋 다 선택. **보낸 칸만 갱신**(policy와 같은 머지 시맨틱)
{ "center": { "name":"라이즈 컨디셔닝", "phone":"02-555-1234", "address":"서울 강남구 …" } }

// 응답(PUT·GET 동일) — GET /v1/center 전체 모양
{ "center_id":"rise",
  "name":"라이즈 컨디셔닝",                                    // 하위호환 유지(center.name과 같은 값)
  "center":{ "name":"…", "phone":"…", "address":"…" },        // v2.27 신설
  "policy":{…}, "business":{…}, "facility":{…} }
```

```
400  id·status·created_at을 보내면 거부(DisallowUnknownFields)
400  policy·business·center 중 아무것도 없으면 거부
403  owner가 아님
```

⚠ **`id`·`status`·`created_at`은 봉인이다.** `SaveCenter`는 두 스토어 구현 모두 `c.ID`를
쓰기 대상 **키**로 쓴다 — `{"id":"gangnam-2"}` 하나가 통과하면 대표의 편집 폼이 **남의 센터
문서를 덮어쓴다.** 그래서 요청 타입을 `domain.Center`가 아니라 세 칸짜리 전용 patch로 둔다.
포인터인 이유는 부분 갱신이다: 보내지 않은 칸은 그대로 두고, **보낸 칸은 빈 문자열이어도
반영한다**(잘못 적은 주소를 비워서 지우기 — business가 통 교체로 얻은 성질을 머지에서 얻는다).

`name`을 top-level에도 남긴 이유: 앱·어드민이 이미 읽고 있는 키라 지우면 배포 순서가 뒤집힌다
(서버 먼저 → 클라이언트 나중이 아니라 그 반대가 된다). `center.name`과 항상 같은 값이다.

#### DELETE /v1/me — 미연결 계정 (종전 404 → 200)

```jsonc
// 미연결 계정의 응답 — **키 집합은 회원 경로와 같다**(숫자만 0)
{ "deleted":true, "member_id":"", "withdrawn_at":"2026-09-02T05:20:00Z",
  "purged":{ "body_photos":0, "inbody":0, "workout_logs":0, "hw_checks":0, "checkins":0,
             "recurrings":0, "consult_requests":0, "join_requests":1 },
  "retained":{ "passes":0, "payments":0, "contracts":0, "ledger":0, "bookings":0 },
  "cancelled_bookings":0, "remaining_sessions":0 }
```

키가 달라지지 않는 것이 규약이다 — 앱의 완료 화면은 서버가 준 숫자만 옮기는 장치이고
(v2.11 `RetainedCounts`), 계정 종류에 따라 키가 갈리면 그 화면이 분기를 갖게 된다.
앱 1.0(5)+가 이 응답의 `purged.join_requests`·`member_id`를 완료 안내에 읽는다 — v2.29 절 끝 소비자 메모 참조.

**탈퇴한 회원의 재호출도 이제 200이다**(종전 404). 탈퇴는 UserIndex를 지우므로 그 토큰의
principal은 member_id가 없는 상태가 되는데, 그것은 **아직 연결되지 않은 대기실 계정과
완전히 같은 모양**이다 — 서버가 둘을 구별할 수단이 없고, 대기실 쪽은 반드시 열려야 한다
(C-3). 응답이 말하는 것은 "이 계정에 남은 것이 없다"이고 그것은 사실이다. 실제로 이 호출이
가능한 창은 Firebase 계정 삭제 후 ID 토큰이 살아 있는 최대 1시간뿐이다.

### C-2를 고친 방법 — **원인 제거와 방어선을 둘 다 둔다**

```
원인 제거   JoinConfirm이 성공하면 그 uid의 가입 요청을 파기한다
            → P53이 만든 Store.DeleteJoinRequestsByUID를 **재사용**(새 스토어 동사 없음).
              그 동사의 규약이 이 자리에 정확히 맞는다: uid 전체 스코프(다른 센터 큐의 요청도
              같은 사람의 것이고, 연결된 지금은 어느 센터도 승인해선 안 된다) · 없는 uid도
              성공 · 멱등.
            → 자리는 **맨 뒤**다. 앞의 두 쓰기(SaveMember·SaveUserIndex)가 연결의 본체라,
              이걸 앞에 두면 "큐에서도 사라지고 연결도 안 된" 사람이 생긴다 —
              대표에게 보이지 않는 사람이다. 뒤에 두면 반대 잔여("연결됐는데 큐에 남음")가
              생길 수 있지만 그쪽은 아래 방어선이 무해하게 만들고 재시도가 마저 지운다.
            → confirm=false("본인이 아니에요")는 아무것도 지우지 않는다(연결되지 않았다).

방어선      JoinApprove가 **이미 회원으로 연결된 uid**를 거절한다 → 409
            → 이미 배포된 프로덕션에 잔여 요청이 실재하므로 원인 제거만으로는 부족하다.
            → guardNotStaff가 이미 GetUserIndex를 부르는 자리 옆이다(조회 1회 추가).
```

⚠ **이 가드는 탈퇴 후 재가입을 막지 않는다 — 막으면 안 된다.** 탈퇴는 `DeleteUserIndex`를
수행하므로 `GetUserIndex`가 ErrNotFound → 가드 통과 → 정상적으로 새 레코드가 생긴다.
그리고 탈퇴자에게 `JoinConfirm`은 `IsWithdrawn`으로 막혀 있으므로(v2.11) **가입 요청 승인이
돌아오는 유일한 길**이다. 여기서 막으면 탈퇴한 사람이 영원히 못 돌아온다 —
`TestJoinApproveAllowsRejoinAfterWithdrawal`이 그 성질을 고정한다.

**이미 프로덕션에 남아 있는 좀비 요청의 처리**: 승인은 이제 409이므로, 대표는 새로 생긴
거절(D-3)로 큐에서 내린다. 그 문서는 `{uid, center_id, status, created_at}`만 남고
이름·번호는 사라진다.

### 큐가 진실을 말하게 — pending 필터와 거절

`ListJoinRequests`가 **pending만** 돌려준다. 종전엔 승인·거절된 요청이 큐에 남아 대표가
"처리할 것"과 "처리한 것"을 구별할 수 없었고, 그 착시가 두 번 누르는 동선을 만들었다
(`JoinApprove`의 v1.9 주석이 *"두 번 누르는 게 기본 동선이다"*라고 자인하고 있었다 —
그 문장이 이 절에서 사라진다).

```
감사 추적은 없어지지 않는다   필터는 **응답에만** 걸린다. 스토어의 동사는 여전히 전체를
                             돌려주고, 문서는 status만 바뀐 채 남는다. 어느 것도 삭제되지
                             않는다(삭제는 탈퇴 파기뿐 — v2.26). 이력 뷰가 필요해지면
                             여기에 status 쿼리 파라미터를 여는 것이 다음 단계다. 지금 열지
                             않는 이유는 **그것을 읽을 화면이 없어서**다.
필터를 스토어가 아니라       Firestore에서 Where(center_id)에 Where(status)를 더하면 복합
서비스에서 하는 이유         인덱스가 필요하고, 인덱스 없이 배포되면 **프로덕션에서만** 500이
                             난다(Memory 구현으로는 보이지 않는다). 큐 규모가 센터당 수십
                             건이라 서버 필터가 그 위험보다 싸다(ListMembers 필터와 같은 판단).
```

**거절이 이름·번호를 비우는 것**은 P53과 모순이 아니다. P53이 탈퇴 파기에서 익명화를 기각한
근거는 *"남은 것에 쓸모가 없을 때"*였다(껍데기만 남는다). 여기서는 남은
`{uid, center_id, status, created_at}`에 쓸모가 생긴다 — 신청자에게 **결론을 전달한다**
(`GET /v1/me`의 `join_request`가 rejected를 읽는다). 같은 컬렉션을 한쪽에선 지우고
한쪽에선 비우는 것이 일관된 판단이다.

**문서를 통째로 지우지 않는 이유**: 지우면 신청자 화면은 "요청한 적 없음"으로 되돌아가고,
그 사람은 "왜 아직 승인이 안 되지"라며 다시 요청한다 — 끊을 수 없는 재요청 루프가 생기고
pending 중복 409도 그것을 막지 못한다(pending이 없으니 통과한다).

### 열지 않은 것 — 바디의 `center_id`는 **계속 무시한다**

`JoinRequestCreate`의 봉인은 유지된다. **다만 이유가 갱신됐다**:

```
종전의 이유   "그 센터의 회원인가"를 검증할 자리가 없다(멀티센터 미도래)
지금의 이유   **넣을 목록이 없다.** 회원용 센터 목록 API가 없고(GET /v1/admin/centers는
              superadmin 전용), ListCenters는 name이 빈 센터를 유령으로 거르는데 **운영
              센터가 바로 그 상태였다** — 열어 봐야 고를 것이 0개인 선택지다.
```

v2.27은 그 선행조건 쪽을 먼저 고친다(PUT /v1/center의 `center` 덩어리로 센터가 신원을 갖는다).
**선택을 여는 조건은 셋이다**: ① 신원 등록된 센터가 2곳 이상 ② 회원이 읽을 수 있는 목록
엔드포인트 ③ `JoinRequestCreate`에 "그 센터가 실재하고 가입을 받는가" 검증. 셋이 갖춰지기
전에 바디 값을 믿으면 종전 결함(존재하지 않는 센터로 200 → 어느 큐에도 안 뜨는 영원한
pending)이 그대로 돌아온다.

### 무변경 — 기존 가드 3겹

```
joinPhone       토큰의 검증된 phone_number가 유일한 출처(v1.7/P06)
guardNotStaff   스태프 uid를 회원으로 연결(=강등)하지 못하게(v1.9)
IsWithdrawn     탈퇴 레코드에 재연결 불가(v2.11)
```

이 절은 셋 중 어느 것도 건드리지 않는다. `GET /v1/center`의 체크인 QR 토큰 비노출
(v2.23 키 집합 고정)도 그대로다 — `center` 블록은 전용 응답 타입이라 토큰이 무임승차할
자리가 없고, 키 집합 테스트가 6키로 갱신돼 다음 필드 추가 때도 같은 질문을 강제한다.

### 배포 순서

```
서버 먼저, 클라이언트 나중.  PUT /v1/center의 decodeJSON은 DisallowUnknownFields라
                            **서버가 먼저 center 필드를 알아야** 어드민이 보낼 수 있다
                            (v2.13이 business를 넣을 때와 같은 규약).
앱은 그 다음.                join_request는 추가 필드라 구 앱이 무시한다(호환 파괴 없음).
                            거절 기능도 어드민이 없는 동안 서버에만 있어도 무해하다.
```

### 검증

```
뮤테이션        가드를 하나씩 지워 테스트가 실제로 죽는지 확인(17건 전부 KILLED — work_log/P55)
C-2 재현        연결 후 남은 좀비 요청 승인 → 409 + UserIndex·회원권·회원 수 불변
C-2 원인        confirm 성공 후 그 uid의 요청이 사라지고 **이웃 신청자 것은 남는가**
재가입          탈퇴 → confirm은 여전히 400 · request→approve는 200 + **새 레코드**
C-3             미연결 탈퇴가 join_requests를 실제로 지우고 Firebase DeleteUser를 부르는가
                (저장소를 다시 읽어 대조 — 응답의 건수를 믿지 않는다)
C-3 순서        ⑤ 실패 → ⑦(UserIndex) 미실행 → 같은 토큰 재시도가 완결
스태프 가드     owner·trainer·superadmin이 미연결 분기로 새지 않는가(가드 ① 무변경)
최소 노출       join_request를 JSON으로 굳혀 키 2개 + 이름·번호 미포함
격리            center 저장이 policy·business·facility를 건드리지 않는가(P27 교훈)
봉인            center.id/status/created_at → 400 · 남의 센터 문서 무변경
와이어          라우터를 태워 상태코드(200/400/403/409/404)와 JSON 키까지 고정
에뮬레이터      스토어 인터페이스 **무변경**이므로 신규 케이스 없음. 새로 밟는 경로
                (기존 센터 문서 위의 SaveCenter 머지)는 testCenterIdentity가 이미 고정하고
                있고, firestore_emulator 러너 전량 통과를 재확인했다.
```

### 남은 갭

```
① /v1/me의 대기 조회가 센터 큐 전체를 훑는다   미연결 회원에게만 도는 경로이고 큐가 수십
                                              건이라 지금은 값싸다. 큐가 커지면
                                              ListJoinRequestsByUID(단일 필드 필터라 복합
                                              인덱스 불요)가 다음 단계다.
② 승인 부분 실패의 잔여                        SaveUserIndex만 실패하면 approved 요청 + 인덱스
                                              없음이 남는다. /v1/me가 status:"approved"를
                                              정직하게 보고하지만 자동 복구는 없다(재승인은
                                              409). v2.6 계열의 트랜잭션화가 남은 자리다.
③ 회원의 센터 선택                             위 "열지 않은 것"의 세 조건이 갖춰지면.
④ 거절 이력 뷰                                 큐는 pending만 보여준다. 문서는 남아 있으므로
                                              status 파라미터를 여는 것으로 족하다.
```

## v2.28 P56 감사 후속(백엔드) — 승인 후 잔류 개인정보 · 배열 null 읽기 정규화 · 파기 경계 미구성 503 · 철회 후 파기 경로 · 라우터 404 구분 (2026-09-04, P57, 이 섹션도 계약의 일부)

P56 감사가 잡은 백엔드 결함 중 **"저장소가 다른 곳에서 이미 내린 판단과 어긋나는 자리"** 5건을 닫는다.
새 기능이 아니다 — 형제 동사가 이미 내린 판단을 따라가게 만드는 것이다. 각 항목 옆에 그 선례를 적었다.

### 왜

```
A5   JoinApprove가 이름·번호를 남긴다         3줄 옆 JoinReject는 "처리 목적이 끝난 개인정보"라며 둘 다 비운다.
     DoneConsultRequest가 note를 남긴다       P53: 상담 요청 큐는 5년 보존 대상이 아니다(결제·발급이 일어나지 않는다)
A3   Payment.installments가 null로 굳는다     Member.flags·Pass.holds는 "어드민 크래시 방지" 주석까지 달고
                                             정규화 — 여기만 빠졌고, **읽기 쪽** 정규화는 셋 다 없었다
A4   파기 경계 강등 4곳이 ListObjects→nil,nil  같은 파일 unconfiguredUploader는 "조용한 성공을 절대 만들지
                                             않는다"(503). reconcile이 미구성 서버에서 항상 "고아 0건"이었다
B1   DeleteBodyPhoto가 열람 게이트를 재사용     형제 DeleteInbody: "삭제는 동의 철회 이후에 **더** 필요한 동작"
B12  라우터 404 = 리소스 404                   어드민 "404=미배포" 규약이 원리적으로 성립 불가 → B6 위험 지시
```

### 변경

#### 요청 큐 — 처리 완료 시 개인정보를 비운다 (A5)

```
POST /v1/join/approve                  승인 후 요청 문서의 name·phone을 비운다(JoinReject와 동형).
                                       남는 것: {uid, center_id, status:"approved", created_at}.
                                       응답(회원 레코드)·/v1/me의 join_request(status·created_at)는 무변경.
POST /v1/consult-requests/{id}/done    done 전이 시 note를 비운다. 행은 남는다(done→done 멱등 유지).
                                       응답·목록의 note 키는 omitempty라 사라진다.
```

승인 큐 이력에서 "누구였는지"는 **회원 레코드가 답한다** — 승인은 이름·번호를 회원 레코드로 *옮기는*
동작이지 복사하는 동작이 아니다. 요청 문서의 사본은 개명·정정을 따라가지 않아 남길수록 틀려지는 사본이고,
join_requests는 최상위+uid 키라 센터 스코프 파기 스윕이 구조적으로 못 닿는다(P53). 이로써 privacy.html의
*"처리 완료 또는 탈퇴 시 지체 없이 파기"*가 두 반쪽 모두 참이 된다(종전엔 탈퇴 절반만 참).

#### 직렬화 계약 — 읽기 쪽 바닥 (A3)

```
배열 필드는 항상 []              Member.flags · Pass.holds · Staff.offdays · **Payment.installments**(신설)
                                — 생성 경로뿐 아니라 **읽기 직전에도** nil→[] (이미 null로 굳은 문서를 위한 바닥)
POST /v1/payments               installments 생략(일시불) → 저장·응답 모두 []
GET  /v1/payments               프로덕션의 null 문서도 []로 나간다
GET  /v1/members                flags null 문서 → 응답 [] (owner 목록 · member self 모두)
PUT  /v1/members/{id}           머지 저장 시 flags를 []로 **치유**(종전 slices.Clone(nil)==nil이라 PUT으로도 안 나았다)
GET  /v1/passes · members[].passes · POST /v1/passes/{id}/refund
                                holds null 문서 → 응답 []
Member.body_poses               **제외** — nil이 "센터 기본 사용"이라는 의미를 가진다(v2.10)
```

⚠ holds의 단건 응답 결함은 기본 `go test`(Memory)로는 **절대 안 죽는다** — Memory의 UpdatePassWithLedger*가
롤백 안전을 위해 슬라이스를 새로 만들어 nil이 될 수 없고, Firestore는 fromDoc(JSON)이라 null이 nil로 온다.
테스트는 Firestore 모양의 래퍼 스토어로 고정했다(P49·P53이 적은 "에뮬레이터 전용" 자리와 같은 계열).

#### 파기 경계 미구성 — 훑기는 503, 탈퇴는 no-op (A4)

```
POST /v1/body-photos/reconcile   STORAGE_BUCKET 미설정 · 버킷 접근 실패 · 로컬(FIREBASE_PROJECT 미설정)이면
                                 503 {error, code:"media_not_configured"}   (종전: 200 "고아 0건")
DELETE /v1/me · DELETE /v1/body-photos/{id}(회원) · 유예 스윕 · POST /v1/body-photos/purge
                                 무변경 — 미구성이면 파일 파기는 no-op(메타·계정·인덱스는 파기), 기동 로그 경고
```

두 동사를 **일부러 다르게** 다룬다. 훑기는 조회라 크게 실패해도 잃는 것이 없고, 조용히 성공하면 "버킷이
깨끗하다"는 거짓 보고가 된다 — 그 도구는 바로 이 no-op이 남긴 고아 50개(v2.15) 때문에 만들어졌다. 탈퇴는
§36 삭제 요구권이라 배포 설정 하나에 막히면 그쪽이 더 큰 거짓이다(P51 결정 유지: 파기 실패가 탈퇴를 막으면
안 된다). `code:"media_not_configured"`는 어드민이 code 없는 503을 전달 경로 장애로 읽어 재시도를 권하기
때문이다 — 재시도로 안 낫는 설정 문제임을 기계가 읽는다. 문구는 어느 값을 설정해야 하는지를 말한다.

#### 체형사진 — 철회 후 파기 경로 완결 (B1)

```
DELETE /v1/body-photos/{id}          동의(sensitive)를 보지 않는다(DeleteInbody와 통일). 스코프는 그대로
                                     (owner=전체 · trainer=담당 · member=본인). 종전: 철회 후 스태프 403.
GET  /v1/body-photos?member=         동의 **무효** + 스태프 + 스코프 안 → 200 **BodyPhotoMeta[]**  (종전 403)
                                       BodyPhotoMeta {id, member_id, pose, direction, date, deleted_at?}
                                       — storage_path·blurred **없음**(열람은 여전히 잠긴다). 키 집합을 테스트로 고정.
                                     동의 유효 · 회원 본인 → BodyPhoto[] 무변경.  스코프 밖 → 403 무변경.
GET  /v1/body-photos?member=&include_deleted=true
                                     **스태프 전용**: 소프트 삭제분(deleted_at 포함)까지 — v2.14 "30일 안에 복원"이
                                     새로고침 뒤에도 참이 된다(종전엔 어드민이 세션 휴지통만 둘 수 있었다).
                                     **회원은 403** — 조용히 무시하지 않는다. 회원 화면에서 삭제분은 "즉시
                                     사라진다"(v2.13)가 계약이라 이 파라미터를 보내는 회원 앱은 버그이고,
                                     버그는 크게 실패해야 보인다. 잠긴 목록(BodyPhotoMeta)에도 적용된다.
POST /v1/body-photos/{id}/restore    무변경 — 복원은 동의 게이트를 지난다(되살리는 동작은 열람 쪽이다).
```

같은 엔드포인트의 **원소 모양이 동의 상태로 갈린다**. 배열 자체는 유지한다(회원 앱이 배열을 읽는다).
어드민은 회원의 consent로 어느 쪽인지 이미 알고, `storage_path` 키의 유무가 두 번째 판별자다. 이로써
방침의 *"철회 후 데스크에 삭제 요청"*이 서버·어드민 양쪽에서 실재한다 — 목록이 403이면 스태프는 지울 id를
얻을 길이 없어 B1은 "서버만 열린" 절반 수리였다.

#### 라우터 404 구분 (B12)

```
없는 경로(라우터)     404 {error:"찾을 수 없음", code:"route_not_found"}
없는 리소스(id)       404 {error:"찾을 수 없음"}                          ← 무변경, code 없음
405                  무변경(code 없음)
```

어드민의 "404 = 이 배포에 아직 없는 엔드포인트" 판정은 **`code === "route_not_found"`로만** 한다. code가 없는
404는 전부 "그 id가 없다"다 — 사람이 읽는 `error` 문구는 판별자가 아니다(바뀌어도 되는 값이다).
**`route_not_found`·`media_not_configured` 문자열은 어드민 상수와 글자 단위로 맞춰져 있으므로 바꾸지 말 것.**

### 검증

```
뮤테이션        24건 → 23 KILLED · 1 제거(등가: PayInstallment의 읽기 정규화 — 인덱스 가드가 len(nil)==0으로
               먼저 400을 내 응답에 nil이 실릴 수 없다. 죽일 수 없는 코드를 두지 않고 지웠다)
               Memory 전용 초록 1건(holds 단건 응답)은 Firestore 모양 래퍼 스토어로 죽였다
와이어          라우터를 태워 "installments":null · "flags":null · "holds":null 바이트 부재, 404 code 유무,
               503 code, BodyPhotoMeta 키 집합(정확히 6키), include_deleted 회원 403을 고정
동의 철회       실제 경로(PUT consent.sensitive=false)로 revoked_at을 찍고 검증 — 스토어 직접 수정은
               SensitiveConsentValid의 판정 규칙을 비켜간다
스토어          인터페이스·구현 무변경 → 에뮬레이터 신규 케이스 없음
회귀            go build · go vet · go test ./... · go test -race ./... 전건 그린
```

### 남은 갭

```
① 과거 승인분의 join_requests            이번 수리는 앞으로의 승인만 비운다. 이미 approved인 문서의 name·phone은
                                        1회성 마이그레이션(status=approved 문서의 두 칸 비움)이 필요하다 — 람 결정.
② 업로드 503(ErrUploadUnavailable)의 code  같은 계열(STORAGE_BUCKET)이라 media_not_configured를 실어도 되지만
                                        어드민이 요청하지 않아 이번엔 안 붙였다(붙이면 추가적 변경).
③ 405의 code                             필요해지면 method_not_allowed — 지금 읽는 화면이 없다.
④ 잠긴 목록의 판별자                       storage_path 키 유무 + consent. 명시 플래그(예: 응답 헤더)가 필요해지면
                                        그때 연다 — 배열을 객체로 바꾸는 것은 회원 앱을 깨뜨리므로 금지.
```

## v2.29 공개 센터 신원 — 회원 앱이 어드민 "센터 신원"을 실제로 읽게 (2026-09-05, P56 L10, 이 섹션도 계약의 일부)

### 왜

v2.27이 `PUT /v1/center {center{name,phone,address}}`를 열고 어드민에 "센터 신원" 폼을 붙였다.
폼의 효과 안내는 **"회원 앱의 센터 찾기 목록에 이 이름으로 뜹니다"**였는데 — 그런 목록은 없다
(P55는 센터 선택 대신 대기실을 택했다), 그리고 앱은 그 3칸을 **어디서도 읽지 않았다**:

```
상호       앱 로컬 상수 '라이즈 컨디셔닝 센터 (강남)' — P48 목업 값, 지점 "강남"은 확인된 사실이 아님.
           홈 헤더(이름 미해석 폴백)·다음 예약 카드·마이 탭·대기실 카드 5곳에 그대로 인쇄.
전화·주소  대기실 연락 카드가 GET /v1/public/business(사업자 정보)를 읽음 — 어드민이 "센터 신원"에
           저장한 센터 전화는 앱 어디에도 나오지 않았다.
```

P56 분류로는 **거짓 약속**(어드민 문안) + **와이어 불일치**(저장 경로와 읽기 경로가 다른 문서) +
**선언만 있고 구현 없음**(CenterResponse.Name의 "클라이언트는 폴백한다" 규약 — 읽는 클라이언트가 없었다).
발견 경로: 2026-09-05 대기실 E2E(에뮬레이터, 미연결 테스트 번호)에서 카드가 "(강남)"을 찍는 것을 보고
출처를 좇았다.

### 무엇이 바뀌나

```
GET /v1/public/center          인증 불필요. /api/v1/public/center 에도 미러(P07).

  응답 200 { name, phone, address }              ← CenterIdentityView, PUT /v1/center {center}와 같은 키 집합
  헤더     Cache-Control: public, max-age=300     ← /v1/public/business와 같은 이유(무인증 경로 읽기 증폭 차단)

  미등록이어도 200 + 빈 3칸(404 아님) — 대기실이 "불러오지 못함"과 "등록 전"을 구분한다.
  키는 항상 셋 다 나간다(omitempty 아님) — 클라이언트가 키 부재와 빈 값을 구분하지 않게.
```

**폴백 규칙 — 서버 한 곳에서.**

```
phone    center.phone   비어 있으면 business.phone
address  center.address 비어 있으면 business.address
name     폴백 없음 — 빈 문자열 그대로. 사업자명(법인명)과 센터 상호는 다른 값이다(어드민이 두 칸을
         나눈 이유). 빈 상호는 클라이언트가 자기 임시 상수로 채운다(CenterResponse.Name 규약과 같다).
```

왜 서버에서 합치나: 앱·어드민이 각자 합치면 어느 화면은 센터 번호를, 어느 화면은 사업자 번호를
말하는 자기모순이 생긴다. 왜 전화·주소만: 대표가 법정 고지 때문에 사업자 12칸을 먼저 채우고 센터
3칸은 비워 두는 순서가 자연스럽고, 그때 대기실의 "센터에 전화하기"가 죽어 있으면 안 된다. 두 번호
모두 이미 공개 값이라 새로 노출되는 것은 없다.

**의도적으로 내보내지 않는 것**: `domain.Center`의 `id`·`status`·`created_at`, policy 전체, business
전체, facility. 키 집합은 `service_public_center_test.go`가 3칸으로 잠근다 — 늘리는 일이 테스트에
걸려 의식적인 결정이 되게.

### 클라이언트

```
앱     centerContactProvider → GET /v1/public/center (종전 /v1/public/business). CenterContact.name 추가,
       displayName = name ∥ AppConfig.centerFullName. 동기 centerDisplayNameProvider(String)를 홈 헤더·
       다음 예약 카드·마이 탭·대기실 매칭/연락 카드 5곳이 읽는다 — 로딩 중엔 임시 상수, 서버 값이 오면 교체.
       AppConfig.centerFullName = '라이즈 컨디셔닝 센터' — 지점명 "(강남)" 제거(검증 못 한 사실을 회원에게
       사실처럼 찍지 않는다), 어드민 CENTER_NAME_FALLBACK과 같은 문자열로 정렬(등록 전 두 화면이 다른
       이름을 말하지 않게).
어드민 CENTER_IDENTITY_EFFECT_NOTE — "센터 찾기 목록" 문안 삭제. 앱이 실제로 읽는 자리(센터 연결 화면·홈·
       마이 탭, 연락 카드의 전화·주소, 사업자 정보 폴백)만 적는다. 상호 미등록 경고도 같은 방향.
앱     401 인터셉터 — `/v1/public/*`(·`/api/v1/public/*`)에서 온 401은 세션을 비우지 않는다. 공개 경로는 신원을
       보지 않으므로 그 401은 신원 상실이 아니라 구서버(라우트 부재 → auth 미들웨어 401) 또는 헤더 첨부 실패다.
       클라이언트가 "무인증 표면" 목록을 이 규칙에 쓰므로, 공개 경로를 더하면 `isPublicApiPath`도 함께 본다.
```

### 무인증 표면 (이 목록이 계약이다)

```
GET /v1/public/business   v2.13   사업자 12칸 + complete
GET /v1/public/center     v2.29   센터 상호·전화·주소 3칸
(+ /api/v1/ 미러 둘, /healthz·/health)
```

그 밖의 모든 `/v1/*`은 auth.Middleware 뒤다 — `TestPublicBusinessNeedsNoAuth`·`TestPublicCenterNeedsNoAuth`가
`/v1/center`·`/v1/me`·`/v1/members`의 401을 함께 고정한다.

소비자 메모(2026-09-06, P63 — 계약 변경 아님): 앱 1.0(5)+는 `DELETE /v1/me` 응답의 `purged.join_requests`(미연결 완료 안내의
"보낸 가입 요청" 유무)와 `member_id`(빈 값 = 미연결 경로 → 완료 문구 선택)를 읽는다. v2.27이 정한 두 칸을 서버가 정리할 때 이 의존을 본다.

## v2.30 접속기록 관측 규약 (2026-09-06, P61, 이 섹션도 계약의 일부)

### 와이어 변경 없음

요청·응답·상태코드·헤더 **무변경**. 앱(Flutter)·어드민(React)이 보내거나 받는 것은 하나도 바뀌지 않고,
클라이언트가 추가로 보낼 식별자도 없다(정보주체 id는 이미 path·query·body에 있고 서버가 그것을 읽는다).
이 절은 v1.2 §"기타 확정"의 `500 바디는 "서버 오류가 발생했습니다"(원문은 서버 로그)` 문장과 같은 층위 — **서버가 요청마다 무엇을 남기는가**를 계약에 적는다.
어디에 얼마나 쌓이고 어떻게 점검하는가(버킷·sink·잠금·주기)는 `backend/README.md` 접속기록 절.

### 왜

privacy.html이 "개인정보처리시스템 접속기록 2년 이상 보관·위·변조 방지·점검"을 약속하는데(P56 L9)
서버에는 chi 평문 요청 로그뿐이었다 — uid·정보주체·수행업무가 없어 「개인정보의 안전성 확보조치 기준」
(고시 제2026-9호, 2026.7.1. 일부개정·같은 날 시행(law.go.kr 헤더 [시행 2026. 7. 1.] 확인)) §2의 '접속기록' 정의를 만족하지 못했고, 30일 뒤 사라졌다. 민감정보(체형사진·체성분)를
처리하는 시스템이라 §8①2호 → 2년.

### access 라인 스키마 — stdout JSON 한 줄, 요청당 1건

```
{"log_type":"access",                  ← sink 필터 키(jsonPayload.log_type="access"). 고정.
 "severity":"INFO",                    ← 2xx/3xx/4xx INFO · 401/403/429 WARNING · 5xx ERROR (항상 명시)
 "time":"2026-09-06T03:09:38.681Z",    ← RFC3339Nano UTC → LogEntry.timestamp
 "message":"access owner1 PUT /v1/members/{id} 200",
 "request_id":"…",                     ← middleware.RequestID (auth reject 로그·recoverJSON 로그와 같은 값)
 "uid":"owner1","role":"owner","center_id":"rise",          ← 식별자(취급자). 401이면 세 칸 모두 ""
 "method":"PUT","route":"/v1/members/{id}","path":"/v1/members/m1",   ← 수행업무. route는 chi 패턴,
                                        미해석(401·404)이면 "/v1/*" 또는 "/api/v1/*" — path를 항상 병기
 "status":200,"latency_ms":3,"bytes":412,
                                        ← status: 핸들러가 헤더를 안 썼으면(0) 컨텍스트 DeadlineExceeded → 504
                                          (chi Timeout이 accessLog 뒤에 504를 쓴다), 그 외 → 500
 "aborted":true,                       ← 패닉으로 끊긴 요청에만. 헤더가 이미 나갔으면 status는 나간 값
                                          (예: 200)을 유지하고 aborted:true — recoverJSON은 그 경우 연결을
                                          끊지 코드를 바꾸지 않는다. 패닉이면 status 무관 severity ERROR
 "remote_ip":"1.2.3.4",                ← RealIP 결과: True-Client-IP → X-Real-IP → XFF **첫** 값 순 —
                                          셋 다 클라이언트가 지정할 수 있어 **위조 가능**. 포트 없음
 "x_forwarded_for":"1.2.3.4, 10.0.0.1",   ← 원 헤더 전체(있을 때만, 512자 클립·초과 시 "…") — 교차 확인용
 "xff_last":"10.0.0.1",                ← XFF **마지막** 값(있을 때만) = 프록시(GFE)가 덧붙인 값 → **신뢰 값**.
                                          Hosting 리라이트 경유는 끝값이 Hosting 프록시라 끝에서 둘째가 클라이언트
 "user_agent":"…",                     ← 있을 때만, 512자 클립·초과 시 "…"
 "subject":{"member_id":"m1"},         ← 처리한 정보주체(있을 때만). member_id | resource_id | staff_uid
 "logging.googleapis.com/trace":"projects/rize-218c1/traces/<TRACE_ID>"   ← GCP_PROJECT 있고
                                        X-Cloud-Trace-Context 있을 때만. Cloud Run 요청 로그와 상관
}
```

`/api/v1/*` 미러(P07)도 완전 패턴(`/api/v1/members/{id}`)으로 남는다 — 미러가 기록 우회 뒷문이 아니다.

### 절대 싣지 않는 것

요청·응답 **본문**, `Authorization`·`X-Dev-Uid`·`X-Dev-Role` 값, **쿠키**, **쿼리 문자열 원문**(`q=` 검색어에
이름·전화번호가 들어온다 — 화이트리스트 `member` 값만 읽어 `subject.member_id`로 옮긴다), `Principal.Phone`,
이름. `accesslog_test.go`(`TestAccessLogNeverContainsSecretsOrBody`)가 문자열 부재로 못 박는다. 이 목록을
늘리는 변경은 계약 개정이다.

### 기록 범위 · 거부 기록 규칙

```
스태프(owner·trainer·superadmin)   모든 요청 — 성공·실패·404·패닉(500)·타임아웃(504) 포함
회원(member)                        401·403(·429 v2.38) 외에는 기록하지 않는다(400·404·5xx 포함) (§8① "정보주체는 제외한다" + 최소수집)
역할 무관                            401(토큰 없음/무효 — auth 앞에서 기록) · 403(스코프 위반) · 429(빈도 제한, v2.38) 은 항상 기록
클로저 밖                            /healthz · /health · /api/health · /v1/public/* (+/api 미러) 는 기록하지 않는다
```

거부 기록이 가능한 이유는 미들웨어 순서다: `accessLog`가 `auth.Middleware`보다 **앞**에 서고 auth가
Principal을 포인터 엔트리에 역주입한다(auth.go). 그 두 줄을 지우면 모든 스태프 요청이 미인증으로
기록된다 — `TestAccessLogRecordsStaffRequest`가 잡는다. 회원 404 제외는 `TestAccessLogOmitsMemberSelfAccess`,
504·aborted 분기는 `TestAccessLogTimeoutIs504`·`TestAccessLogPanicAfterHeaderKeepsStatus`, remote_ip 위조·xff_last는
`TestAccessLogRemoteIPSpoofableXFFLastTrusted`, 512자 클립은 `TestAccessLogClipsLongHeaders`가 고정한다.

### 핸들러 규약 — `setAccessSubject(ctx, memberID)`

정보주체 식별자가 **본문에만** 있는 핸들러는 성공 응답을 쓰기 전에 1줄로 알려준다(미들웨어는 본문을
읽지 않는다 — '본문 기록 금지' 원칙과 `decodeJSON`의 바디 소비가 충돌한다). 생성 동사는 응답 객체의 id를
쓴다(생성 후가 정확). 현재 12곳: `CreateBooking` · `Checkin` · `CreatePass` · `CreatePayment` ·
`CreateContract` · `CreateBodyPhoto` · `CreateInbody` · `CreateWorkoutLog` · `CreateHomework`(개인 배정
1명일 때만 — 다수 배정은 subject 없음) · `CreateHwCheck` · `JoinApprove`(승인으로 생긴 회원 id) ·
`CreateMember`(생성된 id). 훅이 없어도 라인은 남는다(route·path로 수행업무는 확정) — 누락은 "덜 정확"일
뿐 조용한 실패가 아니다. **새 POST 핸들러가 본문의 회원 id로 개인정보를 처리하면 이 훅을 단다.**

### chi `middleware.Logger` 제거

같은 배포에서 제거했다. 컨테이너 stdout의 평문 요청 로그(`?q=` 포함 RequestURI)가 사라지고 access 라인이
대신한다. **Cloud Run 요청 로그(30일)에는 쿼리 문자열이 여전히 남는다** — 이 규약이 보장하는 것은
"접속기록(2년)에 싣지 않는다"까지다.

---

## v2.31 퇴사 시 프로필 사진 파기 — 퇴사는 스태프 사진의 목적 소멸이다 (2026-09-06, P62, P56 B13, 이 섹션도 계약의 일부)

### 왜

스태프 프로필 사진의 유일한 목적은 **회원 앱 공개**다(privacy.html 수집 항목 표 — "센터가 등록(회원 앱에
공개됩니다)"). 퇴사(`deactivate`)는 그 목적이 소멸하는 시점이고, v2.0이 하드 삭제를 하지 않는 근거로 든
근로자 명부 3년(근기법 §42·시행령 §20 — 성명·성별·생년월일·주소·이력·종사 업무·고용/퇴직일)에 사진은
없으며, 정산 5년은 Payout 요율과 by_trainer 집계의 근거일 뿐 사진과 무관하다. 즉 **보존 근거가 없는
개인정보 잔류**다(개인정보 보호법 §21① — 목적 달성 시 지체 없이 파기). 회원 응답 마스킹(v2.0 — inactive
프로필을 빈 객체로)은 화면에서 감출 뿐 파일은 버킷에 무기한 남았다. v2.25는 "퇴사 시 지우지 않는다"를
명시했는데(복직 시 깨진 이미지 우려), `photo_url`을 함께 비우면 그 우려는 생기지 않는다.

### 무엇이 바뀌나 — `POST /v1/staff/{uid}/deactivate`

```
① Firebase 계정 잠금(DisableUser)              — 그대로. 실패하면 아무것도 바꾸지 않은 채 에러
② UserIndex 강등(member)                       — 그대로. 즉시 차단의 본체
③ [신설] 프로필 사진 파기
     prevPath := ownedStaffPhotoPath(uid, photo_url)  // firebasestorage 호스트 + staff/photos/{uid}- 명의
                                                      // + (STORAGE_BUCKET 설정 시) 같은 버킷일 때만
     prevPath != "" ∧ purger 구성됨 → MediaPurger.DeleteObjects([prevPath])
         실패 → 500 (status는 active로 남고 photo_url도 유지 — 재시도 자격 보존)
         성공 → photo_url = ""
     prevPath != "" ∧ purger 미구성 → 파기 건너뜀 + 로그 "staff photo purge skipped uid=… path=…",
                                      photo_url **유지**, 퇴사는 진행(아래 "미구성 purger" 절)
     prevPath == "" (사진 없음·외부 URL·다른 uid 명의·다른 버킷) → DeleteObjects를 부르지 않고 photo_url 무변경
④ Staff 레코드 저장(status=inactive · left_at · photo_url) — 한 번의 쓰기
```

**명의 결속(검증 반영).** 초판은 접두 `staff/photos/`만 봤다 — A의 photo_url이 재직자 B의 파일을
가리키면(대표가 URL을 복사해 붙여 넣으면 된다, PUT은 http(s)면 무엇이든 받는다) A의 퇴사·[사진 지우기]가
**B의 얼굴을 지우고** B의 photo_url은 죽은 링크로 남았다. 업로드 명명 규칙 `staff/photos/{uid}-{난수}.{ext}`의
uid가 곧 소유권이므로 판정에 넣는다(`{uid}-` 하이픈까지 비교 — "t1"이 "t10-…"에 걸리지 않게). 다른 버킷의
URL도 제외한다 — DeleteObjects는 서버가 묶인 버킷 안의 경로만 지우므로 동명 파일을 지우게 된다. 남의 uid
명의·다른 버킷 URL은 **외부 URL과 완전히 같게** 다룬다(파일·포인터 무변경).

**순서의 근거.** 삭제는 불가역이므로 ①② **뒤**다 — ①②가 실패하면 퇴사 자체가 실패인데 사진만 먼저
사라지면 "재직 중인데 사진이 없어진" 부작용이 남는다. ④ **앞**인 이유: 저장 뒤에 지우면 삭제 실패 시
포인터가 이미 비어 파일이 발견 경로 없는 고아가 된다(P22). 앞에 두면 ④가 실패했을 때 "파일은 없는데
URL은 남은" 창이 생기지만, status가 아직 active라 재시도가 `이미 퇴사` 400에 막히지 않고, 재시도의
삭제는 `ErrObjectNotExist`를 성공으로 세므로(v2.11 `firebaseMediaPurger`) 그때 URL이 비워진다 —
**멱등으로 수렴**한다. 그 사이 어드민·앱 아바타는 onError/errorBuilder로 이니셜 폴백한다.

**실패는 전파한다(best-effort가 아니다).** ②가 끝난 시점이라 500을 내도 사람은 이미 잠겨 있어 보안상
잃는 것이 없고(기존 ④ SaveStaff 실패 전파와 같은 취급), status가 active로 남아 재시도가 수렴하며,
어드민이 실패를 본다. 조용히 성공시키면 privacy.html의 "퇴사 처리되면 사진 파일도 함께 삭제됩니다"가
**재시도 동사 없는 거짓 약속**이 된다(스태프판 reconcile이 없다). 회원탈퇴 파기(v2.11)와 같은 정책.

**불변식.** `photo_url == ""` ⇔ **이 uid 명의의 우리 파일**(`staff/photos/{uid}-…`)이 없다(purger가
구성된 환경에서). 외부 URL(v1.6 수기 입력)·다른 uid 명의·다른 버킷은 파일도 포인터도 건드리지 않는다 —
우리가 파기할 수 없는(또는 우리 것이 아닌) 것을 "삭제됨"처럼 보이게 하지 않고, 다른 프로필 칸
(직함·경력·자격·소개)은 보존되는데 외부 링크만 지울 근거도 없다. 회원에게는 어차피 마스킹된다.

### `PUT /v1/staff/{uid}/profile`도 같은 파기 판정을 한다

어드민 [사진 지우기]는 빈 `photo_url`로 프로필 PUT을 보내는데, 종전엔 포인터만 비워 업로드 파일이
고아가 됐다(외부 URL로 덮는 PUT도 동일). 이제 `prev := ownedStaffPhotoPath(uid, 기존)`, `next :=
ownedStaffPhotoPath(uid, 새 값)`에서:

```
next != "" ∧ next != prev   → 409 "사진이 그 사이 바뀌었어요 — 새로고침 후 다시 저장해주세요"
                              (파일·프로필 무변경)
prev != "" ∧ prev != next   → 저장 전에 이전 파일 삭제(실패 → 500, 프로필 무변경)
                              purger 미구성 → 삭제 건너뜀 + 로그, photo_url은 기존 값 **유지**, 나머지 칸 저장
그 외(prev == next · 둘 다 "")  → 삭제 없음
```

**409 가드(검증 반영 — 통 교체 시맨틱의 유일한 예외, v1.6 절에 표기).** 프로필 PUT은 **우리 파일 포인터를
새로 만들 수 없다** — 그 포인터는 업로드 엔드포인트만 박는다. 저장된 값과 다른 우리 파일 URL이 오면 그것은
stale이다(이 화면이 열린 뒤 다른 창에서 사진이 교체·삭제됐다): 초판은 이를 "교체"로 보고 **현재 파일을
지우고 이미 없는 옛 파일의 URL을 박아** 죽은 링크를 만들었다. 퇴사가 파기한 URL을 되돌려 보내는 것도 같은
409다(`prev == ""`, `next` = 우리 파일 — 파기의 역행 차단). 어드민은 서버 `error` 문구를 그대로 그리고(api.ts
`req` — JSON 본문의 error가 상태코드 폴백을 덮는다) 그 문구가 remedy(새로고침)를 말하므로 어드민 코드
변경은 없다.

통 교체라 어드민(대표·본인 트레이너 모두)은 같은 URL을 그대로 되돌려 보내므로 `prev == next` → 삭제 없음.
외부 URL·다른 uid 명의·다른 버킷 URL을 지우거나 덮는 PUT은 `prev == ""`라 삭제 호출이 없다.

**실패 창.** 삭제 성공 뒤 SaveStaff가 실패하면 파일은 없고 URL은 남는다(재직자 → 앱·어드민 아바타 이니셜
폴백). **같은 PUT을 재시도**하면 수렴한다(재시도의 삭제는 `ErrObjectNotExist`를 성공으로 세고 그 뒤 저장이
URL을 비운다). 같은 URL을 되돌려 보내는 일반 저장은 `prev == next`라 이 창을 닫지 않는다 —
`TestUpdateStaffProfileSaveFailureAfterDeleteConvergesOnRetry`(hookStore SaveStaff n==2)가 고정한다.

### `POST /v1/staff/{uid}/photo` — 교체(⑤)도 전파 정책이다 (검증 반영, v2.25 개정)

```
① 검증 → ② 스태프 조회(퇴사자 400) → ③ 새 파일 업로드
⑤ prev := ownedStaffPhotoPath(uid, 기존 photo_url); prev != "" ∧ prev != 새 경로 → 삭제
     실패 → 방금 올린 새 파일 best-effort 되지우기 → 에러 전파(프로필 무변경, 옛 URL·옛 파일 그대로)
     purger 미구성 → 삭제 건너뜀 + 로그(옛 파일 잔존, 새 URL은 저장됨 — 그 환경에선 업로더도 미구성이라
                    실제로는 503에서 끝난다)
④ 프로필 저장(photo_url = 새 URL)
     실패 → 방금 올린 새 파일 best-effort 되지우기 → 에러 전파
```

v2.25는 ⑤를 ④ 뒤 best-effort로 뒀다("성공한 업로드를 실패로 보이게 하지 않기 위해"). 그 정책은 삭제 실패
시 옛 파일을 **발견 경로 없는 고아**로 만들고, privacy.html "교체하거나 지우면 이전 파일은 삭제되며"를
실패한 삭제 뒤에 숨기는 고지로 만들었다 — 이제 삭제가 실패하면 **교체 자체가 실패**하고 대표는 다시 올린다.
그래야 그 문장이 참이다(퇴사 ③·프로필 PUT과 같은 정책, 같은 헬퍼 `purgeStaffPhoto`).

**실패 창.** ⑤ 성공 뒤 ④가 실패하면 "새 파일 고아(되지우기까지 실패한 경우) + 옛 URL 죽은 링크"다(옛
파일은 이미 없다). 재시도(업로드 다시 → prev 삭제 = `ErrObjectNotExist` 성공 → 저장)로 수렴한다.

### `POST /v1/staff/{uid}/photo` — 퇴사자 400

`GetStaff` 뒤 `!IsActive()`면 **400** `"퇴사 처리된 스태프의 사진은 올릴 수 없어요 — 재입사 처리 후
올려주세요"`. 업로드 전이라 파일이 생기지 않는다. 퇴사가 파기한 것을 실수 한 번으로 되살리는 역행 경로를
막는다. 재입사(reactivate·같은 이메일 재초대) 뒤엔 자연히 열린다. 프로필 PUT은 우리 파일을 만들지
않으므로 퇴사자에게도 그대로 열려 있다(외부 URL 입력 가능 — 범위 밖).

**동시성 한계**: 트랜잭션이 없어 deactivate ③~④ 사이에 들어온 업로드는 가드를 통과할 수 있고, 그 경우
deactivate의 stale 저장이 새 URL을 덮어 새 파일이 고아가 된다. 기존 last-writer-wins 경로들과 같은
급이며, 이 절은 그 창이 있음을 적어 둘 뿐 닫지 않는다.

### 복직·재고용

`reactivate`와 재초대(`POST /v1/staff` → rehire)는 코드 무변경 — 프로필은 보존하되 `photo_url`은 퇴사 때
이미 비어 있다(v2.0 "profile·offdays는 보존"에 photo_url 예외 표기). 복직은 이니셜 아바타로 시작하고
필요하면 대표가 다시 올린다. 어드민 재입사·초대·퇴사 모달이 이를 말한다.

### 미구성 purger의 창 (`STORAGE_BUCKET` 없음 · Storage 초기화 실패)

`unconfiguredPurger.DeleteObjects`는 no-op 성공이다(v2.28 — 파기 실패가 탈퇴를 막으면 안 된다). 초판은 그
성공을 믿고 `photo_url`을 비웠다 — **파일은 남고 포인터만 사라지는** 고아다(검증 이슈 5, 정정). 이제
`MediaPurger.Configured() bool`(신설 — unconfigured=false, firebase=true)을 보고 스태프 경로 세 자리(퇴사 ③·
프로필 PUT·교체 ⑤)는 미구성이면 **파기를 건너뛰고 `photo_url`을 유지**한다: 요청당 로그 `staff photo purge
skipped uid=… path=…` 한 줄, 퇴사·프로필 저장 자체는 진행(에러 아님 — 즉시 차단의 본체는 ①②). 남은
포인터가 버킷이 구성되는 날 파일을 좇을 유일한 발견 경로다. 회원탈퇴 경로는 종전대로(no-op 성공 — 메타도
함께 지워져 포인터가 남을 자리가 없다). 기동 경고 3분기 문구도 "파기를 건너뛰고 photo_url을 유지합니다"로
정정. `TestDeactivateWithUnconfiguredPurgerKeepsURL`·`TestUpdateStaffProfileWithUnconfiguredPurgerKeepsURL`이
고정한다.

### 기존 잔류분 정리 (코드로 소급되지 않는다)

이 배포 이전에 퇴사 처리된 스태프의 파일과, [사진 지우기]가 남긴 고아는 남아 있다. 측정은 람이 한다:
`gcloud storage ls gs://<STORAGE_BUCKET>/staff/photos/ | wc -l` vs Firestore `staff` 컬렉션에서
`profile.photo_url`이 `firebasestorage…/staff%2Fphotos`인 문서 수(active/inactive 별). 차이 = 고아(교체
삭제 실패분·지우기 잔류분) + inactive 문서가 가리키는 파일. 0이면 할 일 없음, 소수면 `gcloud storage rm` +
Firestore 콘솔에서 해당 inactive 문서 `profile.photo_url=""`(코드 0) — 또는 서버 배포 뒤 어드민 퇴사 행의
[사진 지우기] 후 저장(파일·포인터를 서버가 함께 지운다, 문서당 1클릭). 재발 방지 도구가 필요하면
`POST /v1/staff/photos/reconcile`(v2.28 reconcile의 스태프판 — `known` = active 스태프의 경로 집합)을
별도 P로. 또한 버킷의 `softDeletePolicy`(2024-03 이후 생성 버킷 기본 7일)가 켜져 있으면 "삭제" 뒤에도
최대 7일 복구 가능 상태로 잔존한다 — 확인: `gcloud storage buckets describe gs://<STORAGE_BUCKET>
--format='value(softDeletePolicy)'`.

### 클라이언트 · 법정문서 · 배포 순서

- 어드민(`Settings.tsx`): 퇴사 행에서 여는 ProfileModal은 `photoEditable=false`([사진 선택] 숨김 — 서버 400)
  + `clearable`([사진 지우기]만 노출 — 퇴사자 PUT은 서버가 허용한다, 검증 반영). 문장은 저장된 `photo_url`
  값으로 가른다: 빈 값이면 "퇴사 때 업로드했던 사진 파일은 삭제됐어요", 값이 남아 있으면(이 배포 이전 퇴사분·
  미구성 건너뜀·외부 주소) "이전 방식으로 남았거나 외부 주소인 사진이에요 — [사진 지우기] 후 저장하면
  파일도 삭제돼요". 명사는 서버 400과 같은 '스태프'. 퇴사·재입사·초대 모달 문안에 "사진 파일 삭제·재입사 시
  비복원"을 적는다. 앱은 **무변경** — 회원 응답은 이미 inactive 프로필을 마스킹하고 TrainerAvatar는 빈 값/
  실패 모두 이니셜 폴백.
- privacy.html: ① 수집 항목 표의 프로필 사진 행 "사진을 교체하거나 지우면 이전 파일은 삭제되며, 스태프가
  퇴사 처리되면 사진 파일도 함께 삭제됩니다"(교체 삭제가 실패하면 교체 자체가 실패하므로 참이다 — 위 ⑤ 절).
  ② **처리위탁 표의 Cloud Storage 행**(검증 반영): 위탁 항목이 "체형사진"뿐이었는데 스태프 프로필 사진도
  같은 버킷에 있다 → "체형사진, 스태프 프로필 사진".
- **배포 순서(검증 반영)**: ① 서버 배포 → ② 잔류 측정·정리(아래 절 — `gcloud storage rm` + inactive 문서
  `photo_url` 비움, 또는 어드민 퇴사 행의 [사진 지우기] 후 저장 — 이 경로는 서버가 파일까지 지운다) →
  ③ 어드민·privacy.html Hosting. 고지가 구현을 앞서면 거짓 약속 창이 생기고, 어드민의 "삭제됐어요" 문장은
  잔류분이 정리된 뒤에야 참이다.
- 범위 밖(후속): 스태프 프로필의 나머지 칸(직함·경력·자격·소개)도 목적이 회원 앱 공개뿐인데 퇴사 후 보존
  근거는 재고용 편의(v2.0)뿐이고, privacy.html 보유기간 표에 스태프 정보 행이 없다 — P56 후속.

## v2.32 멀티센터 가입 연결 — 번호가 센터를 정한다 (2026-09-06, P65, 이 섹션도 계약의 일부)

### 무엇이 고장나 있었나

`POST /v1/join/match`와 `POST /v1/join/confirm`이 **`Principal.CenterID`로** 회원을 찾았다.
그런데 앱을 처음 켠 사람은 `UserIndex`가 없어 인증 미들웨어가 **`DEFAULT_CENTER_ID`를 꽂아
준다**(`auth.enrich`). 즉 2호점 데스크가 회원을 등록해도 그 회원의 앱은 **1호점에서만** 자기를
찾았고, 영원히 "아직 연결된 센터가 없어요"에 갇혔다. 관리 평면(v2.16)으로 센터를 만들 수 있게
된 뒤에도 **신규 센터의 회원 연결이 통째로 불가능**했다는 뜻이다.

### 규약

두 endpoint는 `Principal.CenterID`를 **쓰지 않는다**. **검증된 전화번호**(`joinPhone` — 운영에서는
Firebase 토큰의 `phone_number`만)로 **전 센터를 훑어** 회원을 찾고, 그 회원이 있는 센터가 곧
그 사람의 센터다. 회원은 센터를 고르지 않는다(설계04 §4: PT는 데스크 상담 → 등록 → 앱 연결
순서라 회원이 센터를 고르는 순간이 현실에 없다).

```
조회 대상 센터   DEFAULT_CENTER_ID ∪ GET /v1/admin/centers 목록. 정렬·중복 제거.
                 **기본 센터를 항상 포함한다** — ListCenters는 상호(center.name)가 등록된
                 문서만 돌려주는데 1호 고객이 그 상태라(2026-09-06 실측 name:"")
                 목록만 믿으면 기존 회원 전원의 연결이 끊긴다.
살아 있는 1건    그 (센터, 회원)으로 매칭·연결.
살아 있는 2건+   409 conflict "여러 센터에 등록된 번호예요 — 다니시는 센터 데스크에 문의해주세요".
                 **고르지 않는다**: UserIndex가 uid당 센터 1건이라(memberships[]는 Phase D)
                 한쪽을 고르면 그 선택이 굳고 회원은 다니지 않는 센터의 회원권을 본다.
살아 있는 0건 +  탈퇴 회원을 돌려준다(센터 ID 오름차순 첫 건) — 호출부의
탈퇴 1건+        "탈퇴한 회원이에요" 안내를 살리기 위해서다.
아무것도 없음    match → 200 {needs_confirm:false} · confirm → **400**(404 아님).
```

### 응답 변경 — `POST /v1/join/match`

```
center   객체(선택) — 매칭된 **그 회원의 센터** 신원 {name, phone, address}.
         GET /v1/center·PUT /v1/center의 center 절과 같은 모양(CenterIdentityView).
         미매칭이거나 **상호가 미등록이면 필드 자체를 생략**한다(빈 문자열 세 칸을 보내면
         클라이언트가 "센터를 받았다"고 판단해 빈 이름을 그린다).
```

추가 필드이므로 기존 클라이언트는 무시하고 그대로 동작한다. 앱 대기실은 아직 센터 상호를
무인증 `GET /v1/public/center`(기본 센터 고정)에서 읽으므로 **2호점 회원에게 1호점 상호를
보여준다** — 앱이 이 `center`를 읽도록 바꾸는 것이 남은 일이다(work_log/P65 후속).

### `POST /v1/join/confirm` 방어선 순서 변경

종전: 클라이언트의 `member_id`로 레코드를 열고 → 번호를 대조.
현행: **번호로 서버가 레코드를 고르고** → 클라이언트의 `member_id`가 그것과 같은지 대조
(다르면 400 "회원 정보가 일치하지 않아요"). 클라이언트가 센터도 레코드도 고르지 못한다.

400 문구는 이유를 특정하지 않는다(탈퇴·없는 member_id·번호 변경 셋 다 같은 문구) —
갈라 말하면 `mem_000001` 꼴의 ID를 넣어 보며 존재를 알아내는 오라클이 된다.

### 아직 열리지 않은 것

**미등록 번호의 가입 요청**(`POST /v1/join/request`)은 여전히 `Principal.CenterID`(= 기본 센터)
큐로 간다. 서버는 그 사람이 어느 센터를 원하는지 알 방법이 없다 — 설계04 §4의 권고대로
**센터별 초대 코드/QR**이 정답이고, 그건 앱 화면 변경을 동반한다(P65 후속).

## v2.33 센터 선택 가입 요청 · 법정 문서의 센터 차원 (2026-09-06, P66, 이 섹션도 계약의 일부)

v2.32가 **등록된 회원**의 센터를 번호로 풀었다면, 이 절은 **아직 등록되지 않은 사람**과
**법정 문서**의 센터를 푼다.

### 1) `GET /v1/join/centers` (신설, 인증 필요)

가입 요청을 보낼 수 있는 센터 목록.

```
응답  [{id, name, address?, phone?}]   — 센터 ID 오름차순, 중복 없음
집합  DEFAULT_CENTER_ID ∪ ListCenters  (v2.32의 joinCenterIDs와 같은 집합)
```

- **상호가 빈 센터도 뺀 목록이 아니다.** `ListCenters`는 상호 미등록 문서를 유령으로 거르는데
  1호 고객이 그 상태다 — 걸러 버리면 그 센터를 고를 방법이 사라져 기존 신규 회원의 가입
  요청 경로가 통째로 막힌다. `name: ""`로 실어 보내고 클라이언트가 자기 폴백 라벨을 쓴다.
- 정책·사업자 정보·회원 수는 **싣지 않는다**: 읽는 사람이 아직 어느 센터의 회원도 아니고,
  B2B2C에서 타 센터의 운영 수치는 남에게 보일 값이 아니다.
- **무인증으로 열지 않는다.** 센터 목록은 이 서비스를 쓰는 사업장의 목록이라 익명 크롤링
  표면으로 둘 값이 아니다. 전화 인증만 끝난 신규 사용자면 읽을 수 있다(역할 게이트 없음).

### 2) `POST /v1/join/request` — `center_id`를 **쓴다**

종전에는 바디의 `center_id`를 **무시**했다(P41). 그 봉인의 이유는 "임의 문자열을 신뢰하면
존재하지 않는 센터로 200이 나가고, 그 요청은 어느 대표의 큐에도 안 떠 신청자가 영원히
기다린다"였고, 열 조건 셋을 코드 주석이 미리 적어 뒀다: ① 신원 등록 센터 2곳 이상
② 회원이 읽을 수 있는 목록 ③ 실재 검증. ②·③이 이 절이고 ①은 런타임 조건이다.

```
center_id 생략   Principal.CenterID(신규 uid면 기본 센터) — 종전 동작, 구버전 앱 호환
center_id 지정   `GET /v1/join/centers` 집합에 있으면 그 센터, 없으면 **400**
정규화           소문자 · 앞뒤 공백 제거(문서 키가 되므로)
```

**신뢰 경계는 그대로다**: 클라이언트가 고를 수는 있어도 만들 수는 없다.

앱 규약: 목록이 **2곳 이상일 때만** 선택을 묻고, 그때는 고르지 않으면 요청을 보내지 않는다.
1곳 이하면 선택 UI를 그리지 않고 `center_id`를 비워 보낸다(선택지 없는 선택 화면은 방해다).

### 3) `GET /v1/public/business` · `GET /v1/public/center` — `?center=`

```
?center 없음     기본 센터 (배포된 구 링크 호환)
?center=<known>  그 센터
?center=<모름>   **404**
```

**모르는 센터에 기본 센터로 폴백하지 않는다.** 이 응답이 개인정보처리방침의 "개인정보처리자"와
계정 삭제 안내의 접수 창구로 인쇄된다 — 폴백하면 그 문서는 단순 오표기가 아니라 **거짓 고지**다.
404를 받으면 문서는 자기 자리표시자를 유지한다.

`PublicCenter`의 전화·주소 폴백도 **그 센터의** 사업자 정보에서 가져온다(종전 기본 센터 고정).

### 4) 법정 문서 HTML · 앱 링크

- 문서 5장 + 지원 페이지는 자기 URL의 `?center=`를 그대로 API에 넘기고, **같은 폴더 링크에
  그 값을 승계**시킨다(승계하지 않으면 이용약관 → 개인정보처리방침 한 번에 다른 센터의 고지가 된다).
- 앱 마이 탭의 약관·방침 4행은 **세션의 센터**를 붙여 연다(`LegalLinks.forCenter`).
  센터를 모르는 자리(대기실)에서는 붙이지 않는다 — 빈 파라미터는 404가 된다.

### 이미 센터별이던 것 (확인만)

**전자계약**은 처음부터 센터 스코프였다(`gatherContractVars(ctx, p.CenterID, …)` → 두 호출부
모두 `p.CenterID`). 계약서에 남의 사업자 정보가 인쇄될 경로는 없었다.


## v2.34 대기실의 센터 차원 · 승인의 번호 중복 가드 · 공개 센터의 수업 시간 (2026-09-08, P69, 이 섹션도 계약의 일부)

람이 두 가지를 가져왔다 — "앱에서 가입 요청을 보내면 어드민에서 신청한 회원을 볼 곳이 없다"와
대기실 실사 화면("친구가 생각한 대기실은 이런 모습이 아니다"). 어드민 쪽 답은 와이어 변경 없이
**큐를 회원 관리 탭 최상단으로** 옮기는 것이었고(어드민 갈래), 대기실 쪽을 조사하다 v2.33이 연
센터 선택을 v2.27의 대기 상태 조회가 **못 따라가고 있던 결함**을 찾았다. 이 절은 그 결함과,
같은 조사에서 드러난 승인 쪽 구멍 하나, 대기실 카드가 그릴 공개 값 하나를 닫는다.

### 왜 (이미 배포돼 있던 CRITICAL 1건)

```
① 회원이 앱에서 2호점(gangnam-2)을 골라 가입 요청     join_requests에 center_id=gangnam-2로 저장(v2.33)
② 앱이 GET /v1/me로 대기 상태를 묻는다                 latestJoinRequest가 **Principal.CenterID 큐**만 훑는다
③ 미연결 uid의 Principal.CenterID = 기본 센터 폴백      (v2.32가 match/confirm에서 이미 지적한 "진실 아님")
   → 1호점 큐에 그 사람의 요청이 없다 → join_request 키 생략
④ 앱은 "요청 없음"으로 읽고 재요청 버튼을 연다         → 같은 센터 409("이미 보낸 요청") 반복 — 막다른 길
```

같은 조회가 대기실 연락 카드도 틀리게 했다: `join_request`에 센터가 없으니 앱은 항상 기본 센터의
`GET /v1/public/center`를 찍었다 — 2호점 신청자가 1호점 전화번호를 본다.

### 와이어 변경

```
GET  /v1/me                → join_request{status, center_id, created_at}   center_id 추가(3칸), 조회는 uid 기준
POST /v1/join/request      → 409 본문 {error, code:"join_pending", center_id}   code·center_id 추가
POST /v1/join/approve      → 409 추가: 같은 번호의 살아 있는 회원이 이 센터에 있음
GET  /v1/public/center     → {name, phone, address, open_hour, close_hour}   수업 시간 2칸 추가(?center= 승계)
```

#### GET /v1/me — `join_request.center_id`

```jsonc
{ "uid":"u_abc", "role":"member", "center_id":"rise",
  "join_request": { "status":"pending", "center_id":"gangnam-2", "created_at":"2026-09-08T05:14:00Z" } }
```

- **조회는 uid 기준이다**(`Store.ListJoinRequestsByUID`, 센터 무관, 최신 먼저). 미연결 uid의
  Principal 센터는 폴백이라 진실이 아니다 — match/confirm이 번호로 전 센터를 훑는 것(v2.32)과
  같은 원칙이다. 비용도 준다: 센터 큐 전체(N, 상태 무관, 운영 기간에 비례해 자란다) 대신 그
  사람의 요청(k, 보통 1~2)만 읽는다. Firestore는 `uid ==` 단일 필드 쿼리라 복합 인덱스가 없다.
- v2.27의 "center_id는 싣지 않는다" 근거("v1 단일 센터라 진실이 아닌 선택지 암시")는 v2.33이
  선택을 열면서 소멸했다. 자기 uid 스코프의, 신청자가 방금 자기 손으로 고른 값이라
  (`GET /v1/join/centers`가 인증 사용자에게 이미 주는 집합의 원소) 새 오라클 표면은 없다.
  `id`·`name`·`phone`은 계속 싣지 않는다.
- 앱은 이 값으로 **그 센터의** `GET /v1/public/center?center=`를 그리고, 코치 미리보기는
  `me.center_id == join_request.center_id`일 때만 그린다(`GET /v1/staff`는 Principal 센터 고정이라
  다른 센터 코치는 어차피 못 받는다 — 타 센터 명부를 미연결에 열지 않는다).

#### POST /v1/join/request — 409 본문

```jsonc
{ "error":"이미 보낸 가입 요청이 있어요 — 센터에서 확인하면 연결돼요", "code":"join_pending", "center_id":"rise" }
```

- **판정 범위는 종전대로 그 센터**(같은 uid의 pending이 그 센터에 있을 때). 다른 센터에 pending이
  있어도 이 센터 요청은 받는다 — 잘못 고른 센터를 바로잡을 철회 동사가 없는 상태에서 전 센터로
  넓히면 사용자를 가둔다. 두 번째 요청의 승인은 `JoinApprove`의 "이미 연결된 uid" 가드(v2.27)가
  막으므로 데이터 손실은 없다(남는 pending은 대표가 거절로 정리). 철회 동사(`DELETE
  /v1/join/request`)와 전 센터 409는 **함께** 들어와야 하는 한 쌍이라 후속으로 남긴다.
- `code`는 판별자, `error`는 표시 문구다(라우터 404의 `route_not_found`와 같은 규약). 새 앱은
  이 409를 "서버 확답 pending"으로 승격시켜 대기 화면으로 돌아간다 — 종전엔 이 409가 일반
  실패로 떨어져 사용자가 같은 버튼을 반복해서 눌렀다. 구앱은 `error`만 읽으므로 무해.

#### POST /v1/join/approve — 같은 번호의 활성 회원이 있으면 409

```jsonc
{ "error": "같은 번호로 등록된 회원(김민지)이 이미 있어요 — 승인하면 회원이 2명이 돼요. 그 회원의 번호를 확인하고, 회원에게 앱에서 '번호 다시 인증하기'를 눌러 달라고 안내해주세요" }
```

- 승인은 `jr.Phone`으로 **새** 회원 레코드를 만든다(v1.7). 그 번호의 살아 있는 회원이 이 센터에
  이미 있다는 것은 "데스크가 이 사람을 (요청 이후에) 등록했다"는 뜻이고, 옳은 연결은 승인이
  아니라 회원의 재인증(`join/match → confirm`, 연결되면 A-5가 pending을 파기)이다. 승인하면 같은
  사람이 둘이 되고 회원권·예약은 데스크 레코드에, 앱 계정은 빈 레코드에 붙는다 — C-2의 변종.
- 대조는 `FindMemberByPhone`(정규화 비교 — 표기가 달라도 같은 번호). **탈퇴자는 걸리지 않는다**
  (탈퇴는 번호를 파기하고, 재가입은 승인이 유일한 길 — v2.27 `TestJoinApproveAllowsRejoinAfterWithdrawal`).
  가족이 한 번호를 쓰는 경우는 두 번째 사람을 다른 번호로 등록해야 한다 — 번호는 앱 매칭의 키라
  둘이 같으면 어느 쪽도 자동 연결이 안정적이지 않다.
- 어드민 큐는 같은 판정을 **화면에서 먼저** 보여준다(같은 번호·같은 이름 힌트, 승인 확인 창의
  경고) — 그러나 화면 경고는 방어선이 아니라 서버가 막는다.

#### GET /v1/public/center — `open_hour`·`close_hour`

```jsonc
{ "name":"라이즈 컨디셔닝", "phone":"02-…", "address":"…", "open_hour":9, "close_hour":21 }
```

- 의미는 `GET /v1/center`의 policy와 같다(첫 슬롯 시작·마지막 슬롯 시작, **양끝 포함**). 앱은
  "수업 09:00–22:00"처럼 **`close_hour+1`**로 끝 시각을 그린다(21:00 시작 수업이 마지막이다).
- 운영시간은 간판·지도에 공개되는 값이라 익명 노출에 거절 논거가 없다. 정책의 나머지(용량·
  위약금율·매출 목표)는 여전히 나가지 않는다(키 집합 잠금 테스트 5키). 응답 타입은 신원 3칸
  `CenterIdentityView`와 분리한 `PublicCenterView` — 3칸 타입은 `PUT /v1/center`의 `center` 덩어리와
  공용이라 거기에 시간을 섞으면 대표의 편집 폼이 시간 칸을 되돌려 보낸다.
- 값은 정책 실값이다 — 대표가 정한 적이 없으면 기본 9·21이 나가는데, 그 값이 곧 앱 예약 격자가
  실제로 여는 시간이므로 지어낸 사실이 아니다.

### 호환·배포

- 심사 중인 앱 1.0.0+8: 생성 파서가 지정 키만 읽어 `center_id`·`open_hour` 추가는 무시된다.
  409 본문 확장도 `error`만 읽으므로 무해. 새 앱 + 구서버: DTO 기본값(`''`·null)으로 종전 동작.
- 순서: **Cloud Run → Hosting(어드민) → 앱 빌드 +9**. 어드민 회원 탭 큐는 기존 `GET
  /v1/join/requests`로 동작하므로 서버와 독립이지만, 승인 409 문구는 서버 배포 후에야 나온다.

### 후속(이 절이 열지 않은 것)

- `DELETE /v1/join/request`(본인 pending 철회) + 전 센터 409 — 한 쌍으로.
- `GET /v1/join/requests`의 trainer 열람(어드민 회원 탭에서 트레이너도 큐를 보게) — 승인·거절은 owner 유지.
- 승인 푸시(FCM) — 대기실 폴링은 푸시가 와도 남는다.

## v2.35 관리 평면 센터 목록에 기본 센터 상시 포함 (2026-09-08, P70, 이 섹션도 계약의 일부)

### 왜
superadmin이 처음 연 **센터 관리** 화면이 "아직 등록된 센터가 없습니다"였다 — 운영 중인 1호점
(라이즈)이 있는데도. `GET /v1/admin/centers`가 v2.16부터 **상호가 등록된 문서만** 돌려줬고
(정책 지연 시딩·헬스체크가 만드는 정책-only 유령 문서를 거르려고), 1호점이 정확히 그 상태
(`GET /v1/public/center` → `name:""`, 2026-09-08 재실측)였기 때문이다. P65는 이 사실을 화면 각주로
설명하고 넘겼는데, 람이 그 각주보다 빈 목록을 먼저 읽었다 — 운영 중인 센터가 안 보이는 목록은
유령을 거른 것이 아니라 진실을 거른 것이다.

### 변경
```
GET /v1/admin/centers   → 200 [Center]
  집합   DEFAULT_CENTER_ID ∪ 상호 등록 센터   (v2.33 GET /v1/join/centers와 같은 집합)
  순서   기본 센터 맨 앞 → 나머지 id 오름차순
  기본 센터가 상호 미등록이면   {id, name:"", status:"active", created_at: "0001-01-01T00:00:00Z"}
                               — 빈 채로 보낸다(JoinCenters 규약). 클라이언트가 "상호 미등록"으로 그린다.
  기본 센터가 상호를 등록하면   같은 자리에 한 번만(중복 없음).
  기본 센터가 아닌 상호 미등록 문서   여전히 제외(유령).
```

### 무변경
- 응답 모양(`[Center]`)·키 집합 그대로. `name`이 빈 문자열일 수 있게 된 것뿐이다 — 어드민 외
  소비자 없음(superadmin 전용 경로).
- `POST /v1/admin/centers`는 name 필수 그대로 — 관리 평면으로 만든 센터는 항상 목록에 오른다.
- 상호를 채우는 경로는 그대로 owner 전용 `PUT /v1/center {center}`(v2.27). superadmin은 못 고친다.

### 자문자답
- **기본 센터가 유령일 수 있나?** 없다. config가 운영 센터라고 선언한 값이라 문서 상태와 무관하게
  실재한다(회원·스태프가 그 키 아래 산다).
- **기본 센터 문서가 아예 없으면?** GetCenter가 ErrNotFound 대신 ID만 채운 빈 값을 주는 스토어 규약이
  그대로 적용된다 — 목록에 `name:""`로 오른다. 없다고 숨기지 않는다.
- **created_at 제로값을 서버에서 지워야 하나?** 응답 타입이 domain.Center라 `time.Time`은 omitempty가
  안 듣는다. 어드민이 "0001-"을 "—"로 접는다. 다른 소비자가 생기면 그때 전용 응답 타입으로.

## v2.36 초대 계정의 최초 비밀번호 · 예약 슬롯 규칙의 프로덕션 강제 · 회원 검증 (2026-09-09, P71, 이 섹션도 계약의 일부)

람의 보고 한 줄에서 시작했다 — "센터 등록은 하는데 **비밀번호가 없어서** 문제". 그 자리를 파고
같은 계열(**말한 대로 동작하지 않는 곳**)을 3팀 병렬로 검수한 결과다.

### ① 최초 비밀번호를 응답에 싣는다

```
POST /v1/admin/centers → 201 {center, owner, initial_password?}
POST /v1/staff         → 201 {…Staff 필드 전부 최상위…, initial_password?}

initial_password   이번 요청이 **계정을 새로 만들었을 때만** 채운다.
                   비어 있음(omitempty로 키 자체가 없음) = 이미 있던 계정을 재사용했다는 뜻이고,
                   그 사람이 정한 비밀번호가 살아 있다. 화면은 두 경우를 다르게 그려야 한다.
값                 config.InitialStaffPassword (env INITIAL_STAFF_PASSWORD, 기본 "123456")
```

**왜 4자리가 아닌가**: Firebase Admin SDK가 요청 전에 로컬 검증으로 거부한다 —
`auth/user_mgt.go` *"password must be a string at least 6 characters long"*. 6자가 물리적 바닥이라
람이 요청한 "1234"는 계정 생성 자체가 실패한다. 그래서 기본값이 그 바닥에 맞춘 6자리이고,
`Config.Validate`가 **기동에서** 6자 미만을 거부한다(요청 경로로 내리면 센터 문서·정책이 이미
저장된 뒤 대표 생성만 실패해 "센터는 있는데 대표가 없는" 반쪽 상태가 남는다).

**왜 이 값이 필요했나**: 종전 설계는 "난수를 걸고 어드민 프론트가 sendPasswordResetEmail을 보낸다"
였고, 그 규약을 지키는 화면은 **트레이너 초대 하나뿐**이었다. 센터 생성 화면에는 그 호출이 아예
없어서 새 센터 대표는 메일도 비밀번호도 없이 계정만 받았다 — 로그인할 방법이 0인 계정이다.
메일 경로도 단독으로는 약했다(스팸함·도메인 메일 차단·오타 주소면 초대가 통째로 멈추고 대표에게
손쓸 수단이 없다). 이제 **둘 다** 한다: 메일을 보내고, 값도 화면에 띄운다.

**보안 상충을 적어 둔다**: 기본값은 공개 저장소에 적힌 상수다. 최초 로그인 후 변경이 전제이고
어드민 화면이 그 문장을 함께 띄운다. 운영에서 강화하려면 `INITIAL_STAFF_PASSWORD`를 덮어쓴다.

### ② 예약 슬롯 규칙이 프로덕션에서 강제되지 않고 있었다 (CRITICAL, 이미 배포돼 있던 결함)

`store/firestore.go`의 `BookAtomic`이 **`domain.CanBook`을 호출하지 않았다.** 그 함수의 머리
주석은 처음부터 *"슬롯 읽기 → CanBook 판정 → 예약 생성"*이라고 적고 있었고, 판정만 없었다.
호출은 `store/memory.go`에만 있었고 **전 테스트가 Memory를 타므로 초록불이었다.**

에뮬레이터 실측(정원 3 슬롯):

```
수정 전   코치 중복 = nil · 회원 중복 = nil · 정원 초과 = nil → 슬롯에 6팀 커밋(t1 2회, mem_a 2회)
수정 후   ErrTrainerBusy · ErrMemberBusy · ErrSlotFull  → 3팀에서 멈춤
```

즉 프로덕션에서 **정원이 무제한**이었고, 같은 코치가 같은 시간에 두 수업을 받았고, 예약 확정 중
네트워크가 끊겨 재시도하면 같은 회원이 같은 슬롯에 두 번 들어가 세션이 두 번 차감됐다.
어드민·앱이 그리던 "3/3 만석"은 참이 아니었다.

컨포먼스 스위트에 `BookAtomicEnforcesSlotRules`를 넣었다. 기존 커버리지가 비껴간 이유가 정확히
하나다: `testBookAtomicBudget`·`testConcurrentBookings`는 잔여 회차를 겨냥해 goroutine마다 **다른
slotKey**를 쓴다 — 슬롯 규칙은 같은 슬롯에 겹쳐 넣어야만 드러난다.

**배포 시 유의**: 이미 정원을 넘겨 있는 슬롯은 그대로 남고, 그 슬롯의 **새 예약만** 거부된다.
데이터 마이그레이션은 없다(과거 예약을 서버가 임의로 취소하지 않는다).

### ③ 회원 레코드 검증 신설

```
POST /v1/members · PUT /v1/members/{id}(스태프 경로)
  이름     필수, 40자 이내
  전화번호  필수, 정규화 후 10~11자리
  status   active | dormant 만 허용
  withdrawn 레코드는 검증 면제(Anonymized가 이름·번호를 비운 상태로 보존된다)
```

회원만 도메인 검증이 없어(Staff·Center·Business·Facility·Policy는 전부 있었다) 이름도 번호도 빈
회원이 200으로 저장됐다. v2.32부터 **번호가 센터를 정하므로** 번호가 비거나 자릿수가 틀리면 그
회원은 앱 매칭이 영원히 실패하는데, 데스크에는 등록 성공만 보인다.

`status` 화이트리스트가 닫는 것은 따로 있다: 이 경로는 body를 `domain.Member`에 그대로 언마샬해서
`{"status":"withdrawn"}` 한 줄이면 그 회원이 종단 상태로 굳었다 — 되돌릴 API가 없고, **실제 파기는
일어나지 않아** 개인정보는 그대로 남는 가짜 탈퇴였다. 진짜 탈퇴는 `DELETE /v1/me` 하나다(v2.11).

**전화번호 표기는 바꾸지 않는다.** 저장을 정규화(숫자만)하려다 되돌렸다 — 두 스토어의
`FindMemberByPhone`이 **비교 시점에 양쪽을 정규화**하므로 저장 형식은 매칭에 영향이 없고,
바꾸면 기존 문서와 새 문서의 표기만 갈린다. 자릿수 검증만 정규화 값으로 한다.

### ④ 되돌린 것 — 같은 번호 중복 등록은 계속 허용한다

검수가 *"승인 경로(v2.34)에는 중복 번호 409가 있는데 데스크 손등록에는 없다"*를 결함으로 지적했고,
실제로 409를 넣었다가 **철회했다.** 그 비대칭은 누락이 아니라 설계다:

- 부모 번호로 자녀 둘을 등록하는 건 실제로 흔하다(`store/memory.go` `betterPhoneMatch` 주석).
  이 저장소는 같은 번호 회원 여럿을 **지원하고**, 그 상태에서 매칭이 흔들리지 않도록 전순서 규칙
  (미연결 우선 → ID 오름차순)을 두 스토어가 공유한다(`TestJoinMatchIsDeterministicForSharedPhone`).
  데스크에서 막으면 가족 등록이 불가능해진다.
- 승인 경로에만 409가 있는 이유는 거기서만 **앱 계정이 레코드에 붙기** 때문이다. 중복이 생기면 앱
  연결은 한쪽에, 회원권·기록은 다른 쪽에 남는다. 데스크 등록에는 그 결합이 없다.

### ⑤ `guardNotStaff`의 fail-open 교정

모든 스토어 에러를 "신규 사용자"로 접고 있었다. Firestore 순단 중 대표 계정이 join 경로를 타면
방어선이 조용히 꺼지고, 뒤이은 `SaveUserIndex`가 role을 member로 덮어 **그 대표가 자기 센터에서
영구히 잠긴다**(되돌릴 API 없음). `ErrNotFound`만 부재로 접고 나머지는 그대로 올린다 —
`guardIndexNotLinkedMember`·`JoinApprove`가 이미 지키던 규약에 이 함수만 맞춘 것이다.

### ⑥ 스태프의 로그인 ID를 저장하고, owner에게만 보여준다

```
domain.Staff.email  (json:"email,omitempty")
  저장    POST /v1/staff · POST /v1/admin/centers · 재고용 경로에서 req.Email을 그대로
  마스킹  GET /v1/staff — owner: 전원 / trainer: 본인만 / member: 없음
  빈 값   "이메일이 없다"가 아니라 **"모른다"**(마스킹됐거나 v2.36 이전 레코드거나)
```

종전엔 이메일을 계정 발급용 일회성 입력으로만 쓰고 버렸다. 그래서 "트레이너가 로그인이 안 돼요"
연락을 받은 대표가 그 사람의 등록 이메일을 확인할 방법이 제품 안에 없었다(Firebase 콘솔뿐이고,
오타로 만들었어도 알 길이 없었다).

**마스킹이 필수인 이유**: `GET /v1/staff`는 어드민 직원 표만 쓰는 응답이 아니다 — **회원 앱의
코치 소개**가 같은 목록을 읽는다(P40). payout과 같은 자리에서 같은 규칙으로 지운다.

이 절은 종전 계약 하나를 **뒤집는다**: `TestCreateStaffHTTPContract`가 password·temp_password와
함께 email까지 금지 목록에 두고 "초대는 재설정 메일로"라고 적고 있었다. 그 전제(재설정 메일만으로
초대가 완결된다)가 ①에서 무너졌고, email은 애초에 **요청자가 방금 타이핑한 값**이라 감출 비밀이
아니었다. 난수 임시 비밀번호(password·temp_password)는 여전히 나가지 않는다 — 그 값은 이제 존재하지도 않는다.

### 무변경
- 응답 모양은 **키 추가뿐**이다. `POST /v1/staff`는 `*domain.Staff` 임베딩이라 기존 필드가 전부
  최상위에 그대로 온다(구버전 클라이언트 파싱 보호 — 와이어 테스트로 고정).
- 비밀번호 재설정 메일 경로(`Login.tsx`·`Settings.tsx`)는 그대로다. 이 절은 그것을 **대체하지 않고
  보완한다**.
- 앱(Flutter)에서 이 절을 소비하는 경로는 없다.

## v2.37 전면 재감사 후속 — 환불액 영속화 · 체형사진 입력 검증 · 동의 시각 서버 기록 · superadmin 관문 정밀화 · 스토어 대칭성 (2026-09-26, P73, 이 섹션도 계약의 일부)

람의 "구멍·버그·사용자 편의성 전면 검수 → 교차검증 → 자문자답 반복"에서 3계층 7팀 병렬 감사 뒤
직접 열어 확정한 것만 실었다. 와이어 변경은 **키 추가(①)와 400 확대(②·③)** 뿐이고 나머지는 서버
내부 동작 정정이다. 앱·어드민 구버전은 전부 그대로 동작한다.

### ① `Pass`에 환불액이 남는다 — `refunded_amount` · `refunded_at`

```
Pass {…기존 필드…, refunded_amount?: int, refunded_at?: RFC3339}

refunded_amount   POST /v1/passes/{id}/refund 가 정산한 실제 환불액(원). RefundResult.refund와 같은 값.
                  **0원 환불도 키가 있다**(`"refunded_amount":0`) — 사용분+위약금이 실수납을 넘어 정산이 0원으로
                  끝나는 환불이 실재하므로 서버는 포인터(nil=모름 / &0=0원)로 들고 있다.
refunded_at       마감 시각(UTC). status=refunded 와 **같은 트랜잭션**에서 함께 쓴다.
없음(omitempty)   환불 전 · v2.37 이전에 환불된 문서. 클라이언트는 키 부재를 "0원 환불"로 그리지 않는다.
```

**왜**: 이 제품의 축이 "센터 돈 관리(원장)"인데, 돈이 **나가는** 유일한 사건(환불)의 액수는
`RefundResult`(HTTP 응답)에만 있다가 응답 창을 닫는 순간 어디에도 남지 않았다. "이번 분기 환불
총액"·"이 회원에게 얼마를 돌려줬나"에 서버가 답할 수 없었고, 사후 재구성은 원장·결제·계약을 손으로
합쳐 `SettleRefund`를 다시 돌리는 일이었다. 정산은 이제 마감 트랜잭션 **안에서** 트랜잭션이 본
원장으로 계산해 패스에 함께 기록한다(재시도 시 mutate가 다시 불려도 값이 원장과 어긋나지 않는다).
응답의 `RefundResult`는 그 저장값과 같은 숫자다.

어드민: 회원 상세의 환불된 회원권 카드에 `환불액 ₩… · YYYY-MM-DD 마감` 한 줄. 앱: 소비 경로 없음
(freezed DTO는 미지 키를 무시한다).

### ② `POST /v1/body-photos` — `date`·`direction` 검증 (400 확대)

```
date        "YYYY-MM-DD" 형식이 아니면 400 "date는 YYYY-MM-DD 형식이어야 해요"
            서버(KST) 오늘보다 뒤면 400 "미래 날짜의 체형사진은 저장할 수 없어요"   — CreateInbody(v2.9)와 같은 규칙
direction   front|side|back 외는 400 "direction은 front|side|back 중 하나여야 해요"
```

**왜**: 둘 다 무검증이었다. 앱은 목록의 `date`를 `DateTime.parse`(throw)로 읽어 형식이 깨진 레코드
**하나**가 회원의 체형사진 타임라인 전체를 "불러오지 못했어요"로 접었다(인바디·수업 기록은
tryParse+건너뛰기였고 체형사진만 예외). 앱도 v1.0.1+9부터 tryParse로 바뀌지만, 저장 단계에서
막는 것이 먼저다. 앱 자체 업로드는 항상 KST 오늘·정해진 direction만 보내므로 정상 경로엔 영향이 없다.

### ③ `POST /v1/members` — 동의 시각은 서버가 찍는다

```
consent.signed_at    요청 값은 **무시**된다. sensitive=true 이거나 클라이언트가 signed_at을 실었으면
                     서버 시각(UTC)으로 기록, 둘 다 아니면 null.
consent.revoked_at   신규 레코드는 항상 null(요청 값 무시).
```

**왜**: `PUT /v1/members/{id}`는 v1.2부터 "전이 시각은 서버가 기록한다"였는데 **최초 서명**만 예외였다.
`CreateMember`는 `signed_at == nil`일 때만 채웠고, 어드민 등록 폼은 항상 데스크 PC 시계값을 실어
보냈다 — 민감정보 동의의 "언제"라는 준법 기록이 PC 시계 오차만큼 틀린 채 영구 저장됐다. 클라이언트가
값을 실었으면 "지금 동의했다"는 뜻만 취한다(어드민이 일반 동의만 켜도 시각을 싣는 현행 표시 규약 유지).

### ④ superadmin 관문(auth.go)의 판정 정밀화

```
허용 경로   정확히 /v1/me · /api/v1/me,  그리고 /v1/admin/* · /api/v1/admin/*
그 외       403 "forbidden: superadmin은 관리 평면(/v1/admin/*)만 사용할 수 있어요"  (변경 없음)
```

**왜**: 종전 판정은 `Contains("/admin/") || HasSuffix("/me")` 부분일치였다. `{id}`가 마지막 세그먼트인
라우트에 id=`me`(`DELETE /v1/inbody/me`), `{id}` 뒤에 정적 세그먼트가 붙는 라우트에 id=`admin`
(`POST /v1/bookings/admin/complete`)을 주면 관문을 지났다. 데이터는 새지 않았다 — CenterID=""로 내려간
조회가 스토어에서 먼저 실패한다 — 하지만 결과가 403이 아니라 500이라, "관문 하나가 87곳을 대신한다"는
불변식이 조용히 깨져 있었다. 이제 마운트 접두사(/api)만 벗기고 상수 비교다(`TestSuperadminPathBoundary`).

### ⑤ 서버 내부 정정 (와이어 무변경)

- **`GET /v1/stats`** — `expiring`(만료 임박)과 `hw_d`/`hw_rate`(Home Work 완료율)에서 **탈퇴 회원을
  뺀다**(v2.11 "탈퇴 회원은 어느 KPI에도 들어가지 않는다"가 회원 루프에만 적용돼 있었다). 탈퇴 시
  유효기간이 남은 패스가 "연장 제안" 대상으로 잡히고(연락처는 이미 파기), 배정에서 빠지지 않은
  탈퇴자가 hw-check 전부 삭제된 채 분모만 채웠다. `rereg_d`·매출은 **그대로**다 — 만료 뒤 떠난 사람은
  재등록하지 않은 사람이 맞고, 탈퇴자의 결제는 실제 매출이다. `by_trainer`도 같은 판정.
- **`POST /v1/bookings` · `POST /v1/recurrings`** — 담당 코치 조회(`GetStaff`)가 **부재(ErrNotFound)일
  때만** 퇴사자·휴무일 검사를 건너뛰고, 그 외 스토어 오류는 전파한다(500). 종전 `err == nil` 형은
  순단 시 두 거부가 통째로 꺼져 퇴사자·휴무일 앞으로 예약이 조용히 성립했다(P56 B7~B9와 같은 클래스,
  `TestGuardsDoNotSilentlyOpenOnStoreFailure`). 고정 스케줄의 휴무일도 규칙 저장 **전** 같은 조회에서
  받아 두 번째 조회를 없앴다(그 조회도 fail-open이었다).
- **스토어 대칭성** — `Firestore.GetBodyPhoto/SaveBodyPhoto/DeleteBodyPhoto`에 `checkDocID`(빈 id →
  ErrNotFound, 다른 단건 13종과 같은 규칙) · `Memory.GetCenter/ListCenters`가 읽기 시점 `Normalize()`
  (빈 status → active, Firestore·Policy·Business·Facility·CheckinQR와 같은 규칙). 둘 다
  `conformance_test.go`에 케이스를 추가해 고정.

### 클라이언트 · 문서 (계약 외 변경, 이 P에서 함께)

- 앱: **v2.32 `join/match.center`를 드디어 읽는다**(P65 후속 3) — 대기실 매칭 카드가 매칭된 회원의
  센터 상호를 찍고, 로그인 뒤 홈 헤더·마이 탭은 세션 `center_id`로 `GET /v1/public/center?center=`를
  묻는다(종전엔 둘 다 기본 센터 고정 — 2호점 회원에게 1호점 상호) · 동의 저장 → 촬영 게이트
  (`myProfileProvider`) 동반 갱신 · 예약 생성/취소 → 마이 탭 동반 갱신 ·
  스태프 캐시를 세션 신원에 묶음(로그아웃 뒤 다음 계정이 이전 센터 명단을 15분 보던 문제) ·
  체형사진 뷰어 삭제 중 닫기 잠금 · 성공 스낵바 3곳 · 서명 패드 44dp · 포즈 칩 Semantics · iOS
  버전 단일 소스 복원(pbxproj 리터럴 제거 + 가드) · `pubspec 1.0.1+9`.
- 어드민: 완료/노쇼 → stats 무효화 · 뮤테이션 중 모달 닫기 잠금 전면 · 만료 임박 이름 링크 ·
  Firebase 오류 한국어 공용표 · 예약 그리드 최소 폭+가로 스크롤 · 환불액 표시.
- 법정 문서: `account-deletion.html`·`privacy.html`의 "예약·체크인 기록 삭제"를 실제 동작(체크인·
  **앞으로의** 예약 삭제, 지난 예약 이력 5년 보존)으로 정정 · `support.html` "자동으로 연결"(P72-3).
- 배포·설정: `firebase.json`에 `/api/v1/public/center` 캐시 헤더 · `.env.example`에
  `INITIAL_STAFF_PASSWORD` · README 3종 스테일 수치 정정.

### 무변경
- 엔드포인트 목록·인가 규칙·에러 포맷. ①은 키 추가, ②·③은 이미 거부돼야 했던 입력의 400 확대다.
- 앱 DTO는 `refunded_*`를 파싱하지 않는다(필요해지면 그때 추가 — 미지 키는 무시된다).

## v2.38 성능·보안·운영 감사 후속 — 요청 빈도 제한 · 체형사진 경로 소유 검증 · 접속기록 429 · 읽기 범위 축소 (2026-09-26, P74, 이 섹션도 계약의 일부)

P73(정합·UX)이 끝난 뒤 "그럼 완성인가"에 대한 답으로 **한 번도 감사 축이 아니었던** 성능·보안·운영·
의존성을 돌았다(work_log/P74). 와이어 변경은 **429 신설(①)과 400 확대(②)** 둘이고, 접속기록 범위가
한 줄 넓어진다(③). 나머지는 같은 답을 더 적게 읽어 내는 서버 내부 정정이다(④). 앱·어드민 구버전은
전부 그대로 동작한다 — 429는 앱의 기존 4xx 경로(`RejectedFailure`)로 떨어져 서버 문구가 그대로 보인다.

### ① 요청 빈도 제한 — 429 `rate_limited`

```
대상 경로                                                       키          정상 속도    순간(burst)
POST /v1/join/match · /join/confirm · /join/request · /consult-requests   회원 uid    분당 30      15
POST /v1/checkin · /hw-checks  (두 경로가 한 버킷을 나눠 쓴다)   회원 uid    분당 120     40
GET  /v1/public/business · /v1/public/center (+ /api/v1 미러)   IP          분당 60      30
스태프(owner·trainer)·superadmin 요청                           세지 않음   — 어드민 원탭 체크인(POST /v1/checkin) 포함
그 외 전 경로                                                    제한 없음

응답   429  {error:"요청이 너무 잦아요 — 잠시 후 다시 시도해주세요", code:"rate_limited"}
       Retry-After: <초>  (다음 토큰까지 남은 시간을 올림, 최소 1)   ·   Cache-Control: no-store (writeJSON 규약)
순서   /v1 그룹은 accessLog → auth → (경로별) 제한 → 핸들러. 인증 실패는 여전히 401이 먼저고, 제한은 **핸들러
       보다 앞**이라 429가 난 요청은 본문 검증·저장에 닿지 않는다(400이 될 요청도 429가 될 수 있다).
```

**왜**: 종전 미들웨어 체인엔 "같은 사람이 얼마나 자주 불러도 되는가"를 재는 층이 없었다. P55의 멱등성은
*같은 내용의 중복 제출*을 막는 축이고 빈도는 다른 축이다 — 상담 요청은 인증만 되면 무한히 쌓였고,
무인증 공개 경로는 Hosting 경유(`/api/v1/public/*`, CDN 5분 캐시)와 달리 앱이 직접 부르는 Cloud Run
URL(`/v1/public/*`)엔 완충이 전혀 없어 호출이 그대로 Firestore 읽기였다.

**수치의 근거**: 요청 큐 4종은 사람이 한 번 누르는 일이고 대기실 자동 확인은 30초 간격이라 정상 사용은
한 자릿수/분이다. 체크인·hw-check는 **탭 하나가 POST 하나**라 하루치 홈워크(개인+담당+공지 합쳐 15개
안팎)를 한 번에 훑으면 15에 닿는다 — 그래서 따로 두고 순간 40으로 잡았다. 공개 경로는 센터 와이파이 뒤
회원 수십 명이 동시에 앱을 켜는 경우(공유 IP)를 burst가 흡수하도록 한 사람 기준보다 후하다. 목적은
**폭주 루프(스크립트·앱 버그)의 상한**이지 사람 손의 제한이 아니다.

**왜 스태프는 세지 않나**: 어드민의 원탭 체크인이 회원 셀프 체크인과 같은 `POST /v1/checkin`을 쓴다.
데스크 한 명이 수업 시작 전에 몰아서 누르는 것은 폭주가 아니라 업무이고, 스태프 토큰은 이보다 훨씬
강한 쓰기(회원·결제·환불)를 원래 제한 없이 하므로 이 경로만 세어서는 방어 가치가 없다.

**한계(계약의 일부)**: 프로세스 내 토큰 버킷이라 Cloud Run 인스턴스가 n개면 상한도 n배로 느슨하다.
무인증 경로의 키(chi `middleware.RealIP` — `True-Client-IP` → `X-Real-IP` → `X-Forwarded-For` 첫 값 순)는
클라이언트가 위조할 수 있으므로 공개 경로 제한은 "선의의 폭주 방지"이지 적대적 방어선이 아니다 — 그 자리는
App Check(후속, work_log P74)다. 같은 값이 접속기록(v2.30)의 `remote_ip`에도 쓰인다. chi는 v5.3.0에서
RealIP를 폐기 표시하고 신뢰 프록시를 받는 `ClientIPFrom*`를 냈다(GHSA-3fxj 외 2건 — **버전만 올려서는
RealIP 동작이 같다**). 이전은 Cloud Run 직결·Hosting 경유 두 경로의 XFF 홉 수를 실측한 뒤다(P74 후속). 위조 키가 메모리를
키우지 못하도록 **키 표는 인스턴스당 1만 개가 상한**이고, 가득 차면 새 키는 추적 없이 통과한다
(fail-open — 위조 키는 어차피 매번 가득 찬 새 버킷이라 거를 수 없었고, 이미 추적 중인 키의 제한은
그대로이며, 정상 신규 사용자가 공격 때문에 429를 받지 않는다. 통과 건수는 분당 최대 한 줄로 서버 로그).
버킷은 가득 찰 만큼(burst÷속도, 20~30초) 쉬면 지운다 — 새 버킷과 상태가 같아 제한 결과는 변하지 않는다.
정확한 분산 제한이 필요해지면 Cloud Armor/Memorystore로 올린다.

**클라이언트 규약**: `code === "rate_limited"`로만 판별한다(문구는 바뀌어도 되는 값). 429에 **자동
재시도를 붙이지 않는다** — 사람이 보는 리듬으로만 다시 부른다. 앱은 현재 429를 `RejectedFailure(서버
문구)`로 보여 주고 원상복구(홈워크 역토글)하므로 **앱 변경 없음**. 대기실 자동 확인은 30초 일회성 타이머이고
(30→60→120초 물러남은 `GET /v1/me` 실패에만 걸린다), 그 안의 매칭 재조회(`POST /v1/join/match`)는 429를
포함한 실패를 삼켜 "아직"으로 접는다 — 분당 2회라 한도(분당 30)에 닿지 않는다. 공개 연락처(`GET /v1/public/
center`)의 429는 연락처 카드가 빈 값으로 접혀 임시 상호가 보이고, 화면을 다시 열면 다시 묻는다. 어드민이 부르는 제한 경로는 원탭 체크인(`POST /v1/checkin`) 하나인데 스태프 요청은
세지 않으므로 **어드민은 429를 보지 않는다**.

### ② `POST /v1/body-photos` — `storage_path`는 이 회원의 폴더 안이어야 한다 (400 확대)

```
storage_path   정확히 members/{member_id}/body/{fileName} — 세그먼트 4개, {member_id}는 요청의 member_id와 같아야
               하고, {fileName}은 비어 있지 않은 한 조각(슬래시 없음, "."·".." 아님).
               아니면 400 "storage_path는 이 회원의 체형사진 폴더(members/{member_id}/body/) 안이어야 해요"
```

**왜**: 레코드의 **소유**(member_id)는 P08 스코프로 지키면서, 그 레코드가 **가리키는 파일**은 "비어 있지
않은 문자열"이면 무엇이든 받았다. 남의 경로(또는 임의 경로)를 가리키는 메타가 생기면 회원 타임라인이
그 자리에서 깨지고, 소프트 삭제 뒤 파기(`purgeBodyPhoto`)가 **남의 파일**을 대상으로 삭제를 시도한다.
접두사 규약은 `storage.rules`·앱(`BodyPhotoStoragePath`)이 이미 공유하던 것 그대로라 정상 경로엔 영향이
없다(`domain.BodyPhotoPathOwnedBy`, 테스트 7케이스).

### ③ 접속기록(v2.30) — 429를 거부로 기록한다

```
거부(역할 무관 기록, WARNING)     401 · 403 · **429**(v2.38 추가)
회원(member)                        401·403·429 외에는 기록하지 않는다(400·404·5xx 포함)   ← 429 한 글자 추가
```

**왜**: 제한기가 언제 무엇을 막았는지가 로그에 없으면 상한을 조정할 근거도, 앱의 호출 루프 버그를 알아챌
길도 없다. 회원 쓰기 경로의 429는 uid 키라 이 라인이 유일한 관측점이다. 403과 같은 "오·남용 신호"라
§8② 취지에 맞고, 라인의 내용(uid·route·ip)도 403 라인과 같다 — 정상 본인 접속을 남기지 않는 원칙은
그대로다(`TestAccessLogRecordsMemberRateLimited`). 무인증 공개 경로(`/v1/public/*`)는 종전대로 v1
클로저 밖이라 접속기록을 지나지 않는다 — 그쪽 429는 Cloud Run 요청 로그(30일)의 status로 본다.

### ④ 서버 내부 정정 (와이어 무변경 — 같은 답, 더 적은 읽기)

- **`GET /v1/hw-checks?member=`·홈워크 완료 판정** — 회원 지정 조회가 센터 **전체** hwChecks를 읽고
  메모리에서 거르던 것을 `ListHwChecksByMember`(Firestore `member_id ==` 쿼리)로. 회원 수 × 일수만큼
  자라는 컬렉션이라 홈 탭 한 번이 센터 전체 기록을 읽고 있었다.
- **`GET /v1/stats` HW 완료율** — **활성 배정(기간 안·스코프 안)의 대상 회원만, 회원당 1번**(중복 제거,
  동시 8) 읽는다. 종전은 배정×대상회원 조합마다 그 회원 것을 다시 읽었고(scope=center면 트레이너 표가 한
  번 더), P74 1차의 "센터 hwChecks 전량 1회"는 그 컬렉션이 회원×날짜로 자라는 데다 배정 없는 트레이너의
  scope=me도 전량을 읽어 감사 실측 뒤 되돌렸다(활성 배정이 없으면 0회). 한 회원의 조회 실패는 **그 회원만**
  분자에서 빠진다(종전과 같은 단위 — 1차는 한 번의 실패가 완료율 전체를 조용히 0으로 만들었다, 로그 한 줄).
- **환불 기준액(`refundBasis`)·기록된 결제 합계·회원 결제 목록·계약서 템플릿·탈퇴 파기 집계** — 센터
  전체 payments 스캔을 `ListPaymentsByPass` / `ListPaymentsByMember`(단일 필드 등호 — 복합 인덱스
  불필요)로. 답은 같다(`TestRefundReadsOnlyThatPassPayments` — `quote.PaidSum == 1,000,000`).
- **`GET /v1/members`(스태프)** — 회원별 패스 조회 + 패스별 원장 재계산이 **직렬 N+1**이었던 것을 병렬
  (회원 8 · 패스 4 동시, `forEachParallel`: 첫 오류가 나머지를 취소, 부모 ctx 취소를 그대로 전파,
  **워커 패닉은 오류로 바꿔 그 요청만 500** — 워커는 요청 고루틴 밖이라 recoverJSON이 닿지 않고, 잡지
  않으면 인스턴스 전체가 죽는다)로. 순서·내용은 직렬과 같다(`TestListMembersParallelMatchesSequential`).
- 스토어 인터페이스 `ListPaymentsByPass`·`ListPaymentsByMember` 추가 — Memory·Firestore 대칭,
  `conformance_test.go`에 케이스 고정(`ListHwChecksByMember`도 같은 파일에 — 2026-10-16 에뮬레이터 통과).
- **체형사진 파기는 그 회원 폴더 안의 파일만 지운다** — 회원 즉시 삭제·30일 유예 뒤·탈퇴 파기 공통
  (`ownedBodyPhotoPath`). ②의 생성 검사보다 앞서 저장된 레코드가 남의 경로(`staff/photos/…` 등)를 가리키면
  파기가 남의 파일을 지우는 원시 연산이 됐다 — 폴더 밖이면 파일은 두고 메타만 지운다(로그 한 줄).

### 클라이언트 · 배포 (계약 외 변경, 이 P에서 함께)

- 어드민: 9개 화면 `React.lazy` 코드 분할(첫 진입 번들 축소) · 로그아웃 시 체형사진 blob 캐시 비움
  (`clearBodyPhotoBlobs` — 만들어 두고 한 번도 부르지 않았다: 데스크 PC를 다음 사람이 이어 쓰면 이전
  세션의 민감 사진이 메모리에 남아 있었다) · 회원 목록 파생값 `useMemo`. 감사 후속: 배포 직후 열려 있던
  탭이 아직 받지 않은 화면 조각을 부르다 실패하면(새 배포엔 옛 해시 파일이 없다) **1회 자동 새로고침**
  (`vite:preloadError` — 10분 안에 또 실패하면 오류 카드) · blob 캐시 **30장 상한**(최근 사용 순, 밀려난
  URL은 revoke) · 받는 **도중** 로그아웃되면 그 사진을 다음 세션 캐시에 넣지 않음 · 다른 탭에서 **다른 계정으로
  곧장** 로그인하면(signOut 없이) 이 탭도 쿼리·blob 캐시를 비우고 me를 다시 읽음.
- 앱: 홈·마이·기록 탭의 독립 요청을 **동시에** 띄움(`Settled` 공용화 — 마이 탭은 5왕복 직렬이었다) ·
  수업 기록 목록 10건 + "더 보기" 20건씩 · 체형사진 로더 메모리 캐시 상한 40장(LRU). 감사 후속: 패스별
  원장은 **동시 4개 상한**(`settleEach` — 패스 수는 재등록마다 늘어 상한 없이는 연결이 그만큼 한꺼번에 열렸다) ·
  체형사진을 받는 **도중** 세션이 끝나면 캐시에 넣지 않음(세대 표식) · 펼침 행 2곳 버튼 의미(Semantics).
- 배포·규칙: `firebase.json` 응답 헤더(nosniff · X-Frame-Options DENY · Referrer-Policy · HSTS 1년 ·
  Permissions-Policy 카메라/마이크/위치 차단) · `storage.rules` 체형사진 contentType을 `image/*`에서
  `image/(jpeg|png|webp)`로(SVG 등 스크립트를 품는 형식 배제 — 앱은 `image/jpeg`를 명시한다) · 감사 후속:
  `/`에도 `Cache-Control: no-cache`(운영 실측 2026-10-16: `/index.html`만 no-cache이고 `/`는 Hosting 기본
  `max-age=3600` — 새로 고친 탭이 1시간 동안 옛 index를 다시 받을 수 있었다).
  **셋 다 `firebase deploy`가 있어야 반영된다**(코드 배포와 별개).
- Hosting 헤더 규칙 vs 원본 `Cache-Control`(P35가 "문서상 불확실"로 남긴 것) — 운영 실측 2026-10-16:
  `/api/v1/public/business`의 404·`/api/v1/me`의 401은 원본의 `no-store` 그대로 나간다(Hosting의
  `public, max-age=300` 규칙이 오류를 캐시 가능하게 덮지 않는다). `/api/v1/public/center` 규칙은 지금
  Hosting 경유 호출자가 없다(앱은 Cloud Run 직결) — 무해한 대비.
- 의존성(govulncheck 2026-10-15, 호출 경로상 취약 11건+표준 라이브러리): 백엔드 grpc 1.84.0 · x/net 0.61.0 ·
  otel 1.47.0 · `toolchain go1.26.9`. chi RealIP 3건은 위 ①의 한계(이전 대기), RedirectSlashes 1건은 미사용.

### 무변경
- 엔드포인트 목록·인가 규칙·기존 에러 포맷. ①은 새 status(429)와 기존 `{error, code}` 확장 본문의
  세 번째 사용처(`route_not_found`·`media_not_configured`·`rate_limited`), ②는 이미 거부돼야 했던 입력의
  400 확대다. **`rate_limited` 문자열은 바꾸지 말 것**(앱이 code로 분기하게 될 때의 판별자).
- 제한 대상이 아닌 경로에는 429가 나지 않는다 — 어드민의 어떤 화면도 이번 변경으로 새 에러를 보지 않는다.
