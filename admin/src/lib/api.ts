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
  BodyPhotoListItem,
  BodyPhotoReconcileResult,
  Booking,
  Center,
  CenterBusiness,
  CenterFacility,
  CenterIdentity,
  CenterPolicy,
  CheckinQrToken,
  Contract,
  CreateStaffRequest,
  Exercise,
  Homework,
  HomeworkCreateRequest,
  HwCheck,
  Inbody,
  InbodyCreateRequest,
  ConsultRequest,
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
  StaffPhotoUploadRequest,
  StaffPhotoUploadResult,
  StaffProfile,
  StaffTransferResult,
  StaffUpdateRequest,
  Stats,
  Weekday,
  WorkoutLog,
  AdminCenter,
  CenterCreateBody,
  CenterCreated,
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
// transport — 백엔드가 아니라 **전달 경로**(Hosting 리라이트 유실·SPA 폴백이 /api를 삼킴)가
// 낸 실패라는 표시. 상류 502(Cloud Run 콜드스타트 등 일시적)와 달리 배포를 고치기 전까지
// 100% 결정적으로 실패하므로 **재시도하면 안 된다** — 재시도는 진단만 늦추고(백오프 대기)
// 요청 수를 4배로 만든다. main.tsx의 retry 술어가 이 플래그를 본다.
//
// code — 서버가 표준 {error} 옆에 실어 보내는 **기계 판독용 식별자**(계약 v2.28, 없으면 "").
// 사람이 읽는 문구(message)는 같은데 뜻이 다른 응답을 가르는 유일한 수단이다. 첫 사례가
// 라우터 404 `route_not_found`: 종전엔 "이 배포에 그 주소가 없다"(미배포)와 "그 id의 문서가
// 없다"(이미 처리됨·경합)가 status도 본문도 같아서, 어드민이 후자를 전자로 읽고 대표에게
// **"그동안은 승인만 처리하세요"라고 지시**했다 — 그 승인이 P55 C-2(회원 기록 전부 상실)다.
export class ApiError extends Error {
  readonly status: number;
  readonly data: unknown;
  readonly transport: boolean;
  readonly code: string;
  constructor(message: string, status: number, data?: unknown, transport = false, code = "") {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.data = data;
    this.transport = transport;
    this.code = code;
  }
}

// 라우터 404 식별자(계약 v2.28) — 서버 router.go NotFound 핸들러가 싣는 값과 **글자 단위로** 같아야 한다.
export const ROUTE_NOT_FOUND_CODE = "route_not_found";
// 파기 경계(STORAGE_BUCKET) 미구성 503의 식별자(계약 v2.28) — util.go codeMediaNotConfigured와 동일.
export const MEDIA_NOT_CONFIGURED_CODE = "media_not_configured";

// "이 배포에는 그 주소가 없다" — 어드민이 서버보다 먼저 올라간 창(배포 시차)의 유일한 판정.
//
// **404라는 사실만으로는 미배포라고 말하지 않는다.** 리소스 404(이미 처리된 요청·그 사이
// 지워진 문서)와 status·본문이 같기 때문이다 — 그 오독이 P56 B6이었다. 전달 경로가 낸 404
// (Hosting 폴백 → 비JSON, transport)도 여기 넣지 않는다: 그건 "이 엔드포인트가 없다"가 아니라
// "API 전체가 안 닿는다"라 TRANSPORT_MSG가 이미 맞는 말을 한다.
// 판정을 쓰는 자리: CheckinQr(발급 카드 접기) · Settings(사진 업로드 안내 · 거절 안내).
export function isRouteNotFound(e: unknown): boolean {
  return e instanceof ApiError && e.status === 404 && e.code === ROUTE_NOT_FOUND_CODE;
}

// "서버에 파기 경계가 없다" — reconcile·purge의 503(P57 A4). 재시도로는 안 낫는 503이라 일반 장애
// 문구("잠시 후 다시 시도")로 접으면 대표가 헛되이 다시 누른다. status가 아니라 code로만 판정한다 —
// 같은 503이라도 향후 다른 사유(업로드 미구성 등)와 섞이지 않게(isRouteNotFound와 같은 규약).
export function isMediaNotConfigured(e: unknown): boolean {
  return e instanceof ApiError && e.code === MEDIA_NOT_CONFIGURED_CODE;
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
  // 종전 "동시 처리 충돌"·"서버 오류가 발생했어요"는 쓰는 사람(센터 대표)의 말이 아니고,
  // 특히 500은 다음에 뭘 하라는 말이 없어 화면이 그대로 막다른 길이 됐다.
  409: "다른 곳에서 먼저 바뀌었어요 — 새로고침 후 다시 시도해주세요",
  500: "지금 처리하지 못했어요 — 잠시 후 다시 시도해주세요",
};

// 연결 자체가 실패했을 때의 문구 — fetch가 던지는 곳(요청·본문 수신)이 둘이라 상수로 묶는다.
// 센터 와이파이가 끊기는 상황이 가장 흔한 실패라 이 한 줄이 제일 자주 읽힌다.
const OFFLINE_MSG = "인터넷 연결이 끊긴 것 같아요 — 연결을 확인하고 다시 시도해주세요";

// 전달 경로(Hosting 리라이트 유실·SPA 폴백이 /api를 삼킴)가 낸 실패의 문구.
// 대표가 고칠 수 있는 게 없는 상태라 "관리자에게 알리세요"는 존재하지 않는 사람을 가리켰다
// (이 제품에 관리자는 없다 — 대표 본인이 최상위 사용자다). 실제로 가능한 유일한 다음 행동만 남긴다.
const TRANSPORT_MSG = "지금 자료를 불러올 수 없어요 — 잠시 후 다시 시도해주세요";

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
  // cache: "reload" — 캐시를 **읽지 않고** 항상 네트워크로 나간다. P34에서 Hosting 404가
  // max-age=3600을 달고 나가 브라우저·엣지에 눌러앉는 바람에, 서버를 고쳐도 클라이언트가
  // 캐시된 404를 재생하며 "서버가 죽었다"를 유지했다(시크릿 창에서만 정상 동작).
  //
  // "no-store"가 아니라 "reload"인 이유: no-store는 **브라우저 자신의 캐시만** 우회하고
  // 요청에 재검증 헤더를 붙이지 않아 중간 공유 캐시(Hosting 엣지)가 저장본을 그대로 줄 수 있다.
  // reload는 no-cache 요청 헤더를 실어 공유 캐시까지 재검증시킨다 — 우리가 겪은 실패 모드가
  // 정확히 "엣지·브라우저에 눌러앉은 응답"이라 이쪽이 맞다. (API 응답 자체의 저장 금지는
  // 서버 writeJSON의 no-store가 담당한다 — 층마다 책임이 다르다.)
  //
  // 네트워크가 아예 실패하면(오프라인·DNS·서버 미도달) fetch는 응답 대신 브라우저 자신의
  // TypeError를 던진다 — 메시지가 "Failed to fetch"(Safari "Load failed")라, 화면 53곳이
  // 하나같이 .message를 그리는 이 어드민에서는 **한국어 화면에 영문 한 줄**이 뜬다.
  // req()의 다른 모든 갈래는 한국어로 정규화돼 있었는데(STATUS_FALLBACK) 정작 센터에서
  // 제일 자주 나는 실패만 구멍이었다. 여기서 감싸 나머지와 같은 모양(ApiError)으로 만든다.
  //
  // status 0 — HTTP 응답을 못 받았다는 뜻의 관례값이다. 4xx가 아니므로 main.tsx의 retry
  // 술어가 자동 재시도 대상으로 본다(연결이 돌아오면 그대로 성공한다). transport 플래그는
  // 붙이지 않는다 — 그건 "배포를 고치기 전까지 결정적으로 실패"라는 표시라 재시도를 끈다.
  let res: Response;
  try {
    res = await fetch(BASE + path, { ...init, headers, cache: "reload" });
  } catch (e) {
    // 원문은 개발자 몫으로 콘솔에만 — 화면에는 위 한국어만 나간다.
    console.error(`[api] 네트워크 요청 실패 ${path}:`, e);
    throw new ApiError(OFFLINE_MSG, 0);
  }
  // HTML 응답 = 백엔드가 아니라 **전달 경로**(Hosting 404 페이지, SPA 폴백이 /api를 삼킨 부분
  // 배포)의 응답이다. JSON.parse 실패나 "데이터 없음" 폴백으로 뭉개면 15시간짜리 오진이 된다
  // (P34 — 라우팅 유실이 "요청한 데이터를 찾을 수 없어요"로 표시됐다). 전용 문구로 가른다.
  // \bjson\b — application/problem+json·text/json 같은 변형도 JSON으로 인정한다.
  // "application/json" 부분일치로만 보면 게이트웨이(ESPv2·IAP)를 앞에 뒀을 때 정상 JSON을
  // "전달 경로 오류"로 오진한다.
  const isJSON = /\bjson\b/i.test(res.headers.get("content-type") ?? "");
  if (!res.ok) {
    // 서버는 {"error":"한국어 메시지"}를 주는 것이 계약이지만, 프록시/게이트웨이가 낸
    // 비JSON 에러까지 영문 statusText로 노출하지 않도록 상태코드별 한국어 폴백을 둔다.
    // 매핑에 없는 상태(429·502·503 등)도 한국어 + 다음 행동으로 — 괄호 안 숫자는 남긴다
    // (대표가 찍어 보내는 화면 사진에서 유일한 단서라, 이것까지 지우면 원인을 못 좁힌다).
    let msg =
      STATUS_FALLBACK[res.status] ?? `지금 처리하지 못했어요 — 잠시 후 다시 시도해주세요 (${res.status})`;
    let data: unknown;
    let code = "";
    if (isJSON) {
      try {
        data = await res.json();
        const body = data as { error?: string; code?: unknown };
        if (body?.error) msg = body.error;
        // code는 서버가 주는 경우에만(구서버·프록시 응답엔 없다) — 문자열 아닌 값은 버린다.
        if (typeof body?.code === "string") code = body.code;
      } catch {
        /* 에러 바디가 JSON이 아니면 상태코드 폴백 유지 */
      }
    } else {
      msg = TRANSPORT_MSG;
      // 다음 사고의 진단 시간을 줄이는 흔적 — 무엇이 왔는지(HTML 등) 앞부분만 남긴다.
      const text = await res.text().catch(() => "");
      console.error(`[api] 비JSON 에러 응답 (${res.status}) ${path}:`, text.slice(0, 200));
      // 세션 정리는 던지기 **전에** — 화면이 에러를 처리하는 사이 셸이 남아 있지 않게 한다.
      if (res.status === 401) onUnauthorized?.();
      throw new ApiError(msg, res.status, data, true /* transport */);
    }
    if (res.status === 401) onUnauthorized?.();
    throw new ApiError(msg, res.status, data, false, code);
  }
  // 2xx인데 바디가 빈 응답(204 포함)은 undefined로 — res.json()의 SyntaxError가
  // 성공을 실패로 둔갑시키지 않게 한다.
  //
  // 헤더는 왔는데 본문을 받는 도중 연결이 끊기면 res.text()가 위 fetch와 똑같은 TypeError를
  // 던진다 — 같은 구멍이 하나 더 있었던 셈이라 같은 방식으로 막는다.
  let text: string;
  try {
    text = await res.text();
  } catch (e) {
    console.error(`[api] 응답 본문 수신 실패 ${path}:`, e);
    throw new ApiError(OFFLINE_MSG, 0);
  }
  if (text && !isJSON) {
    // 200인데 HTML — SPA 폴백(** → /index.html)이 /api를 삼킨 상태다. res.ok라 에러 경로를
    // 안 타므로 여기서 안 끊으면 JSON.parse SyntaxError 원문이 화면에 그대로 뜬다.
    console.error(`[api] 2xx 비JSON 응답 ${path}:`, text.slice(0, 200));
    throw new ApiError(TRANSPORT_MSG, 502, undefined, true);
  }
  try {
    return (text ? JSON.parse(text) : undefined) as T;
  } catch {
    // content-type은 JSON인데 본문이 잘렸다(연결 끊김·프록시 truncate). 정규화하지 않으면
    // 생 SyntaxError의 영문 원문("Unexpected token …")이 화면에 그대로 뜬다 — 화면은 모두
    // .message를 표시한다. 전송 실패이므로 재시도 대상은 맞다(transport 플래그는 안 붙인다).
    console.error(`[api] JSON 파싱 실패 ${path}:`, text.slice(0, 200));
    throw new ApiError("받아 온 자료가 온전하지 않아요 — 잠시 후 다시 시도해주세요", 502);
  }
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
  // 응답은 **승인으로 생긴 회원 문서**(handlers_me.go JoinApprove → writeJSON(mem)). 회원 관리 큐가
  // 승인 직후 그 회원을 자동 선택해 담당 배정으로 잇는 데 쓴다(P69) — 종전엔 void로 버렸다.
  joinApprove: (request_id: string) =>
    req<Member>("/v1/join/approve", { method: "POST", body: JSON.stringify({ request_id }) }),
  // [P55] 가입 요청 거절(owner 전용) — 승인의 대칭 동사. 서버가 **이름·번호를 비우고**
  // status=rejected로 행만 남긴다(승인되지 않은 사람의 개인정보를 센터가 계속 들고 있을 근거가
  // 없다 — 행 자체는 재요청 남용의 근거라 남는다). 응답 본문(갱신된 요청 문서)은 쓰지 않는다.
  //
  // 이 동사가 없던 동안 큐를 줄이는 방법은 승인뿐이었다 — 잘못 들어온 요청(남의 센터·중복 계정)도
  // 승인해서 지우거나 영원히 쌓아 두는 두 선택지밖에 없었다.
  joinReject: (request_id: string) =>
    req<void>("/v1/join/reject", { method: "POST", body: JSON.stringify({ request_id }) }),
  // [가정 2] 대기 중 가입 요청 목록(회원 관리 상단 큐·대시보드·네비 배지). types.ts JoinRequest 참고.
  joinRequests: () => req<JoinRequest[]>("/v1/join/requests"),

  // ── 재등록/상담 요청(계약 v2.20, P42) ─────────────────────────────────
  // 서버가 역할 스코프를 정한다: owner 전체 / trainer 담당 회원만 — 어드민은 그대로 그린다.
  consultRequests: () => req<ConsultRequest[]>("/v1/consult-requests"),
  consultRequestDone: (id: string) =>
    req<ConsultRequest>(`/v1/consult-requests/${id}/done`, { method: "POST" }),

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
  // [v2.28] 한 엔드포인트가 두 모양 중 하나를 준다 — 동의 유효면 BodyPhoto[](Full), 스태프가 스코프
  // 안에서 동의 때문에 막힌 회원이면 **403 대신 BodyPhotoMeta[]**(사진 바이트에 닿는 값 없음, 삭제
  // 요청 처리용). 판별은 types.ts isFullBodyPhoto(storage_path 유무).
  // include_deleted=true(스태프 전용 — 회원은 403): deleted_at이 찍힌 삭제분까지 내려준다. 어드민은
  // 늘 스태프이고 휴지통(복원)이 이 값을 필요로 하므로 항상 켠다 — v2.28 이전 서버는 이 파라미터를
  // 모른 채 살아 있는 것만 주므로(휴지통이 비어 보일 뿐) 깨지지 않는다.
  bodyPhotos: (member: string, opts: { includeDeleted?: boolean } = {}) =>
    req<BodyPhotoListItem[]>(
      `/v1/body-photos${qs({ member, include_deleted: opts.includeDeleted ? "true" : undefined })}`,
    ),
  createBodyPhoto: (b: BodyPhotoCreateRequest) =>
    req<BodyPhoto>("/v1/body-photos", { method: "POST", body: JSON.stringify(b) }),
  // [v2.14] 체형사진 삭제 — **누가 눌렀느냐로 뜻이 갈린다.** 스태프(이 어드민)가 부르면 소프트
  // 삭제: 응답은 deleted_at이 찍힌 사진 객체이고 30일 안에 restore로 되돌릴 수 있다. 회원 본인이
  // 앱에서 부르면 즉시 파기(204) — 그쪽은 이 클라이언트가 부르지 않는다.
  // P56 B1 이후 동의 철회 상태에서도 통한다(삭제는 철회 뒤에 **더** 필요한 동작 — DeleteInbody와 동형).
  deleteBodyPhoto: (id: string) => req<BodyPhoto>(`/v1/body-photos/${id}`, { method: "DELETE" }),
  // [v2.14] 유예 안 복원(스태프 전용). 기한이 지났으면 400 한국어("파기 기한이 지난 사진이에요").
  // 동의 철회 중이면 403 — 복원은 열람 게이트를 그대로 탄다(삭제와 달리 사진을 되살리는 일이다).
  restoreBodyPhoto: (id: string) =>
    req<BodyPhoto>(`/v1/body-photos/${id}/restore`, { method: "POST" }),
  // [v2.14] 기한 지난 사진 즉시 파기(owner 전용, 센터 전체, 한 번에 최대 25건). 응답 {purged}.
  // 평소엔 조회에 얹힌 훑기가 바닥을 맡지만(서버 sweepBodyPhotoPurge), 대표가 "지금 당장"
  // 지워야 할 때(회원 요청·감사 대응) 부를 수 있는 손잡이다.
  purgeBodyPhotos: () => req<{ purged: number }>("/v1/body-photos/purge", { method: "POST" }),
  // [v2.15] 정합 검사(owner 전용) — 버킷을 거꾸로 훑어 **메타가 없는 파일**(고아)을 찾는다.
  // member 필수. apply 없이 부르면 조회만(orphans 목록), apply=true면 그 고아를 실제로 지운다 —
  // 되돌릴 수 없어 화면이 두 단계로 가른다. 파기 경계가 미구성인 서버는 503(P57 A4)으로 거절한다.
  reconcileBodyPhotos: (member: string, apply: boolean) =>
    req<BodyPhotoReconcileResult>(
      `/v1/body-photos/reconcile${qs({ member, apply: apply ? "true" : undefined })}`,
      { method: "POST" },
    ),
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
  // 트레이너 사진 업로드(owner 전용) — 폰·노트북에 있는 파일을 그대로 올린다. 종전에는 "이미지
  // 주소(URL)" 칸 하나뿐이라, URL이 없는 사진(= 대표가 가진 사진 대부분)은 넣을 방법이 아예 없었다.
  //
  // 바디는 base64 문자열이다(multipart 아님): 이 API 층은 전부 JSON + Bearer 한 벌로 통일돼 있고,
  // 아바타 한 장(축소 후 수십 KB)에 전송 층을 하나 더 들일 이유가 없다. 대신 **보내기 전에**
  // 클라이언트가 512px로 줄인다(lib/imageDownscale.ts) — 서버는 디코드 후 2MB를 넘기면 거절하고,
  // 폰 원본은 그 상한을 항상 넘는다.
  //
  // 서버가 응답의 photo_url을 프로필에도 저장하므로 이 호출 하나로 반영이 끝난다.
  // 404 = 이 배포에 아직 없는 엔드포인트(백엔드 병렬 작업) — 화면이 CheckinQrCard와 같은 규약으로
  // 접는다(크래시 대신 "아직 서버에 올라가지 않았어요").
  uploadStaffPhoto: (uid: string, body: StaffPhotoUploadRequest) =>
    req<StaffPhotoUploadResult>(`/v1/staff/${uid}/photo`, {
      method: "POST",
      body: JSON.stringify(body),
    }),
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
  // [P55] 센터 신원 편집(owner 전용) — PUT /v1/center의 **세 번째 덩어리**(center).
  //
  // **3칸을 항상 전부 싣는다**(business와 같은 통 교체): 전화·주소는 잘못 적은 값을 비워서
  // 지우는 일이 실제로 필요하고, 머지였다면 한 번 들어간 오타를 지울 방법이 없다.
  // policy·business를 함께 싣지 않는다 — 서버는 **보낸 덩어리만** 처리하므로(handlers_me.UpdateCenter)
  // 이 호출은 정책도 사업자 정보도 건드리지 않는다.
  //
  // 이름이 빈 값이면 서버가 400(domain.Center.Validate "센터 이름을 입력해주세요") — 화면이 같은
  // 규칙으로 선차단하되 집행자는 서버다. 응답은 GET /v1/center과 같은 모양(Center 전체).
  updateCenterIdentity: (center: CenterIdentity) =>
    req<Center>("/v1/center", { method: "PUT", body: JSON.stringify({ center }) }),
  // [P42] 체육시설업 신고 상태 저장(owner 전용) — PUT /v1/center의 덩어리 머지가 아니라
  // **전용 엔드포인트**다: 바디는 facility 절 3필드를 통째로(top-level, {facility} 래핑 없음).
  // reported인데 신고번호가 비면 400 — 화면이 같은 규칙으로 선차단한다(서버가 최종 집행자).
  // 응답은 Center가 아니라 **저장된 facility 그 자체**(200 same shape) — 캐시 반영은
  // useSaveFacility의 keys.center 무효화가 맡는다.
  saveFacility: (facility: CenterFacility) =>
    req<CenterFacility>("/v1/center/facility", { method: "PUT", body: JSON.stringify(facility) }),

  // ── 데스크 체크인 QR(P49, owner 전용) ────────────────────────────────
  // 조회 — 미발급이면 {issued:false, token:"", issued_at:null}. 200이지 404가 아니다
  // (404는 "이 배포에 엔드포인트가 아직 없다"는 뜻으로만 쓰인다 — CheckinQr.tsx의 배포 시차 분기).
  checkinQr: () => req<CheckinQrToken>("/v1/center/checkin-qr"),
  // 재발급 — 첫 발급과 교체가 **같은 동사**다(서버가 새 토큰을 만들어 저장하고 그 결과를
  // 조회와 같은 모양으로 돌려준다). 바디 없음. 성공하는 순간 **이전 토큰은 즉시 무효**가 되어
  // 데스크에 붙어 있는 종이가 죽는다 — 화면이 2단 확인을 세우는 이유가 이 한 줄이다.
  rotateCheckinQr: () => req<CheckinQrToken>("/v1/center/checkin-qr/rotate", { method: "POST" }),

  // ── 관리 평면(멀티센터) — superadmin 전용 ────────────────────────────
  // 계약 v2.16. 서버는 superadmin이 아닌 신원에 403을 주고(`api.CreateCenter`), 반대로
  // superadmin에게는 이 두 경로와 /v1/me 외 전부를 403으로 막는다(`superadminAllowedPath`).
  //
  // 목록은 **기본 센터 ∪ 상호 등록 센터**(v2.35) — 기본 센터는 상호가 비어도 name:"" 그대로
  // 맨 앞에 온다(화면이 "상호 미등록"으로 그린다 — Centers.tsx). v2.34까지는 상호 등록 문서만
  // 돌려줘 1호 고객 라이즈가 목록에서 사라져 있었다(P70).
  adminCenters: () => req<AdminCenter[]>("/v1/admin/centers"),
  // 센터 + 최초 owner를 한 요청으로. 409 = 이미 쓰는 센터 ID이거나, owner 이메일이 이미
  // 다른 센터에 연결된 계정이다(서버가 UserIndex를 덮어써 원래 센터를 잃는 사고를 막는다).
  createCenter: (body: CenterCreateBody) =>
    req<CenterCreated>("/v1/admin/centers", { method: "POST", body: JSON.stringify(body) }),
};
