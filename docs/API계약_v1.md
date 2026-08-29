# 라이즈 v1 API 계약 (백엔드·어드민·앱 공용 — 이 문서가 단일 진실)

Base: `/v1` · 인증: `Authorization: Bearer <Firebase ID token>` (로컬 개발: `X-Dev-Role: owner|trainer|member` + `X-Dev-Uid` 허용)
에러: `{"error":"메시지"}` · 시간: RFC3339 · 날짜: "2026-08-14" · slotKey: "20260814-20" (YYYYMMDD-HH)

## 엔티티 JSON (json 태그 = 이 이름 그대로)
```jsonc
Member   {id, name, phone, channel, trainer_id, flags:[{type:"injury",note}], consent:{general,sensitive,signed_at,revoked_at}, app_linked, status:"active|dormant", last_visit_at}
Pass     {id, member_id, trainer_id, product, paid_amount, total_sessions, remaining, valid_from, valid_until, status:"active|scheduled|expired|refunded", holds:[{from,to,reason}]}
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
GET  /v1/me                                → {uid, role, center_id, member_id?, name?}  (name은 v2.2)
POST /v1/join/match                        회원: 번호 인증 후 자동 매칭 조회 → {member?, needs_confirm:true}
POST /v1/join/confirm                      {member_id, confirm:true|false}  이름확인 1탭(P48)
POST /v1/join/request                      {center_id} 가입 요청 · POST /v1/join/approve {request_id} (owner)

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
GET  /v1/body-photos?member=  POST /v1/body-photos (동의 검증 P8)
DELETE /v1/body-photos/{id}  POST /v1/body-photos/{id}/restore  POST /v1/body-photos/purge (v2.14)
GET  /v1/inbody?member=  POST /v1/inbody
GET  /v1/staff  POST /v1/staff/{uid}/offdays
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
배열 필드는 항상 [] (null 금지)              Member.flags · Pass.holds · Staff.offdays — 신규 생성 경로 포함
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
photo_url        외부 이미지 URL(http/https만 — 스킴 주입 차단, ≤2048자). 빈 값 허용 — 업로드는
                 Storage 트랙 후속(도입 시 서버가 이 필드를 채우는 방식이라 클라이언트 계약 불변).
                 빈 값/로드 실패 시 클라이언트는 Staff.color 배경 + 이름 첫 글자 이니셜 아바타
title ≤40자 · career_years 0~50(0=미표기) · bio ≤500자 · 배열 원소 ≤80자·각 ≤20개
전 필드 회원 열람 전제의 공개 데이터 — payout 마스킹(P13)은 기존 그대로
```

### 신규 엔드포인트
```
PUT /v1/staff/{uid}/profile {profile}      owner 또는 본인 trainer(offdays와 동일 권한, member 403).
                                            "통 교체" 시맨틱 — 폼이 항상 전 필드 제출(머지 아님,
                                            빈 값으로 지우기 자연스러움). 범위 위반 400 한국어
```

### 기존 계약 변경
```
GET /v1/staff                              응답에 profile 포함(하위호환 — 기존 클라이언트는 미지정 키 무시)
DEV_SEED                                   스태프 3명 프로필 시딩(경력·자격·수상 텍스트 위주,
                                            photo_url 빈 값 — 오프라인 데모가 외부 이미지에 의존하지 않게)
```

### 운영(비계약) — DEV_SEED
`DEV_SEED=true`(인메모리 한정)면 데모 데이터 시딩: 스태프 3(owner1 박관장·t1 정혜린·t2 김태오),
회원 5(부상·휴면·미배정·만료임박 상태 포함), 패스·예약(완료/노쇼유예/예정)·고정 스케줄·홈워크·
결제(미납 1건)·계약(signed/sent)·수업기록·인바디. 회원 앱 데모 uid는 `member1`(김민지 연결).

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
     이 문서를 읽고 캐시가 없다) · Firebase 계정 Disabled + RevokeRefreshTokens(재로그인 차단).
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
                            않게). 응답은 신규와 같은 201 + Staff.
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
    purged:{body_photos, inbody, workout_logs, hw_checks, checkins, recurrings},
    retained:{passes, payments, contracts, ledger, bookings},
    cancelled_bookings, remaining_sessions
  }

  403 호출자가 owner|trainer — 스태프에겐 지울 회원 레코드가 없고, 회원으로도 연결된
      계정이면 UserIndex가 사라져 **센터가 대표를 잃는다**(복구 API 없음. v1.9 guardNotStaff·
      v2.0 락아웃 가드와 같은 계열). 스태프의 이탈 경로는 POST /v1/staff/{uid}/deactivate다.
  404 member_id 미연결(가입 매칭 전) — 지울 대상 자체가 없다. 200으로 통과시키면
      "탈퇴했다"는 응답이 실제로는 아무것도 하지 않은 응답이 된다.
  400 이미 탈퇴한 계정(정상 경로로는 도달하지 않는다 — 인덱스만 남은 잔여 상태의 이중 방어선)

  ⚠ **잔여 회차가 남아 있어도 막지 않는다.** 검토 후 기각: Guideline 5.1.1(v)는 사업상 상태를
    이유로 앱 내 삭제를 막는 것을 예외로 인정하지 않는다. 막을 실익도 없다 —
    Pass·Payment·Contract·Ledger가 전부 보존되므로 탈퇴 후 환불 요구에도 정산 근거가 살아 있다.
    대신 응답의 remaining_sessions로 고지한다(앱이 확인 화면·완료 안내에 그대로 띄운다).

  ⚠ **재시도 경로가 없다.** 성공하면 UserIndex가 사라져 같은 uid의 두 번째 호출은 404다.
    되돌리는 API도 없다(탈퇴는 종단 상태 — 복직이 있는 스태프 퇴사와 다르다).
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
  UserIndex(uid→member_id) · **Firebase Identity Platform 계정**

보존(비식별 상태로 5년)
  Ledger(append-only 불변식) · Pass · Payment · Contract · 과거 Booking
  → 이름·번호가 사라져 member_id라는 **가명만 붙은 거래 기록**으로 남는다.
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
④ 가명화 + 건강·이용 기록 파기     (Store.PurgeMemberPersonalData — 기록 먼저, 회원 문서 마지막)
⑤ UserIndex 삭제                 (호출자의 권한 자체를 없애므로 반드시 마지막)

메타보다 **파일을 먼저** 지운다: 반대로 하면 경로를 아는 유일한 문서가 먼저 사라져 민감정보
원본이 버킷에 영영 남고, 그 잔존은 어느 화면에도 드러나지 않아 발견조차 불가능하다.
VerifyIDToken은 계정 삭제를 확인하지 않아 토큰이 최대 1시간 유효하다 — ②가 앞에 있어도
④⑤의 재시도가 가능한 이유다(v2.0 퇴사 처리 주석과 같은 사실).
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

### 신규 엔드포인트 — 유일한 무인증 v1 경로

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
