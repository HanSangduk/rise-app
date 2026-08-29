// 백엔드 API 클라이언트(typed fetch). 기본 base = /api (vite proxy → localhost:8080).
// 인증(P06): Firebase 로그인 상태(auth.currentUser 존재)면 Authorization: Bearer <ID token>,
//            아니면 X-Dev-Role: owner|trainer|member + X-Dev-Uid(로컬 개발 — API계약_v1.md 명시).
//            둘이 동시에 성립하면 Bearer가 우선 — X-Dev 헤더는 아예 싣지 않는다(충돌 방지).
//
// ⚠ 계약 확장 가정이 붙은 메서드는 [가정 N] 주석으로 표시(src/lib/types.ts 하단 설명과 대응).
import { auth } from "./firebase";
import type {
  BodyPhoto,
  BodyPhotoCreateRequest,
  Booking,
  Center,
  CenterBusiness,
  CenterPolicy,
  Contract,
  CreateStaffRequest,
  Exercise,
  Homework,
  HomeworkCreateRequest,
  HwCheck,
  Inbody,
  InbodyCreateRequest,
  JoinMatchResult,
  JoinRequest,
  Ledger,
  Me,
  Member,
  MemberWithPasses,
  Pass,
  Payment,
  PaymentCreateRequest,
  RefundExecuteResult,
  RefundQuote,
  Recurring,
  RecurringDeleteResult,
  Role,
  Slot,
  Staff,
  StaffProfile,
  StaffTransferResult,
  StaffUpdateRequest,
  Stats,
  Weekday,
  WorkoutLog,
} from "./types";

// ||로 빈 문자열도 /api 폴백(??는 .env의 `VITE_API_BASE=` 빈 값을 그대로 통과시켜 프록시를 우회한다).
// 후행 슬래시는 제거해 path와 이중 슬래시가 되지 않게 한다.
const BASE = (import.meta.env.VITE_API_BASE || "/api").replace(/\/+$/, "");

// 로컬 개발 아이덴티티 — 로그인 화면(데모 버튼)이 세팅하고 이후 모든 요청에 실린다.
let devRole: Role | null = null;
let devUid: string | null = null;

function setDevIdentity(role: Role | null, uid: string | null) {
  devRole = role;
  devUid = uid;
}

// ── Firebase Auth 연동(P06) — 구 스텁 주석 자리의 실제 구현 ─────────────────
// getIdToken()은 SDK가 토큰을 캐시하고 만료 임박 시에만 갱신하므로 매 요청 호출해도
// 네트워크 왕복이 없다. 로그인 안 된 상태(null)면 빈 객체 → req()가 X-Dev 데모로 폴백.
async function authHeader(): Promise<{ Authorization?: string }> {
  const user = auth.currentUser;
  if (!user) return {};
  try {
    const token = await user.getIdToken();
    return { Authorization: `Bearer ${token}` };
  } catch {
    // 토큰 **갱신** 실패는 서버에 물어보기도 전에 세션이 끝났다는 뜻이다 — 퇴사 처리의 2차
    // 방어선(Firebase 계정 Disabled + RevokeRefreshTokens)이 정확히 여기서 걸린다.
    // 그대로 두면 401을 받을 기회가 없어 화면이 안 닫히므로 401과 같게 다룬다:
    // 세션을 정리하고 같은 모양(ApiError 401)으로 던져 호출부가 분기를 하나 더 갖지 않게 한다.
    onUnauthorized?.();
    throw new ApiError(STATUS_FALLBACK[401], 401);
  }
}

// 상태코드를 실어 나르는 에러 — 화면이 "409는 이미 등록된 이메일"처럼 코드별 카피를 쓸 수 있게
// 한다(같은 400이라도 서버 메시지가 항목별로 구체적인 경우엔 message를 그대로 노출).
// Error 서브클래스라 .message만 읽는 기존 호출부(ErrorState·인라인 표시)는 그대로 동작한다.
//
// data — 표준 {error} 위에 확장 필드를 얹어 보내는 응답의 파싱 결과(v2.0 퇴사 409의 blockers가
// 첫 사례). 재조회 없이 "무엇을 먼저 이관해야 하는지"를 그 자리에서 그리려면 본문이 필요하다.
export class ApiError extends Error {
  readonly status: number;
  readonly data: unknown;
  constructor(message: string, status: number, data?: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.data = data;
  }
}

// ── 401 인터셉터(v2.0) ──────────────────────────────────────────────────
// 퇴사 처리를 받으면 서버는 즉시 UserIndex를 강등하고 Firebase 계정을 잠그지만, 화면은
// isAuthed = !!me라 셸이 그대로 렌더되고 패널만 빨간 에러로 덮인다 — 세션을 정리할 주체가
// 없었다. api.ts는 React를 모르므로 콜백을 등록받고(auth.tsx가 부팅 시 1회 등록) 401에서만 부른다.
//
// **403은 부르지 않는다.** 403은 "로그인은 유효한데 이 기능은 권한 밖"이라는 정상 응답이기도
// 해서(트레이너가 owner 전용 API를 건드린 경우) 자동 로그아웃과 구분되지 않는다.
// 세션 무효는 401만이 말한다.
let onUnauthorized: (() => void) | null = null;

function setUnauthorizedHandler(fn: (() => void) | null) {
  onUnauthorized = fn;
}

const STATUS_FALLBACK: Record<number, string> = {
  400: "잘못된 요청이에요",
  401: "인증이 필요해요 — 다시 로그인해주세요",
  403: "권한이 없어요",
  404: "요청한 데이터를 찾을 수 없어요",
  409: "동시 처리 충돌 — 새로고침 후 다시 시도해주세요",
  500: "서버 오류가 발생했어요",
};

async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const headers = new Headers(init?.headers ?? { "Content-Type": "application/json" });
  const bearer = await authHeader();
  if (bearer.Authorization) {
    // Firebase 로그인 상태 — 우선순위: Firebase > 데모. X-Dev 헤더는 싣지 않는다(충돌 방지).
    headers.set("Authorization", bearer.Authorization);
  } else {
    if (devRole) headers.set("X-Dev-Role", devRole);
    if (devUid) headers.set("X-Dev-Uid", devUid);
  }
  // cache: "no-store" — 브라우저 HTTP 캐시를 완전히 우회한다. 전달 경로가 고장난 동안 나간
  // 캐시 가능 에러(Hosting 404가 max-age=3600을 달고 온 P34 실사고)가 브라우저에 눌러앉으면,
  // 서버를 고쳐도 이 클라이언트는 캐시된 에러를 재생하며 "서버가 죽었다"를 유지한다 —
  // 서버/CDN 설정과 무관하게 클라이언트에서 확정적으로 끊는 유일한 방어선이다.
  const res = await fetch(BASE + path, { ...init, headers, cache: "no-store" });
  // HTML 응답 = 백엔드가 아니라 **전달 경로**(Hosting 404 페이지, SPA 폴백이 /api를 삼킨 부분
  // 배포)의 응답이다. JSON.parse 실패나 "데이터 없음" 폴백으로 뭉개면 15시간짜리 오진이 된다
  // (P34 — 라우팅 유실이 "요청한 데이터를 찾을 수 없어요"로 표시됐다). 전용 문구로 가른다.
  const isJSON = (res.headers.get("content-type") ?? "").includes("application/json");
  if (!res.ok) {
    // 서버는 {"error":"한국어 메시지"}를 주는 것이 계약이지만, 프록시/게이트웨이가 낸
    // 비JSON 에러까지 영문 statusText로 노출하지 않도록 상태코드별 한국어 폴백을 둔다.
    let msg = STATUS_FALLBACK[res.status] ?? `요청에 실패했어요 (${res.status})`;
    let data: unknown;
    if (isJSON) {
      try {
        data = await res.json();
        const body = data as { error?: string };
        if (body?.error) msg = body.error;
      } catch {
        /* 에러 바디가 JSON이 아니면 상태코드 폴백 유지 */
      }
    } else {
      msg = "API 서버에 연결되지 않았어요 — 연결 경로 문제일 수 있어요. 잠시 후 다시 시도해주세요";
      // 다음 사고의 진단 시간을 줄이는 흔적 — 무엇이 왔는지(HTML 등) 앞부분만 남긴다.
      const text = await res.text().catch(() => "");
      console.error(`[api] 비JSON 에러 응답 (${res.status}) ${path}:`, text.slice(0, 200));
    }
    // 세션 정리는 던지기 **전에** — 화면이 에러를 처리하는 사이 셸이 남아 있지 않게 한다.
    if (res.status === 401) onUnauthorized?.();
    throw new ApiError(msg, res.status, data);
  }
  // 2xx인데 바디가 빈 응답(204 포함)은 undefined로 — res.json()의 SyntaxError가
  // 성공을 실패로 둔갑시키지 않게 한다.
  const text = await res.text();
  if (text && !isJSON) {
    // 200인데 HTML — SPA 폴백(** → /index.html)이 /api를 삼킨 상태다. res.ok라 에러 경로를
    // 안 타므로 여기서 안 끊으면 JSON.parse SyntaxError 원문이 화면에 그대로 뜬다.
    console.error(`[api] 2xx 비JSON 응답 ${path}:`, text.slice(0, 200));
    throw new ApiError("API 연결 경로에 문제가 있어요 — 관리자에게 알려주세요", 502);
  }
  return (text ? JSON.parse(text) : undefined) as T;
}

function qs(params: Record<string, string | number | undefined>): string {
  const s = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== "") s.set(k, String(v));
  }
  const str = s.toString();
  return str ? `?${str}` : "";
}

export const api = {
  setDevIdentity,
  setUnauthorizedHandler,

  // ── 인증 · 가입(P48) ────────────────────────────────────────────────
  me: () => req<Me>("/v1/me"),
  joinMatch: (phone: string) =>
    req<JoinMatchResult>("/v1/join/match", { method: "POST", body: JSON.stringify({ phone }) }),
  joinConfirm: (member_id: string, confirm: boolean) =>
    req<void>("/v1/join/confirm", { method: "POST", body: JSON.stringify({ member_id, confirm }) }),
  joinRequestSend: (center_id: string) =>
    req<void>("/v1/join/request", { method: "POST", body: JSON.stringify({ center_id }) }),
  joinApprove: (request_id: string) =>
    req<void>("/v1/join/approve", { method: "POST", body: JSON.stringify({ request_id }) }),
  // [가정 2] 대기 중 가입 요청 목록(설정 화면). types.ts JoinRequest 참고.
  joinRequests: () => req<JoinRequest[]>("/v1/join/requests"),

  // ── 회원 ────────────────────────────────────────────────────────────
  // [가정 1] 응답에 회원권(passes[])이 포함된다고 가정 — types.ts MemberWithPasses 참고.
  members: (params: { trainer?: string; q?: string } = {}) =>
    req<MemberWithPasses[]>(`/v1/members${qs({ trainer: params.trainer, q: params.q })}`),
  // Partial<Member>가 허용되는 유일한 쓰기 경로 — 서버가 엔티티(domain.Member) 자체를 디코딩
  // 대상으로 쓴다(handlers_members.go). 엔티티의 모든 키가 곧 허용 키라 unknown field가 없다.
  createMember: (m: Partial<Member>) =>
    req<Member>("/v1/members", { method: "POST", body: JSON.stringify(m) }),
  updateMember: (id: string, m: Partial<Member>) =>
    req<Member>(`/v1/members/${id}`, { method: "PUT", body: JSON.stringify(m) }),
  memberLedger: (id: string, pass?: string) =>
    req<Ledger[]>(`/v1/members/${id}/ledger${qs({ pass })}`),

  // ── 회원권(Pass) ────────────────────────────────────────────────────
  createPass: (p: {
    member_id: string;
    trainer_id: string;
    product: string;
    paid_amount: number;
    total_sessions: number;
    valid_from: string;
    valid_until: string;
  }) => req<Pass>("/v1/passes", { method: "POST", body: JSON.stringify(p) }),
  holdPass: (id: string, body: { from: string; to: string; reason: string }) =>
    req<Pass>(`/v1/passes/${id}/hold`, { method: "POST", body: JSON.stringify(body) }),
  resumePass: (id: string) => req<Pass>(`/v1/passes/${id}/resume`, { method: "POST" }),
  refundQuote: (id: string, used: number) =>
    req<RefundQuote>(`/v1/passes/${id}/refund-quote`, { method: "POST", body: JSON.stringify({ used }) }),
  // [v1.4] 환불 "실행"(owner 전용) — 견적 재계산 → 원장 refund(잔여 0 마감) → status=refunded.
  refundPass: (id: string, used: number) =>
    req<RefundExecuteResult>(`/v1/passes/${id}/refund`, { method: "POST", body: JSON.stringify({ used }) }),

  // ── 계약(전자계약, v1.1 정합 패치) ────────────────────────────────────
  // 생성(POST /v1/contracts)은 어드민이 부르지 않는다 — 발급(POST /v1/passes)이 서버에서 계약을
  // 함께 만든다. 소비처 0곳이던 createContract는 제거(P38). 백엔드 라우트는 유지(제품 결정 별도).
  contracts: (params: { member?: string; status?: string } = {}) =>
    req<Contract[]>(`/v1/contracts${qs({ member: params.member, status: params.status })}`),
  sendContract: (id: string) => req<Contract>(`/v1/contracts/${id}/send`, { method: "POST" }),

  // ── 예약(슬롯 3팀 · P35) ────────────────────────────────────────────
  slots: (date: string) => req<Slot[]>(`/v1/slots${qs({ date })}`),
  createBooking: (body: { slot_key: string; member_id: string; pass_id: string }) =>
    req<Booking>("/v1/bookings", { method: "POST", body: JSON.stringify(body) }),
  // [v1.5] waive=true — 스태프의 무차감 취소(운영 사유: recurring 정리·코치 사정 등).
  // 컷오프 경과 취소여도 노쇼 차감·유예 소진 없이 취소만 한다(member 요청에선 서버가 무시).
  cancelBooking: (id: string, opts: { waive?: boolean } = {}) =>
    req<void>(`/v1/bookings/${id}${opts.waive ? "?waive=true" : ""}`, { method: "DELETE" }),
  // 예약 목록(v1.1 정합 패치로 계약 확정 — owner=센터 전체, trainer=본인 분만).
  // 슬롯 그리드는 날짜별 GET /v1/slots를 쓰지만, 퇴사 blockers의 예약 id를 회원 이름·시각으로
  // 풀려면 날짜를 모르는 채로 id → 예약을 찾아야 한다(from=오늘로 미래 분만 받는다).
  bookings: (params: { member?: string; from?: string } = {}) =>
    req<Booking[]>(`/v1/bookings${qs({ member: params.member, from: params.from })}`),
  completeBooking: (id: string) => req<Booking>(`/v1/bookings/${id}/complete`, { method: "POST" }),
  noshowBooking: (id: string) => req<Booking>(`/v1/bookings/${id}/noshow`, { method: "POST" }),
  // 체크인(P44) — 대시보드 "✓ 체크인" 원탭. source=tap(트레이너 어드민 탭) | self_qr(회원 앱 스캔).
  checkin: (body: { source: "tap" | "self_qr"; booking_id?: string; qr_token?: string }) =>
    req<Booking>("/v1/checkin", { method: "POST", body: JSON.stringify(body) }),

  // ── 고정 스케줄(P47) ────────────────────────────────────────────────
  // [v1.4] 목록 조회(관리 UI) — owner=전체, trainer=본인 규칙만(서버 스코프), member 403.
  // [v2.3] include_expired=true — until이 지난 규칙까지 포함. 서버 기본값은 숨김인데, 숨기기만
  // 하면 관리 UI에서 **지울 방법이 없어** 유령 규칙이 쌓인다(그 정리용으로 열어 둔 파라미터).
  recurrings: (params: { includeExpired?: boolean } = {}) =>
    req<Recurring[]>(`/v1/recurrings${qs({ include_expired: params.includeExpired ? "true" : undefined })}`),
  createRecurring: (body: {
    member_id: string;
    trainer_id: string;
    pass_id: string;
    days: Weekday[];
    hour: number;
    until: string;
  }) => req<Recurring>("/v1/recurrings", { method: "POST", body: JSON.stringify(body) }),
  // [v2.3] 규칙 해제 — 204(빈 응답) → **200 {cancelled, kept}**. 서버가 그 규칙이 만든 미래
  // confirmed 예약을 함께 무차감 취소하므로(지난 회차는 이력이라 보존) 응답의 두 숫자를 반드시
  // 화면에 흘려야 한다(types.ts RecurringDeleteResult 주석).
  // keepBookings=true → ?keep_bookings=true: 예약은 그대로 두고 규칙만 지우는 옵트아웃.
  deleteRecurring: (id: string, opts: { keepBookings?: boolean } = {}) =>
    req<RecurringDeleteResult>(
      `/v1/recurrings/${id}${qs({ keep_bookings: opts.keepBookings ? "true" : undefined })}`,
      { method: "DELETE" },
    ),

  // ── 수업 기록(WorkoutLog, v1.4) ─────────────────────────────────────
  // member=본인 강제, trainer=본인 작성분, owner=전체. from은 "YYYY-MM-DD" 이후(포함) 필터.
  workoutLogs: (member?: string, from?: string) =>
    req<WorkoutLog[]>(`/v1/workout-logs${qs({ member, from })}`),
  // 스태프 전용(trainer는 본인 명의 강제 — owner가 대신 기록할 땐 trainer_id 필수).
  // date 생략=오늘, title 생략="1:1 PT" — 완료 처리 직후 30초 기록(P29).
  createWorkoutLog: (body: {
    member_id: string;
    trainer_id?: string;
    booking_id?: string;
    date?: string;
    title?: string;
    exercises: Exercise[];
    coach_note: string;
  }) => req<WorkoutLog>("/v1/workout-logs", { method: "POST", body: JSON.stringify(body) }),

  // ── Home Work(P39) ──────────────────────────────────────────────────
  homeworks: (member?: string) => req<Homework[]>(`/v1/homeworks${qs({ member })}`),
  // 요청 타입은 응답 엔티티(Homework)와 다르다 — types.ts HomeworkCreateRequest 주석 참고.
  // (excluded는 서버 파생값이라 실어 보내면 DisallowUnknownFields가 400으로 막는다.)
  createHomework: (h: HomeworkCreateRequest) =>
    req<Homework>("/v1/homeworks", { method: "POST", body: JSON.stringify(h) }),
  submitHwChecks: (body: { hw_id: string; date: string; done: boolean[] }) =>
    req<HwCheck>("/v1/hw-checks", { method: "POST", body: JSON.stringify(body) }),
  // [가정 3] hw_id별 체크 현황 목록(완료율 표시용).
  hwChecks: (hwId: string) => req<HwCheck[]>(`/v1/hw-checks${qs({ hw_id: hwId })}`),

  // ── 통계(P45) · 결제 ────────────────────────────────────────────────
  stats: (range: string, scope: "me" | "center") => req<Stats>(`/v1/stats${qs({ range, scope })}`),
  // [v1.1] 결제 목록(분할·미수 확인 — 회원 상세 "계약·결제" 섹션).
  // [v1.5] member 생략 = 전체 조회(owner=센터 전체, trainer=담당 패스 결제만 — 서버 스코프).
  // 대시보드 "결제 기록 없는 회원권" 집계에 쓴다.
  payments: (member?: string) => req<Payment[]>(`/v1/payments${qs({ member })}`),
  // [v1.5] 서버 검증 추가(합계=회차 합·음수·수단·회원-패스 소유 일치) — 실패 시 400 한국어 메시지.
  createPayment: (p: PaymentCreateRequest) =>
    req<Payment>("/v1/payments", { method: "POST", body: JSON.stringify(p) }),
  payInstallment: (paymentId: string, index: number) =>
    req<Payment>(`/v1/payments/${paymentId}/installments/${index}/pay`, { method: "POST" }),

  // ── 체형 분석 · 인바디 ──────────────────────────────────────────────
  bodyPhotos: (member: string) => req<BodyPhoto[]>(`/v1/body-photos${qs({ member })}`),
  createBodyPhoto: (b: BodyPhotoCreateRequest) =>
    req<BodyPhoto>("/v1/body-photos", { method: "POST", body: JSON.stringify(b) }),
  inbody: (member: string) => req<Inbody[]>(`/v1/inbody${qs({ member })}`),
  // [v2.9] 서버 검증: 6지표 범위+교차(400 한국어 문구) · 미래 측정일 400(KST) · 같은 회원·
  // 같은 날 중복 409. source는 **실으면 안 된다**(DisallowUnknownFields 400 — 서버가
  // Principal로 판정). 폼(BodyPhotos.tsx)이 같은 범위로 사전 검증해 400 왕복을 줄인다.
  createInbody: (b: InbodyCreateRequest) =>
    req<Inbody>("/v1/inbody", { method: "POST", body: JSON.stringify(b) }),
  // [v2.9] 인바디 삭제 — 오입력을 되돌리는 **유일한** 수단(PUT 없음 — 지우고 다시 입력).
  // 같은 날 재입력이 409로 막히므로 그날 오타 정정은 이 경로가 반드시 선행돼야 한다.
  // 응답 200 {"deleted":true}. 스코프는 서버 검사(스태프는 담당 회원 안에서만, 404/403 구분).
  deleteInbody: (id: string) => req<{ deleted: boolean }>(`/v1/inbody/${id}`, { method: "DELETE" }),

  // ── 직원 · 설정 ─────────────────────────────────────────────────────
  staff: () => req<Staff[]>("/v1/staff"),
  // [v1.8] 트레이너 초대 = 신규 스태프 생성(owner 전용). 서버가 Firebase 계정을 임시 비밀번호로
  // 만들되 응답에 담지 않으므로, 화면이 곧바로 비밀번호 설정 메일을 보내 초대를 완결한다.
  // 400(이름·이메일·role·payout 범위) / 403(owner 아님) / 409(이미 스태프·이미 회원 계정)는
  // ApiError.status로 구분해 화면에서 한국어 카피로 매핑한다.
  createStaff: (body: CreateStaffRequest) =>
    req<Staff>("/v1/staff", { method: "POST", body: JSON.stringify(body) }),
  setOffdays: (uid: string, offdays: string[]) =>
    req<Staff>(`/v1/staff/${uid}/offdays`, { method: "POST", body: JSON.stringify({ offdays }) }),

  // ── 직원 생애주기(v2.0, 전부 owner 전용) ─────────────────────────────
  // 정정 — **머지**: 보낸 필드만 갱신한다(안 보낸 정산 조건이 0으로 초기화되지 않게).
  // 400 값 범위 · 400 본인 role 변경(자기 강등 금지) · 409 마지막 활성 대표의 강등.
  updateStaff: (uid: string, patch: StaffUpdateRequest) =>
    req<Staff>(`/v1/staff/${uid}`, { method: "PUT", body: JSON.stringify(patch) }),
  // 담당 일괄 이관 — toUid ""는 "미배정으로 회수"라는 유효한 지시다(3계층에서 ""는 1급 상태).
  // 서버가 필드 누락과 구분하려고 포인터로 받으므로 항상 키를 실어 보낸다.
  // 409 인수자가 inactive · 400 to_uid == uid.
  transferStaff: (uid: string, toUid: string) =>
    req<StaffTransferResult>(`/v1/staff/${uid}/transfer`, {
      method: "POST",
      body: JSON.stringify({ to_uid: toUid }),
    }),
  // 퇴사 — leftAt 생략 = 지금. 선행 조건(담당 회원·활성 패스·미만료 고정 스케줄·미래 예약)이
  // 남아 있으면 409 + blockers(ApiError.data로 전달 — Settings의 퇴사 모달이 이름으로 푼다).
  deactivateStaff: (uid: string, leftAt?: string) =>
    req<Staff>(`/v1/staff/${uid}/deactivate`, {
      method: "POST",
      body: JSON.stringify(leftAt ? { left_at: leftAt } : {}),
    }),
  // 재입사 복원 — status=active · left_at 소거 · 권한/계정 복원. 400 이미 재직 중.
  reactivateStaff: (uid: string) => req<Staff>(`/v1/staff/${uid}/reactivate`, { method: "POST" }),
  // [v1.6] 트레이너 프로필 "통 교체"(owner 또는 본인 trainer — offdays와 동일 권한, member 403).
  // 폼이 항상 전 필드를 제출한다(머지 아님) — 빈 값으로 지우기가 자연스럽다. 범위 위반은 400 한국어.
  updateStaffProfile: (uid: string, profile: StaffProfile) =>
    req<Staff>(`/v1/staff/${uid}/profile`, { method: "PUT", body: JSON.stringify({ profile }) }),
  // (구 [가정 4] → v1.4 계약 확정) 센터 정책 조회 — member에게도 공개, revenue_target은 owner만.
  center: () => req<Center>("/v1/center"),
  // [v1.4] 운영 정책 편집(owner 전용). 범위 위반은 400 한국어 메시지 — 폼에 그대로 표시한다.
  //
  // **바뀐 필드만 싣는다**(서버는 머지 시맨틱 — service.UpdateCenterPolicy). 전 필드를 항상
  // 보내면 그 머지 보호가 무력화돼, 다른 창·다른 대표가 먼저 저장한 값을 내가 화면에 들고 있던
  // 낡은 값으로 통째로 되돌린다(P14 M5 — StaffEditModal이 이미 쓰는 patch 패턴과 같은 자리).
  updateCenterPolicy: (patch: Partial<CenterPolicy>) =>
    req<Center>("/v1/center", { method: "PUT", body: JSON.stringify({ policy: patch }) }),
  // [v2.13] 사업자 정보 편집(owner 전용) — 법정 고지 4문서가 인쇄하는 값. 형식 위반은 400 한국어.
  //
  // **12칸을 항상 전부 싣는다** — 서버가 통 교체이기 때문이다(updateCenterPolicy의 patch와 반대).
  // 근거는 updateStaffProfile과 같은 자리다: 폼이 늘 전 칸을 제출하고, **잘못 적은 칸을 비워서
  // 지우는 일**이 실제로 필요하다 — 머지였다면 한 번 들어간 오타를 지울 방법이 없다. 정책 쪽이
  // patch인 이유는 그쪽이 매일 만지는 운영 다이얼이라 동시 편집 충돌이 실재하기 때문인데,
  // 사업자 정보는 개업 때 한 번 넣고 상호·주소가 바뀔 때만 손대는 값이라 충돌 자체가 드물다.
  //
  // policy를 함께 싣지 않는다: 서버는 **보낸 덩어리만** 처리하므로(handlers_me.UpdateCenter)
  // 이 호출은 정책을 건드리지 않는다. 반대로 정책 저장도 사업자 정보를 밀지 않는다.
  // 응답은 GET /v1/center과 같은 모양(Center 전체)이라 캐시를 그대로 갈아끼울 수 있다.
  updateCenterBusiness: (business: CenterBusiness) =>
    req<Center>("/v1/center", { method: "PUT", body: JSON.stringify({ business }) }),
};
