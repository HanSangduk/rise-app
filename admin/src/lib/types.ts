// 백엔드 API 계약을 그대로 미러링한 TS 타입. json 태그와 1:1.
// 원천: ptdesk/docs/API계약_v1.md (§엔티티 JSON) — "이 문서가 단일 진실".
// 시간: RFC3339 문자열 · 날짜: "2026-08-14" · slotKey: "20260814-20" (YYYYMMDD-HH)
//
// 계약 확장 가정(GAP) — 화면 구현을 위해 추정한 타입/필드는 파일 하단 "계약 확장 가정" 섹션 참고.
// SlotTeam.status와 비율 필드 0~1 규약(구 [가정 5]·format.ts)은 v1.1 정합 패치로 계약 확정됐다.
// [가정 4](GET /v1/center)는 v1.4 기능 패치로 계약 확정 — 백엔드 실응답 형태로 교체했다.
// 나머지 [가정 1~3]은 백엔드 실장 시 반드시 대조·확정 필요(README.md 갭 목록에도 동일 내용 기록).

export type Role = "owner" | "trainer" | "member";

export type Weekday = "mon" | "tue" | "wed" | "thu" | "fri" | "sat" | "sun";
export const WEEKDAY_LABEL: Record<Weekday, string> = {
  mon: "월",
  tue: "화",
  wed: "수",
  thu: "목",
  fri: "금",
  sat: "토",
  sun: "일",
};

// 진입경로 — 설계 03 §R7: 계약 등록 시 필수 선택(경쟁 대시보드 "미지정 75%" 반면교사).
export const CHANNEL_OPTIONS = ["지인소개", "인스타", "워크인", "재등록", "기타"] as const;

// ── Member ──────────────────────────────────────────────────────────────
/// `withdrawn`은 회원탈퇴(계약 v2.11). 문서 자체는 남는다 — 5년 보존해야 하는 계약·결제·원장이
/// member_id로 이 회원을 조인하므로, 목록에서 지워버리면 보존하기로 한 기록들이 미수금 표·계약
/// 목록에서 이름 없이 깨진다(v2.0에서 퇴사 스태프를 GET /v1/staff가 계속 반환하는 것과 같은 근거).
export type MemberStatus = "active" | "dormant" | "withdrawn";
export type FlagType = "injury"; // 계약상 현재 정의된 플래그는 부상(injury) 1종

export interface MemberFlag {
  type: FlagType;
  note: string;
}

export interface Consent {
  general: boolean;
  sensitive: boolean;
  signed_at: string | null;
  revoked_at: string | null;
}

export interface Member {
  id: string;
  name: string;
  phone: string;
  channel: string;
  trainer_id: string;
  flags: MemberFlag[];
  consent: Consent;
  app_linked: boolean;
  status: MemberStatus;
  last_visit_at: string | null;
  /// 탈퇴(파기) 시각(계약 v2.11, RFC3339). status=withdrawn일 때만 온다.
  /// 전자상거래법상 보존기간(계약·결제 5년)의 기산점이라 언제 지워도 되는지의 근거가 된다.
  withdrawn_at?: string | null;
  /// 이 회원의 체형 촬영 시퀀스(계약 v2.10). 응답은 **항상 구체화**되어 온다(비어 있지 않음)
  /// — 커스텀이 없으면 서버가 센터 기본 4종을 채워 준다.
  /// PUT에서 배열=교체 · null/[]=기본으로 초기화 · **필드 생략=유지**.
  body_poses?: PoseSpec[];
}

// ── Pass(회원권) ────────────────────────────────────────────────────────
export type PassStatus = "active" | "scheduled" | "expired" | "refunded";

/**
 * 이 회원권으로 예약을 잡을 수 있는 상태인가 — 서버 `domain.Pass.BookableStatus()`의 거울.
 *
 * **scheduled를 포함한다.** 아직 시작 전인 재등록 회원권으로도 유효기간 안의 슬롯이면
 * 선예약이 되어야 한다(v1.3 시간축: 기준은 "오늘"이 아니라 "슬롯이 일어나는 날").
 * 여기서 빼면 서버는 받아주는 예약을 어드민 화면이 못 만든다.
 *
 * 상태는 서버가 유효기간에서 계산해 응답에만 싣는다(P25) — 종전엔 저장값이 늘 active라
 * expired·scheduled가 한 번도 내려오지 않았고, 그래서 이 구분이 죽어 있었다.
 */
export const isPassBookable = (p: { status: PassStatus }): boolean =>
  p.status === "active" || p.status === "scheduled";

export interface PassHold {
  from: string;
  to: string;
  reason: string;
  by?: string; // 설계03 §11 스키마엔 있으나 API계약 엔티티 표기엔 생략 — 낙관적으로 optional 수용
}

export interface Pass {
  id: string;
  member_id: string;
  trainer_id: string;
  product: string;
  paid_amount: number;
  total_sessions: number;
  remaining: number;
  valid_from: string;
  valid_until: string;
  status: PassStatus;
  holds: PassHold[];
}

// ── Ledger(세션 원장) ───────────────────────────────────────────────────
export type LedgerReason =
  | "issue"
  | "complete"
  | "noshow"
  | "noshow_waived"
  | "revert"
  | "refund"
  | "hold"
  | "resume"
  | "transfer";

export interface Ledger {
  id: string;
  pass_id: string;
  member_id: string;
  delta: number;
  reason: LedgerReason;
  ref_booking_id: string | null;
  by: string;
  at: string;
}

// ── Slot / Booking / Recurring ─────────────────────────────────────────
export type BookingKind = "pt" | "group" | "ot";
export type BookingStatus = "confirmed" | "waitlist" | "cancelled" | "noshow" | "completed";

export interface SlotTeam {
  booking_id: string;
  trainer_id: string;
  member_id: string;
  kind: BookingKind;
  // v1.1 정합 패치로 계약 확정: 팀 항목에 예약 상태가 실린다. 취소된 예약은 teams에서
  // 제거되므로 waitlist/cancelled는 실제로 오지 않는다(confirmed | completed | noshow만).
  status?: "confirmed" | "completed" | "noshow";
}

export interface Slot {
  slot_key: string;
  capacity: number;
  teams: SlotTeam[];
}

export interface Booking {
  id: string;
  slot_key: string;
  member_id: string;
  trainer_id: string;
  pass_id: string;
  kind: BookingKind;
  status: BookingStatus;
  recurring_id: string | null;
  created_at: string;
}

export interface Recurring {
  id: string;
  member_id: string;
  trainer_id: string;
  pass_id: string;
  days: Weekday[];
  hour: number;
  until: string; // "YYYY-MM-DD" — 이 날짜가 지난 규칙은 만료(서버는 기본 목록에서 숨긴다)
}

// DELETE /v1/recurrings/{id} 응답(계약 v2.3) — service.go RecurringDeleteResult와 1:1
// (json 태그: cancelled·kept). 종전 204(빈 응답)에서 **200 {cancelled, kept}**로 바뀌었다.
//
// 규칙을 지우면 서버가 그 규칙이 만든 **미래 confirmed 예약을 함께 취소**한다(무차감 —
// CancelAtomic만 쓰고 원장을 남기지 않아 노쇼 유예가 소진되지 않는다). 이 두 숫자가 어드민이
// 회원에게 "무엇이 사라졌는지" 알릴 유일한 근거다 — v1엔 회원 통보 채널이 없어 대표가 직접
// 연락한다. 응답을 버리면(req<void>) 대표는 회원 전화를 받고서야 안다.
export interface RecurringDeleteResult {
  cancelled: number; // 함께 취소한 미래 confirmed 예약 수
  kept: number; // 남긴 예약 수(이미 지난 회차 · keep_bookings=true로 남긴 미래 회차)
}

// ── Homework ────────────────────────────────────────────────────────────
export type HomeworkScope = "individual" | "my_members" | "center_notice";
export type HomeworkScheduleType = "once" | "weekly";

export interface HomeworkItem {
  name: string;
  sets?: number | null; // "걷기 30분"처럼 세트 개념이 없는 항목도 있어 optional
  reps: string; // "15"(횟수) 또는 "30분"(시간형) — 계약에 타입 명시 없어 자유 텍스트로 수용
  note: string;
}

export interface HomeworkSchedule {
  type: HomeworkScheduleType;
  days: Weekday[];
  from: string;
  to: string;
}

export interface Homework {
  id: string;
  trainer_id: string;
  scope: HomeworkScope;
  target_member_ids: string[];
  excluded: string[]; // 부상 플래그로 자동 제외된 member_id 목록(P39)
  items: HomeworkItem[];
  schedule: HomeworkSchedule;
}

export interface HwCheck {
  member_id: string;
  hw_id: string;
  date: string;
  done: boolean[];
}

// ── WorkoutLog(수업 기록, v1.4) ─────────────────────────────────────────
// 코어 루프 "예약→수업기록"의 마지막 조각(P29 30초 기록). reps는 HwItem과 동일 규약의
// 문자열("10-12"·"30초"), weight_kg는 숫자(0 = 자중/해당 없음 — 진행 그래프 후속 대비).
export interface Exercise {
  name: string;
  sets: number;
  reps: string;
  weight_kg: number;
  note: string;
}

export interface WorkoutLog {
  id: string;
  member_id: string;
  trainer_id: string;
  booking_id?: string; // 연결된 예약(선택 — 예약 밖 세션도 기록 가능, 백엔드 omitempty)
  date: string; // "2026-08-22"
  title: string; // 생략 시 서버 기본 "1:1 PT"
  exercises: Exercise[]; // 계약 v1.4: 항상 배열(null 없음)
  coach_note: string;
}

// ── Staff ───────────────────────────────────────────────────────────────
export type StaffRole = "owner" | "trainer";
export type PayoutType = "per_session" | "rate";

export interface Payout {
  type: PayoutType;
  value: number;
}

// v1.6: 트레이너 프로필 — 필드 구성은 시장 표준 조사(work_log/P05)에서 도출.
// 전 필드 회원 열람 전제의 공개 데이터(payout 마스킹 P13과 무관). 항상 객체(null 금지)·배열은 항상 [].
export interface StaffProfile {
  photo_url: string; // 외부 이미지 URL(http/https만 · ≤2048자). 빈 값 = Staff.color 배경 이니셜 아바타 폴백
  title: string; // 직함 ≤40자 (예: "헤드 트레이너")
  career_years: number; // 경력 연차 0~50 (0=미표기)
  specialties: string[]; // 전문분야 태그 — 원소 ≤80자·≤20개(아래 두 배열도 동일 규약)
  certifications: string[]; // 자격증
  awards: string[]; // 수상·선수 경력
  bio: string; // 소개문 ≤500자
}

// v2.0(P08 직원 생애주기): 하드 삭제 대신 상태 전이. "inactive"만이 명시적 퇴사이고
// 필드 부재·빈 값은 재직으로 읽는다(서버 domain.Staff.IsActive와 동형 — format.ts isStaffActive).
export type StaffStatus = "active" | "inactive";

export interface Staff {
  uid: string;
  role: StaffRole;
  name: string;
  color: string;
  payout: Payout;
  offdays: string[];
  profile: StaffProfile; // v1.6 — GET /v1/staff 응답에 항상 포함(하위호환 추가)
  // v2.0 — GET /v1/staff는 inactive도 계속 반환한다(이름 해석을 잃으면 회원·스케줄·정산의
  // uid 참조가 통째로 붕괴한다). 필터는 클라이언트가 이 필드로 한다.
  status: StaffStatus;
  // 퇴사 시각(RFC3339). 서버가 기록하며 inactive일 때만 실린다(백엔드 omitempty).
  left_at?: string | null;
}

// v2.0 PUT /v1/staff/{uid} — **머지 시맨틱**(보낸 필드만 갱신). status는 의도적으로 없다:
// 상태 전이는 deactivate/reactivate 전용 동사만 담당하고, 바디에 실으면 서버가 400을 낸다.
export interface StaffUpdateRequest {
  name?: string;
  color?: string;
  payout?: Payout;
  role?: StaffRole;
}

// 클라이언트 내부 공통 표현 — "어느 예약이 언제인가" 한 짝.
//
// 서버는 같은 정보를 두 이름으로 준다: 퇴사 blockers는 BlockedBooking{id, slot_key},
// 이관 결과는 StaffTransferConflict{booking_id, slot_key}. **와이어 형태는 서버 소관이라 바꿀 수
// 없지만**(양쪽 다 계약에 박혀 있다) 두 모양이 화면 안까지 그대로 흘러들면 정렬·라벨러·목록
// 컴포넌트가 각각 두 벌이 된다(실제로 퇴사 창과 이관 창이 서로 다른 라벨 함수를 들고 있었다).
// 응답이 들어오는 지점에서 이 하나로 모은다(toBookingRef).
export interface BookingRef {
  id: string; // 예약 문서 id
  slot_key: string; // "20260828-15"(YYYYMMDD-HH)
}

// v2.1: blockers.bookings의 원소 — id만 주던 것에 slot_key가 붙었다(백엔드 api.BlockedBooking).
// 서버는 blockers를 만드는 시점에 Booking을 손에 들고 있어 새로 캐는 값이 아니다. 어드민은 이
// 필드 덕에 "무엇을 옮겨야 하는지"를 사람이 읽는 시각으로 그리면서 예약 목록 재조회를 없앤다.
// 와이어 키가 내부 표현과 이미 같아서 별칭으로 둔다(이관 충돌은 toBookingRef로 맞춘다).
export type BlockedBooking = BookingRef;

// v2.0 POST /v1/staff/{uid}/deactivate 409 본문의 blockers — 퇴사를 막는 담당 잔여물의 **실제 ID**다
// (회원 id · 패스 id · 고정 스케줄 id · 예약). 화면이 이름·시각으로 해석해 보여줘야 한다.
// v2.1: bookings만 객체 배열로 바뀌었다(나머지 셋은 그대로 id 배열 — 서버가 그 엔티티들은
// 수집 시점에 id만 들고 있고, 어드민이 이미 회원·고정 스케줄 캐시로 이름을 풀 수 있다).
export interface StaffBlockers {
  members: string[];
  passes: string[];
  recurrings: string[];
  bookings: BlockedBooking[];
}

// v2.0 POST /v1/staff/{uid}/transfer 응답. conflicts = 인수자가 같은 슬롯에 이미 수업이 있어
// **옮기지 못한** 예약(트레이너 동시 1건 규칙을 이관이 우회하지 않는다) — 남아서 퇴사를 계속 막는다.
// 키 이름만 blockers와 다르다(booking_id vs id) — 화면에 넣기 전에 toBookingRef로 맞춘다.
export interface StaffTransferConflict {
  booking_id: string;
  slot_key: string;
}

// 이관 충돌 → 내부 공통 표현. 서버가 갈라놓은 두 이름을 여기 한 줄에서만 만난다.
export const toBookingRef = (c: StaffTransferConflict): BookingRef => ({
  id: c.booking_id,
  slot_key: c.slot_key,
});

export interface StaffTransferMoved {
  members: number;
  passes: number;
  recurrings: number;
  bookings: number;
}

export interface StaffTransferResult {
  moved: StaffTransferMoved;
  conflicts: StaffTransferConflict[];
}

// v1.8: POST /v1/staff 요청 바디(owner 전용 — 트레이너 초대). 응답은 Staff 재사용.
// color 생략 = 서버가 기본색 배정 · payout 생략 = 미설정(대표는 정산 개념이 없어 항상 생략).
// 비밀번호는 서버가 임시로 만들고 응답에 담지 않는다 — 초대는 클라이언트가 이어 보내는
// 비밀번호 설정 메일(sendPasswordResetEmail)로 완결된다(Settings.tsx InviteStaffModal).
export interface CreateStaffRequest {
  name: string;
  email: string;
  role: StaffRole;
  color?: string;
  payout?: Payout;
}

// ── Contract(전자계약) ──────────────────────────────────────────────────
// v1.1 정합 패치(API계약_v1.md §v1.1 정합 패치)에서 확정된 엔티티. 추가결제 플로우:
// 회원권 발급(POST /v1/passes) → 계약 자동 생성(sent) → 결제 기록(POST /v1/payments, 분할 가능).
// 어드민 회원 상세("계약·결제" 섹션)에서 원스톱으로 처리한다.
// v1.5: voided(패스 환불로 거래 해지 — 미서명 계약 자동 무효, 종단 상태) 추가.
// refunded 패스엔 계약 생성·발송·서명이 모두 400. 패스당 유효(비voided) 계약은 1건.
export type ContractStatus = "draft" | "sent" | "signed" | "voided";

export interface Contract {
  id: string;
  member_id: string;
  pass_id: string;
  product: string;
  paid_amount: number;
  // v1.5: 생성 시점 센터 정책의 위약금율 스냅샷(0~1 소수) — 환불 정산은 회원이 동의한 이 요율을
  // 쓴다(이후 정책 변경 비소급). null = 레거시(v1.5 이전 계약 — 스냅샷 없음, 정산 시 현재 정책
  // 폴백 — 백엔드 refundBasis) · 0 = 회원이 동의한 0%. 둘은 다른 상태다.
  penalty_rate: number | null;
  status: ContractStatus;
  sent_at: string | null; // 마지막 발송 시각(재발송 시 갱신)
  // v1.5: 최초 서명 요청 시각(한 번만 기록) — 재발송이 최초 고지 증적을 지우지 않는다.
  first_sent_at: string | null;
  signed_at: string | null;
  signer_ip: string | null;
  sha256: string | null;
  pdf_path: string | null;
}

// ── Payment ─────────────────────────────────────────────────────────────
export type PaymentMethod = "card" | "cash" | "transfer";

export interface Installment {
  due: string;
  amount: number;
  paid_at: string | null;
  // v1.5: 청구 종결 시각 — 패스 환불로 거래가 정산 종료돼 더 이상 수납하지 않는 회차.
  // 삭제가 아닌 표식(원장주의). 백엔드 omitempty — 종결 아닌 회차엔 필드 자체가 없다.
  // 종결 회차는 납부 처리 불가(서버 400) — 미수 집계에서도 제외된다.
  waived_at?: string | null;
}

export interface Payment {
  id: string;
  member_id: string;
  pass_id: string;
  method: PaymentMethod;
  total: number;
  installments: Installment[];
  channel: string;
}

// ── 체형 분석 ───────────────────────────────────────────────────────────
// 포즈는 **회원마다 다르다**(계약 v2.10) — 대표가 순서·구성을 정하고 커스텀 포즈를 만든다.
// 그래서 union이 아니라 string이다. 이미 찍힌 사진의 포즈가 현재 시퀀스에 없을 수 있고,
// 그 사진도 계속 보여야 하므로 타입으로 좁히면 안 된다.
export type BodyPose = string;

/// 레거시 4종 라벨 — 시퀀스에서 빠진 옛 포즈의 이름을 복원하는 폴백.
export const BODY_POSE_LABEL: Record<string, string> = {
  stand: "차렷",
  tpose: "T자",
  fold: "전굴",
  ohsquat: "OH스쿼트",
};

/// 계약 v2.10 — `{key, label}`. key는 Storage 파일명 조각이라 서버가 슬러그를 강제한다
/// (`^[a-z0-9_]{1,24}$` — 하이픈은 파일명 구분자라 금지).
export interface PoseSpec {
  key: string;
  label: string;
}

/// 포즈 key → 표시명: 회원 시퀀스 → 레거시 맵 → **raw key**.
/// 마지막 폴백이 핵심이다 — 모르는 key를 숨기거나 다른 포즈로 떨어뜨리면 그 사진이
/// 사라지거나 남의 포즈에 섞인다(체형사진은 삭제 API가 없어 안 보이면 영영 못 본다).
export function poseLabel(key: string, sequence: PoseSpec[] = []): string {
  return sequence.find((p) => p.key === key)?.label ?? BODY_POSE_LABEL[key] ?? key;
}

/// 서버 DefaultBodyPoses와 같은 순서·같은 라벨(구서버 대비 폴백).
export const DEFAULT_BODY_POSES: PoseSpec[] = [
  { key: "stand", label: "차렷" },
  { key: "tpose", label: "T자" },
  { key: "fold", label: "전굴" },
  { key: "ohsquat", label: "OH스쿼트" },
];

/// 서버 검증 미러(measurement/member.go) — 왕복 전에 칸 단위로 이유를 보여주기 위한 것.
export const POSE_KEY_RE = /^[a-z0-9_]{1,24}$/;
export const POSE_MAX_COUNT = 8;
export const POSE_LABEL_MAX = 12;
export type BodyDirection = "front" | "side" | "back";

export interface BodyPhoto {
  id: string;
  member_id: string;
  pose: BodyPose;
  direction: BodyDirection;
  date: string;
  storage_path: string;
  blurred: boolean;
}

export interface Inbody {
  id: string;
  member_id: string;
  date: string;
  weight: number;
  smm: number;
  bfm: number;
  pbf: number;
  vfl: number;
  bmr: number;
  // [v2.9] 이 기록을 누가 넣었나 — "member_self"(회원이 앱에서 셀프 입력) | "staff"(어드민/
  // 데스크) | ""(v2.9 이전 레코드 — 서버가 백필하지 않는다). **응답 전용 필드**다: 요청에
  // 실으면 서버 decodeJSON의 DisallowUnknownFields가 400으로 막는다(삭제 권한의 근거라
  // 서버가 Principal로 판정 — domain/measurement.go 주석).
  source: "member_self" | "staff" | "";
}

// ── Stats ───────────────────────────────────────────────────────────────
export interface MonthlyRevenue {
  month: string;
  amount: number;
}

export interface TrainerStat {
  uid: string;
  // v2.0 — inactive 행은 해당 기간에 활동(sessions>0 또는 revenue>0)이 있을 때만 포함된다.
  // 표가 "퇴사자인데 왜 아직 보이는지"를 스스로 설명할 수 있게 상태를 함께 준다.
  status: StaffStatus;
  name: string;
  revenue: number;
  sessions: number;
  rereg_rate: number;
  rereg_n: number;
  rereg_d: number;
  // v2.1: 행 단위 분모(백엔드 domain.TrainerStats.NoshowD/HwD — json 키는 top-level Stats와 동일).
  // 행에서는 top-level보다 분모가 훨씬 자주 0이다(이번 기간에 수업이 없던 코치). 분모 없이 비율만
  // 보면 그 코치가 "노쇼 0.0%"로 표의 최우수처럼 보인다 — 실제로는 비교 자체가 불가능한 행이다.
  // optional인 이유는 Stats.noshow_d와 같다(v2.1 이전 서버 = 미상).
  noshow_rate: number;
  noshow_d?: number;
  hw_rate: number;
  hw_d?: number;
}

export interface Stats {
  active_members: number;
  registered: number;
  rereg_rate: number;
  rereg_n: number;
  rereg_d: number;
  unassigned: number;
  long_absent: number;
  expiring: number;
  monthly: MonthlyRevenue[];
  ytd: number;
  target: number;
  noshow_rate: number;
  // v2.1: 비율의 분모. rereg_n/rereg_d 선례를 노쇼·홈워크로 확장했다. domain.Rate()가 분모 0에
  // 0을 돌려주므로 비율만 보면 "성과 0"과 "모수 없음"이 같은 0%다 — 신규 센터의 "아직 집계할 게
  // 없음"이 성과 실패로 읽힌다. **0이면 화면은 "0%"가 아니라 "—"를 쓴다**(format.ts ratioState).
  //
  // 계약상 필수 필드(서버가 omitempty를 붙이지 않는다)인데 **optional로 선언한 이유**: 0과
  // 필드 부재는 화면에서 정반대 뜻이라(집계 대상 없음 vs 구버전 서버라 미상) 그 구분이 이 앱의
  // 표시 정책 자체다. 필수로 못박으면 `d === undefined` 비교가 타입 에러가 되어, 구버전 응답에서
  // 런타임 undefined가 0으로 뭉개진 채 "집계 대상이 없다"는 단정으로 새어 나간다.
  noshow_d?: number; // 집계 대상 예약 수(완료 + 노쇼)
  hw_rate: number;
  hw_d?: number; // 집계 대상 홈워크 배정 수
  // v1.4 추가 필드
  sessions: number; // 완료 세션 수(스코프 내 — 트레이너 scope=me면 본인 정산 근거)
  // v1.5 재정의: unpaid_* = "연체"(due 경과·미납·미종결 회차)만 — due 당일은 아직 연체 아님.
  // 매출(monthly/ytd/by_trainer)은 환불 거래 제외(순매출).
  unpaid_total: number; // 연체 미수금 합계(원, owner 전용)
  unpaid_count: number; // 연체 회차가 있는 결제 건수(owner 전용)
  upcoming_total: number; // 미도래 미납 합계(due 전 — 연체 아님, owner 전용, v1.5 신규)
  by_trainer?: TrainerStat[]; // owner 전용(P45) — trainer 스코프 응답엔 생략됨
}

// ── /v1/me ──────────────────────────────────────────────────────────────
export interface Me {
  uid: string;
  role: Role;
  center_id: string;
  member_id?: string;
  // v2.2: 화면에 띄울 본인 이름(staff면 Staff.name · 연결된 member면 Member.name).
  // **서버가 best-effort로 채운다** — 이름 조회가 실패해도 /v1/me 자체는 성공하고 이 필드만
  // 빠진다(백엔드 omitempty · api.MeResponse.Name). 그래서 optional은 "구버전 서버 대비"가
  // 아니라 **정상 경로에서도 없을 수 있다**는 뜻이다: 이 필드 하나로 폴백을 걷어내면 그 순간
  // 헤더가 빈칸이 된다. 우선순위 1순위로만 쓰고 기존 폴백 사슬은 그대로 둔다(firstNonEmpty).
  name?: string;
}

// ── 가입 매칭(P48) ──────────────────────────────────────────────────────
export interface JoinMatchResult {
  member?: Member;
  needs_confirm: boolean;
}

// ── 환불 계산기(P5) ─────────────────────────────────────────────────────
// v1.5: 단가·이용분·위약금은 계약가 기준으로 산출하되, 환불액은 실수납(paid_sum)에서만 나간다
// — refund = max(paid_sum − usage − penalty, 0). refund-quote·refund 실행 응답 동일 형식.
export interface RefundQuote {
  per_session: number;
  usage: number;
  penalty: number;
  // 정산 기준이 된 실수납액(납부 완료 회차 합) — 분할 미완납이면 계약가(paid_amount)보다 작다.
  // 결제 기록이 아예 없는 레거시 패스는 계약가 폴백.
  paid_sum: number;
  refund: number;
  /**
   * 환불이 **함께 취소하는** 미래 확정 예약 건수(v2.14).
   *
   * 환불은 돈만 움직이는 게 아니라 회원의 앞으로 잡힌 수업을 통째로 지운다. 종전 확인
   * 문구는 그 사실을 말하지 않았고, 서버에 푸시가 없어 회원은 앱을 열어야 알았다.
   * 견적(refund-quote)과 실행 응답이 **같은 판정**으로 세므로 예고한 수와 실제가 갈리지 않는다.
   */
  cancelled_bookings: number;
}

// ── 환불 실행(v1.4) — POST /v1/passes/{id}/refund 응답 ──────────────────
// 견적(quote)과 달리 상태를 바꾼다: 원장 refund(잔여 0 마감) + status=refunded 전이.
export interface RefundExecuteResult {
  pass: Pass;
  quote: RefundQuote;
}

// ═══════════════════════════════════════════════════════════════════════
// 요청 바디 타입 — 응답 엔티티와 **겸용하지 않는다**
// ═══════════════════════════════════════════════════════════════════════
// 백엔드의 모든 쓰기 핸들러는 decodeJSON(= json.Decoder + DisallowUnknownFields,
// backend/internal/api/util.go)으로 바디를 읽는다. 서버 요청 구조체에 **없는 키가 하나라도**
// 실리면 값이 빈 배열이어도 400 "지원하지 않는 필드가 포함돼 있어요"로 요청 전체가 죽는다.
//
// 그래서 `Partial<엔티티>`를 요청 타입으로 쓰면 안 된다. 엔티티에는 서버가 **응답에만** 싣는
// 필드(id·서버 파생값)가 있어 오타가 아니라 "있는 필드"로 컴파일을 통과하고, 런타임에서만
// 400이 난다. 실제 사고: Homework.excluded(부상 자동제외 **결과** — 서버 파생값)를 배정
// 요청에 실어 보내 Home Work 배정이 어떤 입력으로도 성공하지 못했다. 타입은 정상이었다.
//
// 아래 타입들은 backend/internal/api/service.go의 *CreateRequest 구조체 json 태그와 1:1이다.
// 서버 구조체가 바뀌면 여기도 같이 바꾼다.
//
// 여기 없는 쓰기 경로는 요청 타입이 이미 인라인으로 좁게 박혀 있거나(passes·bookings·
// recurrings·contracts·hw-checks·workout-logs·staff·center — api.ts 시그니처 참고),
// 서버가 **엔티티 자체를 디코딩 대상으로** 쓴다(POST/PUT /v1/members = domain.Member —
// 엔티티의 모든 키가 곧 허용 키라 Partial<Member>가 구조적으로 안전한 유일한 경우다).

// POST /v1/homeworks — service.go HomeworkCreateRequest.
// **excluded는 요청 필드가 아니다**(서버가 ResolveTargets로 계산해 응답에만 싣는다).
export interface HomeworkCreateRequest {
  trainer_id: string;
  scope: HomeworkScope;
  // 배정 **후보** member_id 목록. 서버가 이 후보에서 부상 플래그 회원을 걸러 최종 target을
  // 만든다(domain.ResolveTargets). 응답 엔티티의 동명 필드는 "걸러진 결과"라 의미가 다르다 —
  // 이미 걸러낸 목록을 후보로 보내면 아래 include로 되살릴 대상이 후보에 없어 무시된다.
  target_member_ids: string[];
  // 부상 자동제외를 뒤집어 강제 포함할 member_id(수동 포함). 화면의 "(포함)" 칩이 이 키로 나간다.
  // 서버는 제외를 자기가 다시 계산하므로, 이 필드 없이는 화면에서 켠 포함이 저장 시 사라진다.
  include: string[];
  items: HomeworkItem[];
  schedule: HomeworkSchedule;
}

// POST /v1/payments — service.go PaymentCreateRequest(id 없음).
export interface PaymentCreateRequest {
  member_id: string;
  pass_id: string;
  method: PaymentMethod;
  total: number;
  installments: Installment[];
  channel: string;
}

// POST /v1/body-photos — service.go BodyPhotoCreateRequest(id 없음).
export interface BodyPhotoCreateRequest {
  member_id: string;
  pose: BodyPose;
  direction: BodyDirection;
  date: string;
  storage_path: string;
  blurred: boolean;
}

// POST /v1/inbody — service.go InbodyCreateRequest(id 없음). ⚠ 응답의 source를 여기 실으면
// DisallowUnknownFields 400 — 서버가 Principal로 판정해 채운다(v2.9). 이 8키가 허용의 전부다.
export interface InbodyCreateRequest {
  member_id: string;
  date: string;
  weight: number;
  smm: number;
  bfm: number;
  pbf: number;
  vfl: number;
  bmr: number;
}

// ═══════════════════════════════════════════════════════════════════════
// 계약 확장 가정(GAP) — API계약_v1.md가 조회 엔드포인트를 명시하지 않은 부분.
// README.md "정직한 갭" 항목과 함께 백엔드 확정 필요.
// ═══════════════════════════════════════════════════════════════════════

// [가정 1] GET /v1/members 응답에 회원권 목록이 포함된다고 가정.
// 근거: 계약에 "회원권 목록 조회" 단독 엔드포인트가 없음(POST /v1/passes는 발급만).
// 회원 상세 드로어·예약 생성 모달(패스 선택)에 회원권 데이터가 반드시 필요해
// 회원 목록 응답이 회원+회원권을 함께 반환하는 것으로 가정했다.
export interface MemberWithPasses extends Member {
  passes: Pass[];
}

// [가정 2] GET /v1/join/requests — 가입 요청 승인 리스트(설정 화면·P48 ③폴백)를
// 보여주려면 대기 중 요청 목록 조회가 필요한데 계약엔 POST(요청·승인)만 있고
// 목록 조회가 없다. POST /v1/join/request의 대칭 조회로 추정.
export interface JoinRequest {
  id: string;
  name: string;
  phone: string;
  center_id: string;
  requested_at: string;
}

// [가정 3] GET /v1/hw-checks?hw_id= — Home Work "이번 주 완료율" 표시에 필요.
// 계약엔 POST /v1/hw-checks(회원 앱에서 체크 제출)만 있고 조회가 없어,
// 동일 리소스의 대칭 조회 엔드포인트가 있다고 가정했다.
// (반환 타입은 HwCheck[] 그대로 재사용)

// (구 [가정 4] → v1.4 계약 확정) GET /v1/center {center_id, policy} + PUT /v1/center {policy}.
// 백엔드 domain.Policy json 태그와 1:1. member에게도 공개되나 revenue_target은 owner만
// 실값(비-owner 응답은 0). 홀딩 상한은 -1 = 무제한.
// 위약금율 상한 — 백엔드 domain.MaxPenaltyRate 미러(약관규제법 §8 리스크). **정책 상한이자
// 집행 상한**이다: 서버 Policy.Validate가 초과 저장을 거부하고, 계약 스냅샷·환불 공제·회원 앱이
// 전부 이 안의 값을 쓴다. 종전엔 어드민이 100%까지 받고 서버는 저장까지 성공시켰는데 실제
// 공제만 10%로 캡돼, 회원이 30% 조항에 서명하고 10%만 공제되는 계약서가 발행됐다(P14 C1).
export const MAX_PENALTY_RATE = 0.1;
export const MAX_PENALTY_PCT = MAX_PENALTY_RATE * 100;

export interface CenterPolicy {
  slot_capacity: number; // 시간당 최대 팀 수(1~10)
  cancel_cutoff_hours: number; // 취소 마감(0~168h). **즉시·소급** — 이미 잡힌 예약의 취소에도 적용
  grace_once: boolean; // 노쇼 최초 1회 유예
  penalty_rate: number; // 0~MAX_PENALTY_RATE 소수(0.1 = 10%)
  revenue_target: number; // 연 매출 목표(원, owner 전용 값)
  rereg_window_days: number; // 재등록 인정 기간(만료 후 N일)
  long_absent_days: number; // 장기미출석 기준일
  expiring_days: number; // 만료임박 기준일
  max_holds_per_pass: number; // 패스당 홀딩 최대 횟수(-1 = 무제한)
  max_hold_total_days: number; // 패스당 홀딩 총 일수 상한(-1 = 무제한)
}

// [v2.13] 사업자 정보 — 백엔드 domain.Business json 태그와 1:1.
// GET /v1/center {center_id, policy, business} · PUT /v1/center {business}(owner 전용).
//
// **policy 안이 아니라 옆에 두는 이유**(백엔드 domain/business.go 주석 미러): policy는 용량·컷오프·
// 위약금율처럼 서비스 동작을 바꾸는 운영 다이얼이고, 이쪽은 동작을 하나도 바꾸지 않는 법적 신원이다.
// 한 객체로 섞으면 PolicyEditForm의 "바뀐 필드만 저장" 비교가 중첩 객체를 참조 비교해 늘 "바뀜"으로
// 읽어, patch로 좁힌 의미(P14 M5)가 그 자리에서 도로 사라진다.
//
// 12칸이 전부 채워져야 이용약관·개인정보처리방침·민감정보 동의·계정 삭제 안내 4개 문서가 초안을
// 벗는다. 비어 있는 것 자체는 오류가 아니다(아직 등록 전) — 서버도 **채워진 칸의 형식만** 본다.
export interface CenterBusiness {
  biz_name: string; // 사업자명(상호)
  ceo_name: string; // 대표자명
  biz_reg_no: string; // 사업자등록번호 — 서버가 저장 시 ###-##-#####로 정규화해 되돌려준다
  address: string; // 사업장 주소
  phone: string; // 대표 전화 — 02·031·1544가 정상이라 회원 휴대폰(010)과 다른 규칙을 쓴다
  email: string; // 대표 이메일
  privacy_officer_name: string; // 개인정보 보호책임자 성명(개인정보보호법 §31 — 처리방침 필수 기재)
  privacy_officer_title: string; // 개인정보 보호책임자 직책
  privacy_officer_email: string; // 개인정보 보호책임자 이메일
  privacy_dept: string; // 권리행사(열람·정정·삭제) 접수 부서명
  privacy_manager: string; // 접수 담당자 성명
  effective_date: string; // 약관 시행일(YYYY-MM-DD) — 없으면 문서는 "시행 전 초안"이다
}

// complete — **서버가 계산해 내려주는 파생값**(api.BusinessView). 이 판정 하나로 법정 문서 4장이
// "시행 중"과 "초안" 사이를 오간다. 층마다 다시 세면 어느 문서는 시행 중이고 어느 문서는 초안인
// 상태가 만들어지므로, 화면은 세지 않고 **받아 쓴다**(위약금율이 네 자리에서 다른 숫자를 말하던
// P14 C1과 같은 모양의 결함이다). 저장 요청에는 실으면 안 된다 — api.ts pickBusiness 주석 참고.
export type CenterBusinessView = CenterBusiness & { complete: boolean };

/// 12칸의 한국어 라벨. 폼·미기재 안내·오류 문구가 **같은 이름으로 같은 칸을 가리키게** 하는 단일
/// 출처다(서버 domain.businessFields 미러). 라벨이 화면마다 다르면 대표는 "대표 전화"와 "센터
/// 번호"가 같은 칸인지 알 수 없다. 타입이 Record<keyof CenterBusiness, string>이라 칸을 늘리고
/// 라벨을 빠뜨리면 컴파일이 깨진다 — 목록이 조용히 어긋나지 않는다.
export const BUSINESS_FIELD_LABEL: Record<keyof CenterBusiness, string> = {
  biz_name: "사업자명(상호)",
  ceo_name: "대표자명",
  biz_reg_no: "사업자등록번호",
  address: "사업장 주소",
  phone: "대표 전화",
  email: "대표 이메일",
  privacy_officer_name: "개인정보 보호책임자 성명",
  privacy_officer_title: "개인정보 보호책임자 직책",
  privacy_officer_email: "개인정보 보호책임자 이메일",
  privacy_dept: "접수 부서명",
  privacy_manager: "담당자 성명",
  effective_date: "약관 시행일",
};

/// 폼 순서 = 위 선언 순서(JS 객체는 문자열 키의 삽입 순서를 보존한다). 순서를 별도 배열로 또 적지
/// 않는 이유는 두 목록이 언젠가 어긋나기 때문이고, 순서를 **고정**하는 이유는 "무엇이 남았는지"
/// 안내가 재조회마다 뒤바뀌면 대표가 같은 목록을 매번 처음부터 다시 읽게 되기 때문이다.
export const BUSINESS_FIELD_KEYS = Object.keys(BUSINESS_FIELD_LABEL) as (keyof CenterBusiness)[];

/// 서버 domain.Business.MissingFields 미러 — 아직 비어 있는 칸의 키 목록(폼 순서).
/// 저장된 값과 **편집 중인 값** 양쪽에 같은 규칙을 쓰려고 함수로 둔다: 카드 헤더 배지는 서버가 준
/// 저장 상태를, 폼 안내는 지금 화면의 값을 세야 하는데 세는 방법이 갈리면 두 곳이 다른 수를 말한다.
export function businessMissingFields(b: CenterBusiness): (keyof CenterBusiness)[] {
  return BUSINESS_FIELD_KEYS.filter((k) => b[k].trim() === "");
}

/// 서버 domain/business.go 상한 미러 — 값 자체보다 **어디서 왔는지**가 중요해 상수로 뽑는다.
/// 전부 법정 고지에 그대로 인쇄되는 값이라, 레이아웃을 깨는 길이를 서버가 먼저 막는다.
/// 길이를 셀 때는 반드시 `[...s].length`(코드 포인트)를 쓴다 — 서버가 `len([]rune(s))`로 세므로
/// UTF-16 단위인 `s.length`로 세면 이모지·일부 한자에서 서버가 받아주는 값을 화면이 먼저 막는다.
export const BUSINESS_NAME_MAX = 60; // 사업자명·대표자명·보호책임자 성명/직책·부서명·담당자명
export const BUSINESS_ADDRESS_MAX = 200; // 도로명 + 상세주소
export const BUSINESS_PHONE_MAX = 24;
export const BUSINESS_EMAIL_MAX = 120;
export const BUSINESS_REG_NO_DIGITS = 10; // 하이픈을 뺀 자릿수
/// 전화 자릿수 하한 8은 국내 최단(지역번호 없는 1544-0000), 상한 15는 E.164 상한.
export const BUSINESS_PHONE_DIGITS_MIN = 8;
export const BUSINESS_PHONE_DIGITS_MAX = 15;

/// 미등록 상태의 사업자 정보(12칸 공백 + complete:false) — **배포 순서가 어긋난 창을 받치는 값**.
///
/// 계약(v2.13 "배포 순서")은 서버를 먼저 올리라고 말하고, 그러면 business는 늘 온다. 하지만 그
/// 약속이 깨지는 유일한 순간(어드민이 서버보다 먼저 뜨는 배포)의 대가가 "사업자 정보 칸이 빈다"가
/// 아니라 **설정 화면 전체가 흰 화면**이다 — 직원·운영 정책·가입 승인까지 같이 죽는다. 없는 값을
/// 미등록과 **같은 모양**으로 접어 두면 그 순간이 장애가 아니라 "아직 등록 전"으로 보인다.
/// 12칸을 손으로 적는다 — 타입이 전 칸을 요구하므로 칸을 늘리면 여기서 컴파일이 깨진다
/// (Object.fromEntries로 만들면 그 검사가 사라진다. BUSINESS_FIELD_LABEL과 같은 이유다).
export const EMPTY_BUSINESS: CenterBusinessView = {
  biz_name: "",
  ceo_name: "",
  biz_reg_no: "",
  address: "",
  phone: "",
  email: "",
  privacy_officer_name: "",
  privacy_officer_title: "",
  privacy_officer_email: "",
  privacy_dept: "",
  privacy_manager: "",
  effective_date: "",
  complete: false,
};

export interface Center {
  center_id: string;
  policy: CenterPolicy;
  // v2.13 신설. 서버가 항상 채워 보낸다(미등록이면 12칸이 빈 문자열 + complete:false) —
  // optional로 두면 화면마다 다른 폴백을 짜 넣게 되고 "미등록"과 "아직 안 불러옴"이 섞인다.
  business: CenterBusinessView;
}
