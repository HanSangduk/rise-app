// 설정 · 직원 — 목업 s-set 1:1(대표 전용, App.tsx에서 owner 게이트).
// 직원 신규 생성은 v1.8(POST /v1/staff)로 실제 초대 플로우가 됐다(InviteStaffModal).
// v2.0(P08 직원 생애주기)으로 **되돌리기**가 생겼다 — 정정(PUT /v1/staff/{uid}) · 담당 이관
// (transfer) · 퇴사(deactivate) · 재입사(reactivate). 종전엔 이름 오타·역할 오지정·퇴사를
// 처리할 경로가 없어 잘못 초대하면 영구히 남았다.
// 운영 정책은 v1.4(PUT /v1/center)로 실제 편집 폼이 됐다 — 하드코딩 금지 원칙(설계00 §3.1)의
// 마지막 조각.
// DragEvent는 React 합성 이벤트와 DOM 전역이 같은 이름이라 별칭으로 가른다 — 창 전체에 거는
// 리스너(TrainerPhotoField)는 DOM 쪽 타입이어야 한다.
import { useEffect, useId, useRef, useState, type DragEvent as ReactDragEvent } from "react";
import { FirebaseError } from "firebase/app";
import { sendPasswordResetEmail } from "firebase/auth";
import {
  ArrowRightLeft,
  CalendarOff,
  Check,
  IdCard,
  ImagePlus,
  Pencil,
  Plus,
  Save,
  Trash2,
  TriangleAlert,
  UserCheck,
  UserMinus,
  UserPlus,
} from "lucide-react";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Chip,
  EmptyState,
  ErrorState,
  Input,
  Label,
  Modal,
  Select,
  Spinner,
  TD,
  TH,
  THead,
  TR,
  Table,
  Textarea,
} from "@/components/ui";
import { ApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { auth } from "@/lib/firebase";
// 데스크 체크인 QR(P11 → P49) — 발급·QR 렌더·A4 인쇄 시트가 한 덩어리라 별 파일로 뺀다
// (인쇄 포털·print 전용 CSS가 이 화면의 다른 섹션과 공유하는 게 하나도 없다).
import { CheckinQrCard } from "@/features/CheckinQr";
import {
  useApproveJoin,
  useBookings,
  useCenter,
  useCreateStaff,
  useDeactivateStaff,
  useJoinRequests,
  useMembers,
  useReactivateStaff,
  useRecurrings,
  useSaveFacility,
  useSetOffdays,
  useStaff,
  useTransferStaff,
  useUpdateCenterBusiness,
  useUpdateCenterPolicy,
  useUpdateStaff,
  useUpdateStaffProfile,
  useUploadStaffPhoto,
} from "@/lib/queries";
// 업로드 전 축소(캔버스) — 폰 사진 3~5MB를 서버 상한(2MB) 아래로 줄인다. 상세는 그 파일 머리주석.
import { PHOTO_MAX_SIDE, formatBytes, preparePhoto } from "@/lib/imageDownscale";
import {
  formatCurrency,
  formatPercent,
  formatSlotKey,
  isStaffActive,
  slotKeyStart,
  todayStr,
} from "@/lib/format";
import {
  BUSINESS_ADDRESS_MAX,
  BUSINESS_EMAIL_MAX,
  BUSINESS_FIELD_KEYS,
  BUSINESS_FIELD_LABEL,
  BUSINESS_NAME_MAX,
  BUSINESS_PHONE_DIGITS_MAX,
  BUSINESS_PHONE_DIGITS_MIN,
  BUSINESS_PHONE_MAX,
  BUSINESS_REG_NO_DIGITS,
  EMPTY_BUSINESS,
  EMPTY_FACILITY,
  MAX_PENALTY_PCT,
  WEEKDAY_LABEL,
  businessMissingFields,
  centerHours,
  hourLabel,
  hoursValid,
  toBookingRef,
  type BookingRef,
  type Center,
  type CenterBusiness,
  type CenterBusinessView,
  type CenterFacility,
  type CenterPolicy,
  type FacilityReportStatus,
  type JoinRequest,
  type Payout,
  type PayoutType,
  type Staff,
  type StaffBlockers,
  type StaffProfile,
  type StaffRole,
  type StaffTransferResult,
  type StaffUpdateRequest,
} from "@/lib/types";

export function Settings() {
  const { me } = useAuth();
  // 이 화면 자체가 App.tsx owner 게이트 뒤에 있지만, 초대는 서버도 owner만 허용하므로(403)
  // 버튼 노출도 같은 조건으로 한 번 더 잠근다 — 눌러보고 403을 받는 UI를 만들지 않는다.
  const isOwner = me?.role === "owner";
  const staffQ = useStaff();
  const centerQ = useCenter();
  const joinReqQ = useJoinRequests();
  const [inviteOpen, setInviteOpen] = useState(false);
  const [offdayTarget, setOffdayTarget] = useState<Staff | null>(null);
  const [profileTarget, setProfileTarget] = useState<Staff | null>(null);
  // v2.0 생애주기 — 정정 · 담당 이관 · 퇴사 · 재입사.
  const [editTarget, setEditTarget] = useState<Staff | null>(null);
  // thenDeactivate — 퇴사 모달의 blockers에서 넘어온 이관인지. 이관을 마치면 "퇴사 처리
  // 계속하기"로 되돌려 보낸다(왜 안 되는지 → 그래서 뭘 해야 하는지 → 다시 시도가 한 줄로 이어진다).
  const [transferTarget, setTransferTarget] = useState<{ staff: Staff; thenDeactivate: boolean } | null>(
    null,
  );
  const [deactivateTarget, setDeactivateTarget] = useState<Staff | null>(null);
  const [reactivateTarget, setReactivateTarget] = useState<Staff | null>(null);
  // 가입 요청 승인은 되돌릴 수 없다(승인 즉시 그 계정이 회원 데이터를 본다) — 목록이 폴링으로
  // 움직이는 화면에서 한 번의 오클릭이 **남의 계정을 남의 기록에 붙인다**. 확인 창을 한 단계 둔다.
  const [approveTarget, setApproveTarget] = useState<JoinRequest | null>(null);

  // 서버는 최신순으로 주는데, 그대로 그리면 폴링(60초·창 포커스)으로 새 요청이 **맨 위에 삽입**돼
  // 보고 있던 행이 전부 한 칸 내려간다 — 승인 버튼을 누르려던 손 밑에서 대상이 바뀌는 구조다.
  // 요청 시각 오름차순(먼저 온 순)으로 고정하면 새 요청은 항상 **끝에 붙어** 기존 행이 움직이지
  // 않는다. 처리 순서도 선착순이라 화면 순서와 대표의 일 처리 순서가 같아진다.
  // (동시각 tie는 id로 갈라 매 응답마다 순서가 흔들리지 않게 한다.)
  const joinRequests = [...(joinReqQ.data ?? [])].sort(
    (a, b) => a.requested_at.localeCompare(b.requested_at) || a.id.localeCompare(b.id),
  );
  // 끝에 붙은 새 요청이 그냥 묻히지 않게 표시만 남긴다(최신순 정렬이 하던 "눈에 띄기" 역할).
  // 응답 전(undefined)과 "응답이 빈 목록"을 구분해 넘긴다 — 첫 응답이 기준선이다.
  const freshJoinIds = useFreshIds(joinReqQ.data ? joinRequests.map((r) => r.id) : undefined);

  const allStaff = staffQ.data ?? [];
  // GET /v1/staff는 inactive도 준다(이름 해석 보존) — 재직/퇴사 구분은 클라이언트 몫이다.
  const activeStaff = allStaff.filter((s) => isStaffActive(s));
  const inactiveStaff = allStaff.filter((s) => !isStaffActive(s));
  // 락아웃 가드 미러(service_staff.go activeOwnerCount) — 활성 대표가 1명뿐이면 그 사람의
  // 퇴사(409)도 강등(409)도 서버가 막는다. 대표가 1명인 지금이 기본 상태다.
  const activeOwnerCount = activeStaff.filter((s) => s.role === "owner").length;

  // 퇴사 버튼을 **감추는** 이유. 서버는 400(본인)·409(마지막 활성 대표)로 확실히 거절하는데,
  // 이 화면의 관례는 "눌러보고 403을 받는 UI를 만들지 않는다"(초대 버튼 owner 게이트와 같은 자리)다.
  // 다만 조용히 감추면 "왜 나만 버튼이 없지"가 되므로 그 자리에 이유 문장을 남긴다.
  function deactivateBlockReason(s: Staff): string | null {
    if (s.uid === me?.uid) return "본인은 퇴사 처리할 수 없어요";
    if (s.role === "owner" && activeOwnerCount <= 1) return "마지막 활성 대표는 퇴사할 수 없어요";
    return null;
  }

  function staffRow(s: Staff) {
    const active = isStaffActive(s);
    const blockReason = active ? deactivateBlockReason(s) : null;
    return (
      <TR key={s.uid} className={active ? undefined : "opacity-60"}>
        <TD>
          <div className="flex items-center gap-2">
            <StaffAvatar name={s.name} color={s.color} photoUrl={s.profile.photo_url} />
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-1.5 font-bold">
                {s.name}
                {!active && <Badge tone="danger">퇴사</Badge>}
                {active && isProfileEmpty(s.profile) && <Badge tone="muted">프로필 미등록</Badge>}
              </div>
              {!active ? (
                <div className="text-[10.5px] text-muted">
                  {s.left_at ? `${formatLeftAt(s.left_at)} 퇴사` : "퇴사 처리됨"}
                </div>
              ) : (
                s.profile.title && (
                  <div className="truncate text-[10.5px] text-muted">{s.profile.title}</div>
                )
              )}
            </div>
          </div>
        </TD>
        <TD>
          <Badge tone={!active ? "muted" : s.role === "owner" ? "brand" : "warn"}>
            {s.role === "owner" ? "대표" : "트레이너"}
          </Badge>
        </TD>
        <TD>
          {/* rate는 0~1 소수(계약 확정) — formatPercent로 *100 표시. */}
          {s.role === "owner"
            ? "—"
            : s.payout.type === "per_session"
              ? `${formatCurrency(s.payout.value)}/회`
              : `요율 ${formatPercent(s.payout.value)}`}
        </TD>
        <TD>
          <div className="flex flex-wrap items-center gap-1.5">
            {isOwner && (
              <Button size="sm" variant="outline" onClick={() => setEditTarget(s)}>
                <Pencil className="h-3.5 w-3.5" /> 정정
              </Button>
            )}
            <Button size="sm" variant="outline" onClick={() => setProfileTarget(s)}>
              <IdCard className="h-3.5 w-3.5" /> 프로필
            </Button>
            {active && (
              <Button size="sm" variant="outline" onClick={() => setOffdayTarget(s)}>
                <CalendarOff className="h-3.5 w-3.5" /> 휴무
              </Button>
            )}
            {isOwner && (
              <Button
                size="sm"
                variant="outline"
                onClick={() => setTransferTarget({ staff: s, thenDeactivate: false })}
              >
                <ArrowRightLeft className="h-3.5 w-3.5" /> 담당 이관
              </Button>
            )}
            {isOwner &&
              (!active ? (
                <Button size="sm" variant="outline" onClick={() => setReactivateTarget(s)}>
                  <UserCheck className="h-3.5 w-3.5" /> 재입사
                </Button>
              ) : blockReason ? (
                <span className="text-[10.5px] text-muted">{blockReason}</span>
              ) : (
                <Button
                  size="sm"
                  variant="outline"
                  className="text-danger"
                  onClick={() => setDeactivateTarget(s)}
                >
                  <UserMinus className="h-3.5 w-3.5" /> 퇴사
                </Button>
              ))}
          </div>
        </TD>
      </TR>
    );
  }

  return (
    <div>
      <h2 className="text-[16.5px] font-bold">설정 · 직원</h2>
      {/* "법의 상한 안에서 자유롭게"는 위약금율을 100%까지 받던 화면의 문장이었다 —
          상한(10%)은 서버가 강제하고, 컷오프처럼 소급되는 값도 있어 "자유롭게"가 아니다(P14). */}
      <p className="mt-0.5 mb-3.5 text-xs text-muted">
        센터 정책과 팀 권한 — 여기서 정한 값이 계약서·환불·회원 앱에 그대로 나갑니다.
      </p>

      <div className="grid gap-3 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>직원 · 권한</CardTitle>
            {isOwner && (
              <Button size="sm" onClick={() => setInviteOpen(true)}>
                <UserPlus className="h-3.5 w-3.5" /> 트레이너 초대
              </Button>
            )}
          </CardHeader>
          <CardContent>
            {staffQ.isLoading ? (
              <Spinner />
            ) : staffQ.isError ? (
              <ErrorState error={staffQ.error} onRetry={() => void staffQ.refetch()} />
            ) : !staffQ.data?.length ? (
              <EmptyState>등록된 직원이 없습니다.</EmptyState>
            ) : (
              <Table>
                <THead>
                  <TR>
                    <TH>이름</TH>
                    <TH>역할</TH>
                    <TH>정산 방식</TH>
                    <TH></TH>
                  </TR>
                </THead>
                <tbody>
                  {activeStaff.map(staffRow)}
                  {/* 퇴사자는 목록 하단 별도 그룹으로 — 표 구조(4열)는 그대로 두고 구분선만 넣는다. */}
                  {inactiveStaff.length > 0 && (
                    <TR>
                      <TD colSpan={4} className="pt-3 text-[10.5px] font-bold text-muted">
                        퇴사 {inactiveStaff.length}명 — 과거 정산·원장·수업 기록이 이 계정을 참조하고
                        있어 삭제하지 않고 남깁니다
                      </TD>
                    </TR>
                  )}
                  {inactiveStaff.map(staffRow)}
                </tbody>
              </Table>
            )}
            <p className="mt-2.5 text-[10.5px] text-muted">
              트레이너는 담당 회원·본인 일정·본인 정산만 봅니다. 퇴사는 담당(회원·회원권·고정
              스케줄·예정 예약)이 전부 비어야 처리됩니다 — 남아 있으면 퇴사 창이 무엇을 이관해야
              하는지 알려줍니다.
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>운영 정책</CardTitle>
            <Badge tone="brand">편집 가능</Badge>
          </CardHeader>
          <CardContent>
            {centerQ.isLoading ? (
              <Spinner />
            ) : centerQ.isError ? (
              <ErrorState error={centerQ.error} onRetry={() => void centerQ.refetch()} />
            ) : !centerQ.data ? (
              <EmptyState>정책 정보가 없습니다.</EmptyState>
            ) : (
              <PolicyEditForm initial={centerQ.data.policy} />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>사업자 정보</CardTitle>
            {/* 배지는 **저장된** 상태만 말한다(서버가 준 complete). 편집 중인 화면 값으로 세면
                아직 저장하지 않은 입력이 "등록 완료"로 보여, 문서가 시행 중이라고 오해하게 된다 —
                미기재 목록은 그래서 폼 안쪽에서 따로, 지금 화면 값으로 센다. */}
            {centerQ.data &&
              (businessOf(centerQ.data).complete ? (
                <Badge tone="ok">등록 완료</Badge>
              ) : (
                <Badge tone="warn">미완성 {businessMissingFields(businessOf(centerQ.data)).length}칸</Badge>
              ))}
          </CardHeader>
          <CardContent>
            {centerQ.isLoading ? (
              <Spinner />
            ) : centerQ.isError ? (
              <ErrorState error={centerQ.error} onRetry={() => void centerQ.refetch()} />
            ) : !centerQ.data ? (
              <EmptyState>사업자 정보를 불러오지 못했습니다.</EmptyState>
            ) : (
              <BusinessEditForm initial={businessOf(centerQ.data)} />
            )}
          </CardContent>
        </Card>

        {/* 체육시설업 신고(P42) — 사업자 정보 옆자리. 계약서 템플릿 2종(신고/비대상)을 가르는
            상태 선언이라 법적 신원(사업자 정보)과 같은 구역에 둔다. */}
        <Card>
          <CardHeader>
            <CardTitle>체육시설업 신고</CardTitle>
            {/* 사업자 정보 배지와 같은 규약 — 배지는 **저장된** 상태만 말한다(편집 중 값은 폼 몫).
                미확인만 warn인 이유: 그 상태로는 계약서 본문이 발행되지 않는다(P42). */}
            {centerQ.data &&
              (facilityOf(centerQ.data).report_status === "unknown" ? (
                <Badge tone="warn">미확인</Badge>
              ) : facilityOf(centerQ.data).report_status === "reported" ? (
                <Badge tone="ok">신고함</Badge>
              ) : (
                <Badge tone="ok">신고 대상 아님</Badge>
              ))}
          </CardHeader>
          <CardContent>
            {centerQ.isLoading ? (
              <Spinner />
            ) : centerQ.isError ? (
              <ErrorState error={centerQ.error} onRetry={() => void centerQ.refetch()} />
            ) : !centerQ.data ? (
              <EmptyState>시설 신고 정보를 불러오지 못했습니다.</EmptyState>
            ) : (
              <FacilityEditForm initial={facilityOf(centerQ.data)} />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>가입 요청 승인</CardTitle>
            <Badge tone="muted">{joinReqQ.data?.length ?? 0}건</Badge>
          </CardHeader>
          <CardContent>
            {joinReqQ.isLoading ? (
              <Spinner />
            ) : joinReqQ.isError ? (
              <ErrorState error={joinReqQ.error} onRetry={() => void joinReqQ.refetch()} />
            ) : !joinRequests.length ? (
              <EmptyState>대기 중인 가입 요청이 없습니다.</EmptyState>
            ) : (
              <div className="space-y-1.5">
                {joinRequests.map((r) => (
                  <div
                    key={r.id}
                    className="flex items-center justify-between rounded-[10px] bg-panel-2 px-3 py-2 text-[12.5px]"
                  >
                    <span className="flex flex-wrap items-center gap-1.5">
                      <b>{r.name}</b> <span className="text-muted">{r.phone}</span>
                      {/* 이 화면을 열어둔 사이에 새로 들어온 요청 — 목록 끝에 붙으므로 표시로 알린다. */}
                      {freshJoinIds.has(r.id) && <Badge tone="brand">새 요청</Badge>}
                    </span>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setApproveTarget(r)}
                      title="확인 창에서 이름·번호를 한 번 더 보고 승인합니다"
                    >
                      <Check className="h-3.5 w-3.5" /> 승인
                    </Button>
                  </div>
                ))}
              </div>
            )}
            {/* 승인 실패 문구는 확인 창 안에 있다(창이 열린 채로 남아 재시도가 그 자리에서 된다). */}
            <p className="mt-2.5 text-[10.5px] text-muted">
              {/* 내부 티켓 번호(P48)·"폴백 경로" 같은 개발 용어는 화면에서 뺀다(어드민 UX 감사). */}
              전화번호가 자동으로 맞지 않은 회원의 "센터 찾기" 요청만 여기 쌓입니다. 목록은 1분마다
              자동 갱신되고, 먼저 온 순으로 고정돼 새 요청이 끼어들어도 기존 줄이 밀리지 않습니다.
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>센터 · 앱 연결</CardTitle>
          </CardHeader>
          <CardContent>
            <Table>
              <tbody>
                <TR>
                  <TD className="text-muted">센터명</TD>
                  <TD>
                    {/* GET /v1/center(v1.4 확정)는 center_id+policy만 반환 — 표시명은 앱 셸과 동일한 고정값. */}
                    <b>라이즈 컨디셔닝 센터</b> (강남)
                  </TD>
                </TR>
                <TR>
                  <TD className="text-muted">회원 연결(기본)</TD>
                  <TD>
                    <b>등록하면 끝</b> — 앱에서 번호 인증 시 자동 매칭 + 이름 확인 1탭
                  </TD>
                </TR>
                <TR>
                  <TD className="text-muted">초대 보내기(보조)</TD>
                  <TD>카톡/문자 설치 링크</TD>
                </TR>
              </tbody>
            </Table>
            <p className="mt-2.5 text-[10.5px] text-muted">
              {/* 내부 티켓 번호(P48) 제거 — 대표에게 의미 없는 문자열이다(어드민 UX 감사). */}
              초대코드 입력은 없습니다. 이름 확인은 오타 번호로 남의 기록에 연결되는 사고를 막는
              안전장치입니다.
            </p>
          </CardContent>
        </Card>

        {/* 데스크 체크인 QR — 대표 전용. 이 화면 자체가 App.tsx owner 게이트 뒤에 있지만,
            운영 토큰(owner 전용 API)을 다루는 자리라 이 화면의 관례대로 한 겹 더 잠근다
            (초대 버튼과 같은 조건). **이 두 겹이 useCheckinQr에 enabled 인자가 없는 근거다**
            — 트레이너 세션에서는 카드가 마운트되지 않아 조회 자체가 일어나지 않는다
            (queries.ts useCheckinQr 주석). 이 줄에서 게이트를 빼면 그 훅이 403을 받는다. */}
        {isOwner && <CheckinQrCard />}

        <Card>
          <CardHeader>
            <CardTitle>모바일 사용(트레이너)</CardTitle>
          </CardHeader>
          <CardContent className="text-[12px] leading-[1.9]">
            이 어드민은 반응형입니다 — 폰 브라우저에서 그대로 쓰고, "홈 화면에 추가"(PWA)하면
            앱처럼 아이콘으로 실행됩니다. 별도 트레이너 앱 없이 체크인·Home Work·정산 확인까지
            가능합니다.
            <p className="mt-2 text-[10.5px] text-muted">창 폭을 줄이면 모바일 레이아웃으로 전환됩니다.</p>
          </CardContent>
        </Card>
      </div>

      {/* 조건부 마운트 — 닫으면 언마운트되므로 다시 열 때 폼이 항상 빈 상태로 시작한다. */}
      {inviteOpen && <InviteStaffModal onClose={() => setInviteOpen(false)} />}
      {offdayTarget && <OffdaysModal staff={offdayTarget} onClose={() => setOffdayTarget(null)} />}
      {profileTarget && <ProfileModal staff={profileTarget} onClose={() => setProfileTarget(null)} />}
      {editTarget && (
        <StaffEditModal
          staff={editTarget}
          isSelf={editTarget.uid === me?.uid}
          isLastActiveOwner={
            isStaffActive(editTarget) && editTarget.role === "owner" && activeOwnerCount <= 1
          }
          onClose={() => setEditTarget(null)}
        />
      )}
      {transferTarget && (
        <TransferStaffModal
          from={transferTarget.staff}
          staff={allStaff}
          onClose={() => setTransferTarget(null)}
          // 이관을 마쳤고 충돌도 없으면 곧바로 퇴사 창으로 되돌아간다 — 대표가 설정 화면을
          // 다시 훑으며 같은 사람을 찾아 누르지 않게.
          onContinueToDeactivate={
            transferTarget.thenDeactivate
              ? () => {
                  const s = transferTarget.staff;
                  setTransferTarget(null);
                  setDeactivateTarget(s);
                }
              : undefined
          }
        />
      )}
      {deactivateTarget && (
        <DeactivateStaffModal
          staff={deactivateTarget}
          onClose={() => setDeactivateTarget(null)}
          onNeedTransfer={() => {
            const s = deactivateTarget;
            setDeactivateTarget(null);
            setTransferTarget({ staff: s, thenDeactivate: true });
          }}
        />
      )}
      {reactivateTarget && (
        <ReactivateStaffModal staff={reactivateTarget} onClose={() => setReactivateTarget(null)} />
      )}
      {approveTarget && (
        <ApproveJoinModal
          request={approveTarget}
          onClose={() => setApproveTarget(null)}
          // 목록에서 사라진 요청(다른 기기에서 이미 승인·취소됨)을 계속 승인 대상으로 붙들지 않는다.
          gone={!joinRequests.some((r) => r.id === approveTarget.id)}
        />
      )}
    </div>
  );
}

// 폴링으로 갱신되는 목록에서 **이 화면을 연 뒤 새로 들어온 항목**의 id 집합.
//
// 기준선은 **첫 응답이 도착한 순간**이다. 로딩 중의 빈 배열을 기준선으로 삼으면 처음 뜬 요청들이
// 전부 "새 요청"이 되어 배지가 아무 뜻도 갖지 못한다 — 그래서 미도착은 undefined로 구분해 건너뛴다.
// 한 번 새 것으로 표시한 id는 계속 유지한다(다음 폴링에서 조용히 평범해지면 표시의 의미가 없다).
function useFreshIds(ids: string[] | undefined): Set<string> {
  const seen = useRef<Set<string> | null>(null);
  const [fresh, setFresh] = useState<Set<string>>(new Set());
  // 배열은 매 렌더 새 참조라 내용으로 비교한다(정렬이 고정돼 있어 문자열 비교로 충분).
  const key = ids ? ids.join(",") : null;
  useEffect(() => {
    if (key === null) return; // 아직 응답 전 — 기준선을 잡지 않는다
    const list = key ? key.split(",") : [];
    const prev = seen.current;
    // 사라진 id도 기억에 남긴다 — 다른 기기에서 처리됐다가 되살아난 요청을 "새 요청"으로 속이지 않는다.
    seen.current = new Set([...(prev ?? []), ...list]);
    if (prev === null) return; // 첫 응답 = 내가 오기 전부터 있던 것
    const added = list.filter((id) => !prev.has(id));
    if (added.length) setFresh((old) => new Set([...old, ...added]));
  }, [key]);
  return fresh;
}

// 가입 요청 승인 확인 — 되돌리기가 없는 유일한 1클릭 동작이라 한 단계를 세운다.
//
// 왜 폴링을 끄지 않고 확인 창을 세웠나: 회원 앱이 "센터에서 승인하면 연결돼요"라고 약속하고
// 대기 화면에 머문다(queries.ts JOIN_REQUESTS_POLL_MS). 폴링을 끄면 그 약속이 깨진다.
// 정렬 고정만으로도 삽입에 의한 밀림은 사라지지만, **삭제**(다른 기기·다른 대표가 먼저 승인)와
// 손이 이미 움직이는 중인 클릭까지는 막지 못한다 — 그래서 대상을 객체로 붙들고 이름·번호를
// 다시 보여준 뒤에 실행한다. 승인은 하루 0~2건이라 한 클릭의 비용이 오연결 위험보다 싸다.
function ApproveJoinModal({
  request,
  onClose,
  gone,
}: {
  request: JoinRequest;
  onClose: () => void;
  gone: boolean;
}) {
  const approveJoin = useApproveJoin();
  return (
    <Modal open onClose={onClose} title="가입 요청 승인">
      <div className="space-y-3">
        <p className="text-[12.5px]">
          <b>{request.name}</b> <span className="text-muted">{request.phone}</span> 님을 이 센터
          회원으로 연결합니다.
        </p>
        {gone ? (
          <p className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] text-warn">
            <TriangleAlert className="mr-1 inline h-3.5 w-3.5" />이 요청이 목록에서 사라졌어요 —
            다른 기기에서 이미 처리됐을 수 있습니다. 창을 닫고 목록을 다시 확인해주세요.
          </p>
        ) : (
          <p className="text-[10.5px] text-muted">
            승인하면 그 계정이 바로 이 회원의 기록을 보게 되고{" "}
            <b className="text-ink">되돌리는 버튼은 없습니다</b>. 목록은 1분마다 갱신되니 눈앞의 그
            사람이 맞는지 이름·번호를 한 번만 확인해주세요.
          </p>
        )}
        {approveJoin.isError && (
          <p className="text-[11px] text-danger">승인 실패: {approveJoin.error.message}</p>
        )}
        <Button
          className="w-full"
          disabled={approveJoin.isPending || gone}
          onClick={() => approveJoin.mutate(request.id, { onSuccess: onClose })}
        >
          <Check className="h-4 w-4" /> {approveJoin.isPending ? "승인 중…" : "승인하기"}
        </Button>
        <Button className="w-full" variant="outline" onClick={onClose}>
          취소
        </Button>
      </div>
    </Modal>
  );
}

// 퇴사 시각(RFC3339) → "2026-08-22". 초 단위까지 보여줄 이유가 없고, 표에서는 날짜만 읽힌다.
function formatLeftAt(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${m}-${day}`;
}

// 정책 값이 언제 효력을 갖는지 — 이 화면이 사실대로 말해야 하는 단 하나의 구분(P14 H1).
//
//   즉시·소급  컷오프·용량·통계 기준. 서버는 취소/예약 **시점에** GetPolicy를 새로 읽는다
//              (service.CancelBooking → domain.WithinCancelCutoff). 즉 이미 잡혀 있는 예약도
//              새 값으로 판정된다.
//   계약 고정  위약금율만. 발급 시점 값이 계약에 스냅샷되어(service.buildContractForPass)
//              기존 계약의 환불에는 영향이 없다.
//
// 종전 문구는 "새 정책은 이후 예약·환불·통계부터 적용됩니다"로 **넷 다 소급되지 않는다**고
// 단정했다. 실제로는 컷오프를 24→48h로 올리는 순간, 이틀 안에 수업이 잡힌 회원 전원이 예약할
// 때는 없던 페널티 구간에 이미 들어가 있다 — 그렇게 생긴 원장 차감은 정책을 되돌려도 남는다.
const POLICY_EFFECT_NOTE =
  "취소 컷오프·예약 용량·통계 기준은 이미 잡힌 예약과 기록에도 바로 적용돼요. 위약금율만 계약 시점 값으로 고정돼 기존 계약은 그대로입니다.";

// 운영 정책 편집 폼(v1.4, PUT /v1/center — owner 전용). 서버가 범위를 검증하고(용량 1~10,
// 컷오프 0~168h, 위약금율 0~0.1, 홀딩 상한 양수/-1) 위반 시 400 한국어 메시지를 준다 — 그대로 표시.
// 위약금율은 기존 표시 규약(%)대로 입력받아 저장 시 0~1 소수로 변환한다.
//
// **바뀐 필드만 보낸다**(P14 M5): 서버는 머지 시맨틱인데 폼이 늘 10필드를 실어 보내면 그 보호가
// 무력화된다 — 다른 창·다른 대표가 먼저 저장한 값을, 내가 화면에 들고 있던 낡은 값으로 통째로
// 되돌리게 된다. StaffEditModal이 이미 쓰는 patch 패턴과 같은 자리다.
function PolicyEditForm({ initial }: { initial: CenterPolicy }) {
  const updatePolicy = useUpdateCenterPolicy();
  // **비교 기준을 마운트 시점에 얼린다.** patch는 "서버 값과의 차이"가 아니라 "내가 이 화면에서
  // 바꾼 것"이어야 한다: initial은 폴링·포커스 재조회로 움직이는 살아 있는 prop이라, 그대로
  // 비교하면 다른 창이 방금 바꾼 필드가 **내가 바꾼 것으로 둔갑**해 patch에 실린다 — patch로
  // 좁힌 의미가 그 자리에서 도로 사라진다(P14 M5).
  const [baseline, setBaseline] = useState(initial);
  const [slotCapacity, setSlotCapacity] = useState(initial.slot_capacity);
  const [cutoffHours, setCutoffHours] = useState(initial.cancel_cutoff_hours);
  const [graceOnce, setGraceOnce] = useState(initial.grace_once);
  // 소수 % 보존 — 0.125는 12.5%로 반올림 없이 표시하고 저장 시 /100. *10000/100은
  // 부동소수 노이즈(0.1*100 = 10.000…2)만 제거한다(0.01%p 해상도).
  const [penaltyPct, setPenaltyPct] = useState(pctOf(initial.penalty_rate));
  const [revenueTarget, setRevenueTarget] = useState(initial.revenue_target);
  const [reregWindowDays, setReregWindowDays] = useState(initial.rereg_window_days);
  const [longAbsentDays, setLongAbsentDays] = useState(initial.long_absent_days);
  const [expiringDays, setExpiringDays] = useState(initial.expiring_days);
  // 홀딩 상한 2필드만 문자열 state — Number(v)||0 패턴은 "-" 타이핑을 0으로 지워
  // -1(무제한) 입력 자체가 불가능했다. 저장 시 파싱하고, 빈/불량이면 저장을 잠근다.
  const [maxHolds, setMaxHolds] = useState(String(initial.max_holds_per_pass));
  const [maxHoldDays, setMaxHoldDays] = useState(String(initial.max_hold_total_days));
  // 운영시간 — 필드가 없는 응답(구서버·미저장 센터)은 centerHours가 9/21로 접는다. 그 상태에서
  // 대표가 값을 바꾸면 그때 처음으로 patch에 실려 나간다(그전까지 서버는 계속 기본값을 쓴다).
  const [openHour, setOpenHour] = useState(centerHours(initial).open);
  const [closeHour, setCloseHour] = useState(centerHours(initial).close);
  // 저장 성공 문구는 이후 입력이 바뀌면 숨긴다 — "저장됐어요"가 미저장 수정 위에 남지 않게.
  const [touched, setTouched] = useState(false);
  // 컷오프 상향 확인 창(P14 H1) — 되돌릴 수 없는 결과가 딸린 저장에만 한 단계를 세운다.
  const [confirmCutoff, setConfirmCutoff] = useState(false);

  const parsedMaxHolds = maxHolds.trim() === "" ? NaN : Number(maxHolds);
  const parsedMaxHoldDays = maxHoldDays.trim() === "" ? NaN : Number(maxHoldDays);
  // 0은 서버가 거부한다 — "필드 부재"를 뜻하는 자리라 무제한(-1)과 구분해야 하기 때문이다
  // (백엔드 Policy.NormalizeHoldLimits). 라벨이 -1만 알려주고 0을 막지 않아 400 왕복이 났다(P14 M2).
  const holdsRangeBad = parsedMaxHolds === 0 || parsedMaxHoldDays === 0;
  const holdsValid =
    Number.isInteger(parsedMaxHolds) &&
    Number.isInteger(parsedMaxHoldDays) &&
    parsedMaxHolds >= -1 &&
    parsedMaxHoldDays >= -1 &&
    !holdsRangeBad;

  // 서버 검증 미러(0 ≤ 첫 ＜ 마지막 ≤ 23). 두 칸이 각각은 범위 안이어도 **역전**될 수 있어
  // (첫 20시 · 마지막 8시) 칸별 클램프만으로는 못 막는다 — 홀딩 상한과 같은 자리의 게이트다.
  const hoursOk = hoursValid(openHour, closeHour);
  const slotCount = hoursOk ? closeHour - openHour + 1 : 0;

  // 바뀐 필드만 담은 patch. 위약금율은 % 값끼리 비교한다 — 0~1 소수로 되돌린 뒤 비교하면
  // 부동소수 왕복 오차가 "안 바꿨는데 바뀐 필드"를 만든다.
  const patch: Partial<CenterPolicy> = {};
  if (slotCapacity !== baseline.slot_capacity) patch.slot_capacity = slotCapacity;
  if (cutoffHours !== baseline.cancel_cutoff_hours) patch.cancel_cutoff_hours = cutoffHours;
  if (graceOnce !== baseline.grace_once) patch.grace_once = graceOnce;
  if (penaltyPct !== pctOf(baseline.penalty_rate)) patch.penalty_rate = penaltyPct / 100;
  if (revenueTarget !== baseline.revenue_target) patch.revenue_target = revenueTarget;
  if (reregWindowDays !== baseline.rereg_window_days) patch.rereg_window_days = reregWindowDays;
  if (longAbsentDays !== baseline.long_absent_days) patch.long_absent_days = longAbsentDays;
  if (expiringDays !== baseline.expiring_days) patch.expiring_days = expiringDays;
  if (holdsValid) {
    if (parsedMaxHolds !== baseline.max_holds_per_pass) patch.max_holds_per_pass = parsedMaxHolds;
    if (parsedMaxHoldDays !== baseline.max_hold_total_days) {
      patch.max_hold_total_days = parsedMaxHoldDays;
    }
  }
  // 운영시간도 **접은 값끼리** 비교한다(위약금율을 % 값끼리 비교하는 것과 같은 이유): 필드가
  // 없던 응답의 기준선은 9/21이므로, 대표가 9/21 그대로 두면 patch에 실리지 않는다 — 서버는
  // 계속 "필드 부재 = 9/21"로 같은 결과를 낸다. 값을 실제로 바꾼 순간에만 나간다.
  if (hoursOk) {
    const base = centerHours(baseline);
    if (openHour !== base.open) patch.open_hour = openHour;
    if (closeHour !== base.close) patch.close_hour = closeHour;
  }
  const changedCount = Object.keys(patch).length;
  // 컷오프를 **올릴 때만** 확인한다. 내리는 쪽은 페널티 구간이 줄어드는 방향이라 회원에게
  // 불리한 결과가 새로 생기지 않는다.
  const raisingCutoff =
    patch.cancel_cutoff_hours !== undefined && cutoffHours > baseline.cancel_cutoff_hours;

  // 이 창을 연 뒤 **다른 창·다른 대표가** 정책을 바꿨나. 조용히 지나가면 화면의 숫자와 실제
  // 정책이 다른 채로 대표가 돈과 약관을 판단하게 된다. (내 저장은 성공 시 baseline을 갱신하므로
  // 여기 걸리지 않는다 — 아래 save의 onSuccess 참고.)
  const serverMoved =
    (Object.keys(baseline) as (keyof CenterPolicy)[]).some((k) => baseline[k] !== initial[k]) ||
    // 운영시간만 따로 한 번 더 본다: baseline의 **키 순회**라 "없던 필드가 생기는" 변화를 놓친다
    // (구서버 응답으로 창을 연 뒤 다른 창이 처음으로 운영시간을 저장한 경우가 정확히 그 모양이다).
    centerHours(baseline).open !== centerHours(initial).open ||
    centerHours(baseline).close !== centerHours(initial).close;

  function save() {
    if (!holdsValid || !hoursOk || changedCount === 0) return;
    setTouched(false);
    setConfirmCutoff(false);
    // 저장이 끝나면 서버가 돌려준 정책이 새 기준선이다 — 그래야 다음 patch가 다시 "내가 바꾼
    // 것"만 담고, "다른 창에서 바뀜" 안내가 내 저장에 반응하지 않는다.
    updatePolicy.mutate(patch, { onSuccess: (center) => setBaseline(center.policy) });
  }

  // 빈 칸·불량 입력을 0으로 접지 않는다(P14 L1) — 용량 칸을 지우면 0이 되어 서버 400이 났다.
  // 위약금율만 클램프하던 것을 전 숫자 칸의 공통 규약으로 올린다.
  const clamped = (v: string, min: number, max: number) => {
    const n = Number(v);
    if (v.trim() === "" || !Number.isFinite(n)) return min;
    return Math.min(max, Math.max(min, n));
  };

  return (
    <div>
      {/* React onChange는 버블링된다 — 그리드 어느 필드가 바뀌어도 성공 문구를 숨긴다. */}
      <div className="grid grid-cols-2 gap-2" onChange={() => setTouched(true)}>
        {/* 운영시간 — 예약 화면의 시간 격자를 만드는 값이라 정책 중 가장 먼저 읽혀야 한다.
            **두 값 다 "수업이 시작하는 시각"이고 양끝을 포함한다**(9~21 = 13타임, 마지막 수업이
            21:00 시작). 라벨을 "여는 시간/닫는 시간"으로 쓰면 21시를 마감으로 읽어 실제로는
            20시까지만 받는 줄 알게 되므로, 라벨과 미리보기 양쪽에서 시작 시각임을 못박는다. */}
        <div className="col-span-2">
          <div className="grid grid-cols-2 gap-2">
            <div>
              <Label>첫 수업 시작 시간 (0~23시)</Label>
              <Input
                type="number"
                min={0}
                max={23}
                step={1}
                value={openHour}
                // 정수로 접는다(ProfileModal 연차 칸과 같은 규약) — "9.5"가 들어오면 아래 범위
                // 경고가 **역전이 아닌 이유**로 뜨면서 문구가 상황과 어긋난다.
                onChange={(e) => setOpenHour(Math.round(clamped(e.target.value, 0, 23)))}
              />
            </div>
            <div>
              <Label>마지막 수업 시작 시간 (0~23시)</Label>
              <Input
                type="number"
                min={0}
                max={23}
                step={1}
                value={closeHour}
                onChange={(e) => setCloseHour(Math.round(clamped(e.target.value, 0, 23)))}
              />
            </div>
          </div>
          {hoursOk ? (
            <p className="mt-1 text-[10.5px] leading-[1.7] text-muted">
              <b className="text-ink">
                {hourLabel(openHour)}부터 {hourLabel(closeHour)} 시작까지 · 하루 {slotCount}타임
              </b>{" "}
              — 마지막 수업은 {hourLabel(closeHour)}에 <b className="text-ink">시작</b>합니다(문
              닫는 시각이 아니에요).
            </p>
          ) : (
            <p className="mt-1 text-[11px] text-warn">
              첫 수업 시간이 마지막 수업 시간보다 빨라야 해요 — 0~23시 사이에서 첫 시간을 마지막보다
              앞에 두고 입력해야 저장할 수 있어요.
            </p>
          )}
          {/* 정직 고지 — 회원 앱은 아직 09~21을 코드에 박고 있고 스토어 업데이트가 나가야 풀린다. */}
          <p className="mt-1 text-[10.5px] leading-[1.7] text-muted">
            바꾼 시간은 데스크·어드민 예약 화면에 바로 적용되고,{" "}
            <b className="text-ink">회원 앱에는 다음 앱 업데이트부터</b> 반영돼요.
          </p>
        </div>
        <div>
          <Label>시간당 예약 용량 (팀, 1~10)</Label>
          <Input
            type="number"
            min={1}
            max={10}
            value={slotCapacity}
            onChange={(e) => setSlotCapacity(clamped(e.target.value, 1, 10))}
          />
        </div>
        <div>
          <Label>취소 컷오프 (시간, 0~168)</Label>
          <Input
            type="number"
            min={0}
            max={168}
            value={cutoffHours}
            onChange={(e) => setCutoffHours(clamped(e.target.value, 0, 168))}
          />
        </div>
        <div>
          <Label>위약금율 (%, 상한 {MAX_PENALTY_PCT}%)</Label>
          <Input
            type="number"
            min={0}
            max={MAX_PENALTY_PCT}
            step={0.1}
            value={penaltyPct}
            onChange={(e) => setPenaltyPct(clamped(e.target.value, 0, MAX_PENALTY_PCT))}
          />
        </div>
        <div>
          <Label>연 매출 목표 (원 · 0 = 미설정)</Label>
          <Input
            type="number"
            min={0}
            step={1_000_000}
            value={revenueTarget}
            onChange={(e) => setRevenueTarget(clamped(e.target.value, 0, Number.MAX_SAFE_INTEGER))}
          />
        </div>
        <div>
          <Label>재등록 인정기간 (일)</Label>
          <Input
            type="number"
            min={0}
            value={reregWindowDays}
            onChange={(e) => setReregWindowDays(clamped(e.target.value, 0, 3650))}
          />
        </div>
        <div>
          <Label>장기 미출석 기준 (일)</Label>
          <Input
            type="number"
            min={0}
            value={longAbsentDays}
            onChange={(e) => setLongAbsentDays(clamped(e.target.value, 0, 3650))}
          />
        </div>
        <div>
          <Label>만료 임박 기준 (일)</Label>
          <Input
            type="number"
            min={0}
            value={expiringDays}
            onChange={(e) => setExpiringDays(clamped(e.target.value, 0, 3650))}
          />
        </div>
        <div>
          <Label>회원 셀프 홀딩 최대 횟수 (1 이상 · -1 = 무제한)</Label>
          <Input
            type="number"
            min={-1}
            step={1}
            value={maxHolds}
            onChange={(e) => setMaxHolds(e.target.value)}
          />
        </div>
        <div>
          <Label>회원 셀프 홀딩 총 일수 (1 이상 · -1 = 무제한)</Label>
          <Input
            type="number"
            min={-1}
            step={1}
            value={maxHoldDays}
            onChange={(e) => setMaxHoldDays(e.target.value)}
          />
        </div>
        <div className="flex items-end pb-2">
          <label className="flex items-center gap-2 text-[12.5px]">
            <input
              type="checkbox"
              checked={graceOnce}
              onChange={(e) => setGraceOnce(e.target.checked)}
            />
            노쇼 최초 1회 유예
          </label>
        </div>
      </div>

      {/* 홀딩 상한이 **회원 셀프 홀딩에만** 걸린다는 한정어(P14 M1). 서버는 member 호출일 때만
          정책을 읽어 ValidateNewHold를 태운다(service.CreateHold) — 데스크에서 거는 홀딩은
          이 상한을 지나지 않는다. 도메인 주석엔 그렇게 적혀 있는데 화면이 한정어를 떨어뜨렸다. */}
      <p className="mt-2 text-[10.5px] text-muted">
        홀딩 상한 2개는 <b className="text-ink">회원이 앱에서 직접 거는 홀딩</b>에만 걸립니다 —
        데스크(어드민)에서 거는 홀딩은 이 상한과 무관하게 처리돼요.
      </p>

      {!holdsValid && (
        <p className="mt-2 text-[11px] text-warn">
          {holdsRangeBad
            ? "홀딩 상한에 0은 넣을 수 없어요 — 최소 1회·1일은 항상 허용됩니다(홀딩을 완전히 막는 설정은 없어요). 무제한은 -1이에요."
            : "홀딩 상한 2개 필드는 1 이상의 정수 또는 -1(무제한)로 입력해주세요 — 입력해야 저장할 수 있어요."}
        </p>
      )}

      {/* 컷오프를 올리는 순간 무슨 일이 벌어지는지, 저장 버튼을 누르기 **전에** 보여준다. */}
      {raisingCutoff && (
        <CutoffRaiseNotice from={initial.cancel_cutoff_hours} to={cutoffHours} />
      )}

      {serverMoved && (
        <p className="mt-2 rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] leading-[1.8] text-warn">
          <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />이 창을 연 뒤 다른 곳에서
          정책이 바뀌었어요 — 화면의 값은 그때 것입니다. 저장해도{" "}
          <b>내가 바꾼 항목만</b> 덮어쓰지만, 최신 값을 보려면 새로고침해주세요.
        </p>
      )}
      {updatePolicy.isSuccess && !touched && (
        <p className="mt-2 text-[11px] text-ok">
          <Check className="mr-1 inline h-3 w-3" />
          저장됐어요 — {POLICY_EFFECT_NOTE}
        </p>
      )}
      {updatePolicy.isError && (
        <p className="mt-2 text-[11px] text-danger">{updatePolicy.error.message}</p>
      )}

      <Button
        className="mt-2.5 w-full"
        disabled={updatePolicy.isPending || !holdsValid || !hoursOk || changedCount === 0}
        onClick={() => (raisingCutoff ? setConfirmCutoff(true) : save())}
      >
        <Save className="h-4 w-4" />{" "}
        {updatePolicy.isPending
          ? "저장 중…"
          : // 운영시간이 어긋나면 시간 칸 값이 patch에서 빠져 changedCount가 0이 될 수 있다 —
            // 그대로면 버튼이 "바뀐 항목 없음"이라고 **틀린 이유**를 말한다(FacilityEditForm의
            // "신고번호를 입력해주세요"와 같은 자리).
            !hoursOk
            ? "운영시간을 확인해주세요"
            : changedCount === 0
              ? "바뀐 항목 없음"
              : `저장 (${changedCount}개 항목)`}
      </Button>
      <p className="mt-2.5 text-[10.5px] text-muted">
        현재 위약금율 {penaltyPct}%(상한 {MAX_PENALTY_PCT}%) · 연 매출 목표{" "}
        {revenueTarget > 0 ? formatCurrency(revenueTarget) : "미설정"}. 위약금율은 환불에서 실제로
        공제되는 값이자 새 계약서에 인쇄되는 값이에요 — 상한을 넘는 값은 서버가 저장 전에
        거부합니다. 바뀐 항목만 저장하므로 다른 창에서 먼저 저장한 값은 되돌아가지 않아요.
      </p>

      {confirmCutoff && (
        <CutoffRaiseModal
          from={initial.cancel_cutoff_hours}
          to={cutoffHours}
          pending={updatePolicy.isPending}
          onCancel={() => setConfirmCutoff(false)}
          onConfirm={save}
        />
      )}
    </div>
  );
}

// 0~1 소수 → % 표시값. 0.125 → 12.5 (부동소수 노이즈만 제거, 0.01%p 해상도).
function pctOf(rate: number): number {
  return Math.round(rate * 10000) / 100;
}

// 컷오프 상향으로 **새로 페널티 구간에 들어가는** 확정 예약(P14 H1).
//
// 예약 시점엔 무료 취소였는데 저장 순간부터 취소 시 세션이 차감되는 수업들이다:
// 시작 시각이 (지금+옛 컷오프, 지금+새 컷오프] 구간에 든 confirmed 예약.
// 서버는 취소 시점에 정책을 새로 읽으므로(service.CancelBooking) 아무도 통보받지 못한다.
function useCutoffImpact(fromHours: number, toHours: number) {
  // 컷오프를 올리는 중일 때만 이 훅이 마운트된다 — 예약 목록을 평소에 끌어오지 않는다.
  const bookingsQ = useBookings(todayStr());
  if (bookingsQ.isLoading) return { count: 0, loading: true, unknown: false };
  // 조회 실패를 "0건"으로 위장하지 않는다 — 없는 것과 모르는 것은 다르다.
  if (bookingsQ.isError || !bookingsQ.data) return { count: 0, loading: false, unknown: true };
  const now = Date.now();
  const fromEdge = now + fromHours * 3_600_000;
  const toEdge = now + toHours * 3_600_000;
  const count = bookingsQ.data.filter((b) => {
    if (b.status !== "confirmed") return false;
    const start = slotKeyStart(b.slot_key);
    return start !== null && start.getTime() > fromEdge && start.getTime() <= toEdge;
  }).length;
  return { count, loading: false, unknown: false };
}

function cutoffImpactText(impact: ReturnType<typeof useCutoffImpact>): string {
  if (impact.loading) return "영향받는 예약을 세는 중…";
  if (impact.unknown) return "영향받는 예약 수를 확인하지 못했어요(예약 목록 조회 실패)";
  return impact.count > 0
    ? `지금 확정된 예약 ${impact.count}건이 저장 즉시 페널티 구간에 들어갑니다`
    : "지금은 새로 페널티 구간에 들어가는 확정 예약이 없어요";
}

// 저장 전 인라인 예고 — 버튼을 누르기 전에 대가를 먼저 읽게 한다.
function CutoffRaiseNotice({ from, to }: { from: number; to: number }) {
  const impact = useCutoffImpact(from, to);
  return (
    <p className="mt-2 rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] leading-[1.8] text-warn">
      <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />
      컷오프를 {from}시간 → {to}시간으로 올리면 <b>이미 잡힌 예약에도 바로 적용</b>됩니다.{" "}
      {cutoffImpactText(impact)}.
    </p>
  );
}

// 컷오프 상향 확인 — 되돌릴 수 없는 결과가 딸린 유일한 정책 저장이라 한 단계를 세운다
// (가입 요청 승인과 같은 자리). 정책값 자체는 되돌릴 수 있지만, 그 사이에 생긴 원장 항목과
// 차감된 세션은 정책을 되돌려도 남는다.
function CutoffRaiseModal({
  from,
  to,
  pending,
  onCancel,
  onConfirm,
}: {
  from: number;
  to: number;
  pending: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const impact = useCutoffImpact(from, to);
  return (
    <Modal open onClose={onCancel} title="취소 컷오프를 올립니다">
      <div className="space-y-3">
        <p className="text-[12.5px]">
          무료 취소 마감을 <b>{from}시간 전 → {to}시간 전</b>으로 바꿉니다.
        </p>
        <div className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2.5">
          <div className="flex items-center gap-1 text-[11.5px] font-extrabold text-warn">
            <TriangleAlert className="h-3.5 w-3.5" /> 이미 잡힌 예약에도 소급됩니다
          </div>
          <p className="mt-1 text-[10.5px] leading-[1.8] text-muted">
            서버는 취소가 일어나는 <b className="text-ink">그 시점의 정책</b>으로 판정합니다 —
            예약할 때는 없던 페널티 구간에 회원이 이미 들어가 있게 되고, 아무도 통보받지 않아요.{" "}
            <b className="text-ink">{cutoffImpactText(impact)}.</b>
          </p>
          <p className="mt-1.5 text-[10.5px] leading-[1.8] text-muted">
            정책값은 되돌릴 수 있지만 그 사이에 생긴{" "}
            <b className="text-ink">원장 차감과 소진된 노쇼 유예는 되돌아가지 않습니다</b>. 회원에게
            먼저 안내한 뒤 바꾸시는 걸 권해요.
          </p>
        </div>
        <Button className="w-full" disabled={pending} onClick={onConfirm}>
          <Save className="h-4 w-4" /> {pending ? "저장 중…" : "알겠어요, 저장할게요"}
        </Button>
        <Button className="w-full" variant="outline" onClick={onCancel}>
          취소
        </Button>
      </div>
    </Modal>
  );
}

// ── 사업자 정보(v2.13, PUT /v1/center {business} — owner 전용) ─────────────────────────

// businessOf — 응답에서 사업자 정보를 꺼내되, **없으면 미등록과 같은 모양으로 접는다**.
//
// 타입은 business를 필수로 선언한다(계약이 그렇게 약속한다). 이 한 겹은 그 약속이 깨지는 유일한
// 창을 위한 것이다: 계약 v2.13 "배포 순서"는 서버 먼저를 요구하는데, 어드민이 먼저 뜨면 응답에
// business가 없다. 그때 대가가 "사업자 정보 칸이 빈다"가 아니라 **설정 화면 전체가 흰 화면**이라는
// 게 문제다 — 직원 관리·운영 정책·가입 승인이 같이 죽는다. 접어 두면 그 순간이 장애가 아니라
// "아직 등록 전"으로 보이고, 서버가 뜨는 순간 저절로 낫는다.
function businessOf(c: Center): CenterBusinessView {
  return c.business ?? EMPTY_BUSINESS;
}

// 저장 직후 무엇이 달라지는지. 정책과 달리 예약·정산은 하나도 움직이지 않고 **문서에 인쇄되는
// 글자만** 바뀐다 — 대표가 "저장했는데 뭐가 바뀐 거지"를 묻지 않게 그 사실을 그대로 적는다.
const BUSINESS_EFFECT_NOTE =
  "이용약관 · 개인정보처리방침 · 민감정보 동의 · 계정 삭제 안내 4개 문서가 다음 열람부터 이 값을 인쇄해요.";

// 칸별 입력 힌트. 12칸이 전부 같은 텍스트 입력이라 폼을 BUSINESS_FIELD_KEYS 순회로 그리는데,
// 그러면 칸마다 다른 예시·키보드·폭을 줄 자리가 없어진다. 순서와 라벨의 단일 출처(types.ts)는
// 그대로 두고 칸별 차이만 여기 모은다 — JSX를 12번 복사해 두면 한 칸을 고칠 때 나머지 11칸이
// 조용히 어긋나고, 서버가 정한 폼 순서와 화면 순서가 갈라진다.
const BUSINESS_INPUT_HINT: Record<
  keyof CenterBusiness,
  { placeholder?: string; type?: string; inputMode?: "tel"; wide?: boolean }
> = {
  biz_name: { placeholder: "라이즈 컨디셔닝" },
  ceo_name: { placeholder: "홍길동" },
  // inputMode는 numeric이 아니라 tel이다 — numeric 키패드에는 하이픈이 없어 예시(123-45-67890)를
  // 그대로 따라 칠 수 없다. 하이픈 없이 10자리만 쳐도 서버가 정규화하지만, 화면이 보여준 모양을
  // 입력할 수 없는 상태를 만들 이유는 없다.
  biz_reg_no: { placeholder: "123-45-67890", inputMode: "tel" },
  // 도로명 + 상세주소는 이름 칸과 같은 폭에 넣으면 실제 값 대부분이 잘려 보인다 — 두 칸을 합친다.
  address: { placeholder: "서울특별시 강남구 …", wide: true },
  phone: { placeholder: "02-1234-5678", inputMode: "tel" },
  email: { placeholder: "help@example.com", type: "email" },
  privacy_officer_name: { placeholder: "홍길동" },
  privacy_officer_title: { placeholder: "센터장" },
  privacy_officer_email: { placeholder: "privacy@example.com", type: "email" },
  privacy_dept: { placeholder: "고객지원팀" },
  privacy_manager: { placeholder: "김담당" },
  // 달력 입력이면 존재하지 않는 날짜를 애초에 고를 수 없다. 그래도 아래 검증을 두는 이유는
  // 붙여넣기·자동완성으로 들어오는 값 때문이다(브라우저마다 허용 범위가 다르다).
  effective_date: { type: "date" },
};

/**
 * 서버 domain.Business.Validate 미러 — **칸 하나의 이유**를 돌려준다(null = 통과).
 *
 * 서버 400 문구에 기대지 않는 이유는 PoseSequenceEditor 헤더 주석과 같은 자리다: 400은 첫 실패에서
 * 곧바로 돌아오므로 한 번에 한 칸만 말하고, 그마저 **어느 입력 상자**인지는 알려주지 않는다.
 * 12칸짜리 폼에서 그건 "저장 → 거절 → 범인 찾기"를 열두 번 반복하라는 뜻이다.
 *
 * **빈 값은 언제나 통과다.** 대표는 사업자등록증을 보며 아는 칸부터 채우고 보호책임자 지정은 그
 * 뒤에 온다 — 전부 채워야 저장되면 중간 저장이 불가능해 결국 메모장에 적어 두게 된다. 서버가
 * "저장 가능 조건"과 "문서 게시 조건(complete)"을 나눠 둔 설계를 화면도 그대로 따른다.
 */
function businessFieldError(key: keyof CenterBusiness, raw: string): string | null {
  // 서버는 검증 **전에** Normalize(앞뒤 공백 제거)를 태운다 — 판정 기준을 같은 모양에서 맞춘다.
  // 이걸 빼면 붙여넣기에 딸려 온 공백 한 칸 때문에 화면만 빨개지고 서버는 저장에 성공한다.
  const v = raw.trim();
  if (v === "") return null;
  const len = [...v].length; // 코드 포인트 — 서버 len([]rune(s))와 같은 수를 센다
  const label = BUSINESS_FIELD_LABEL[key];
  switch (key) {
    case "biz_reg_no": {
      const digits = v.replace(/-/g, "");
      return digits.length === BUSINESS_REG_NO_DIGITS && /^[0-9]+$/.test(digits)
        ? null
        : `사업자등록번호는 숫자 ${BUSINESS_REG_NO_DIGITS}자리여야 해요(예: 123-45-67890)`;
    }
    case "phone":
      return len <= BUSINESS_PHONE_MAX && isDialable(v)
        ? null
        : "대표 전화 형식이 올바르지 않아요(예: 02-1234-5678)";
    case "email":
    case "privacy_officer_email":
      return len <= BUSINESS_EMAIL_MAX && isEmailLike(v)
        ? null
        : `${label} 형식이 올바르지 않아요(예: help@example.com)`;
    case "effective_date":
      return isCalendarDate(v) ? null : "약관 시행일은 YYYY-MM-DD 형식이어야 해요(예: 2026-09-01)";
    case "address":
      return len <= BUSINESS_ADDRESS_MAX ? null : `${label}은(는) ${BUSINESS_ADDRESS_MAX}자까지예요`;
    default:
      // 나머지 6칸(이름·직책·부서·담당자)은 서버에서도 같은 상한 하나를 공유한다.
      return len <= BUSINESS_NAME_MAX ? null : `${label}은(는) ${BUSINESS_NAME_MAX}자까지예요`;
  }
}

// 서버 isDialable 미러 — 숫자 8~15개 + 하이픈 + **맨 앞의** +만. 회원 휴대폰(phone.go)의 010
// 정규화를 태우지 않는 이유도 서버와 같다: 센터 대표번호는 02·031·1544가 정상이라 010 규칙으로
// 접으면 실제로 거는 번호가 화면에서 거부된다.
function isDialable(s: string): boolean {
  let digits = 0;
  for (const [i, ch] of [...s].entries()) {
    if (ch >= "0" && ch <= "9") digits++;
    else if (ch === "-") continue;
    else if (ch === "+" && i === 0) continue;
    else return false;
  }
  return digits >= BUSINESS_PHONE_DIGITS_MIN && digits <= BUSINESS_PHONE_DIGITS_MAX;
}

// 서버 isEmailLike 미러 — local@domain · @ 정확히 하나 · 도메인 라벨 2개 이상(빈 라벨 금지) ·
// 공백 없음. RFC 5322 전체를 구현하지 않는 것도 서버와 같은 판단이다: 여기서 걸러야 하는 건
// "hello", "hello@rise" 같은 **오타**지 희귀 문법이 아니고, 지나치게 엄격한 판정은 대표가 실제로
// 쓰는 주소를 막아 등록 자체를 못 하게 만든다. 공백도 서버와 **같은 4글자**(스페이스·탭·CR·LF)만
// 본다 — 정규식 \s로 넓히면 서버가 받아주는 값을 화면이 먼저 거절한다(미러의 방향이 뒤집힌다).
function isEmailLike(s: string): boolean {
  const at = s.indexOf("@");
  if (at <= 0 || at !== s.lastIndexOf("@") || at === s.length - 1) return false;
  if (/[ \t\r\n]/.test(s)) return false;
  const labels = s.slice(at + 1).split(".");
  return labels.length >= 2 && labels.every((l) => l !== "");
}

// 서버는 time.Parse("2006-01-02")를 쓴다 — 모양뿐 아니라 **실재하는 날짜**여야 한다(2026-02-30 ·
// 2026-13-01 거부). Date 생성자로 검사하지 않는 이유: new Date("2026-02-30")은 3월 2일로 굴러가
// 통과시키고, Date.UTC는 0~99년을 1900년대로 옮겨 4자리 연도를 왜곡한다. 자릿수 검사 + 그 달의
// 마지막 날 비교면 브라우저 구현에 기대지 않고 서버와 같은 답이 나온다.
function isCalendarDate(s: string): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return false;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  if (mo < 1 || mo > 12 || d < 1) return false;
  const leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  return d <= [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mo - 1];
}

/**
 * 사업자등록번호 검사식(국세청 규칙). **저장을 막지 않는 경고 전용**이다.
 *
 * 서버가 일부러 이 검사를 하지 않는 이유를 화면도 그대로 따른다: 오탐 한 번이 이 값을 고칠 수 있는
 * **유일한 사람**(대표)을 완전히 막아 세운다. 우리가 모르는 예외 번호 하나에 "당신의 사업자등록증이
 * 틀렸다"고 우기는 화면이 되는 셈이고, 그 순간 법정 고지 등록 자체가 불가능해진다. 그래서 판정이
 * 아니라 "한 번 더 대조해 달라"는 힌트로만 쓴다 — 오타는 대부분 여기서 걸리고, 예외는 통과한다.
 */
function bizRegNoCheckDigitOk(digits: string): boolean {
  const d = [...digits].map(Number);
  const weights = [1, 3, 7, 1, 3, 7, 1, 3, 5];
  let sum = 0;
  for (let i = 0; i < 9; i++) sum += d[i] * weights[i];
  sum += Math.floor((d[8] * 5) / 10);
  return (10 - (sum % 10)) % 10 === d[9];
}

// 응답(complete 포함)에서 **저장 가능한 12칸만** 뽑는다. complete를 그대로 되돌려 보내면 400이다 —
// 서버 디코더가 DisallowUnknownFields라 파생값 하나가 요청 전체를 거절시킨다. 애초에 complete는
// 서버가 12칸을 세서 만드는 값이라 클라이언트가 보낼 의미도 없다.
function pickBusiness(v: CenterBusinessView): CenterBusiness {
  const out = {} as CenterBusiness;
  for (const k of BUSINESS_FIELD_KEYS) out[k] = v[k];
  return out;
}

/**
 * 사업자 정보 편집 폼(v2.13, PUT /v1/center {business} — owner 전용).
 *
 * **12칸을 항상 전부 보낸다**(통 교체). 정책 폼과 정반대인데 이유가 있다: 서버가 통 교체라
 * 빠뜨린 칸은 머지가 아니라 빈 값으로 저장되고, 그 성질 덕분에 **잘못 적은 칸을 비워서 지우는 일**이
 * 가능해진다(머지였다면 한 번 들어간 오타를 지울 방법이 없다).
 *
 * 그래도 baseline은 PolicyEditForm과 같은 이유로 마운트 시점에 얼린다: initial은 폴링·창 포커스
 * 재조회로 움직이는 살아 있는 prop이라, 그대로 비교하면 다른 창이 방금 저장한 값이 "내가 바꾼 것"으로
 * 둔갑해 dirty 판정이 흔들린다. 다만 여기서 baseline이 쓰이는 곳은 patch를 만드는 자리가 아니라
 * **저장 버튼을 열어도 되는가**와 "다른 곳에서 바뀜" 경고뿐이다.
 */
function BusinessEditForm({ initial }: { initial: CenterBusinessView }) {
  const updateBusiness = useUpdateCenterBusiness();
  const [baseline, setBaseline] = useState<CenterBusiness>(() => pickBusiness(initial));
  const [form, setForm] = useState<CenterBusiness>(() => pickBusiness(initial));
  // 저장 성공 문구는 이후 입력이 바뀌면 숨긴다 — "저장됐어요"가 미저장 수정 위에 남지 않게.
  const [touched, setTouched] = useState(false);

  const setField = (key: keyof CenterBusiness, value: string) => {
    setForm((prev) => ({ ...prev, [key]: value }));
    setTouched(true);
  };

  const errors: Partial<Record<keyof CenterBusiness, string>> = {};
  for (const k of BUSINESS_FIELD_KEYS) {
    const msg = businessFieldError(k, form[k]);
    if (msg) errors[k] = msg;
  }
  const invalidCount = BUSINESS_FIELD_KEYS.filter((k) => errors[k]).length;

  // 서버 Normalize가 앞뒤 공백을 털고 저장하므로, 공백만 늘린 값은 서버 입장에서 "안 바뀜"이다.
  // 그대로 비교하면 아무것도 달라지지 않는 저장 요청을 열어 주게 된다.
  const changedCount = BUSINESS_FIELD_KEYS.filter((k) => form[k].trim() !== baseline[k].trim()).length;

  // "무엇이 남았는가"는 저장된 값이 아니라 **지금 화면의 값**으로 센다 — 채우는 동안 목록이 줄어드는
  // 게 보여야 12칸을 끝까지 채우게 된다. 카드 헤더 배지는 반대로 서버 complete를 쓴다(그쪽은
  // 저장된 사실, 즉 문서가 지금 어떤 상태인지를 말해야 하는 자리다).
  const missing = businessMissingFields(form);

  // 사업자등록번호 오타 힌트 — 형식(10자리)은 맞는데 검사식이 틀린 경우에만. 저장은 막지 않는다.
  const regDigits = form.biz_reg_no.replace(/-/g, "");
  const regCheckWarn =
    !errors.biz_reg_no &&
    regDigits.length === BUSINESS_REG_NO_DIGITS &&
    /^[0-9]+$/.test(regDigits) &&
    !bizRegNoCheckDigitOk(regDigits);

  // 이 창을 연 뒤 **다른 창·다른 대표가** 사업자 정보를 바꿨나. 정책 폼보다 결과가 무겁다:
  // 통 교체라 지금 저장하면 그쪽이 채워 넣은 칸까지 내 화면의 옛 값으로 통째로 덮인다.
  // (내 저장은 성공 시 baseline을 갱신하므로 여기 걸리지 않는다 — 아래 save의 onSuccess 참고.)
  const serverMoved = BUSINESS_FIELD_KEYS.some((k) => baseline[k] !== initial[k]);

  function save() {
    if (invalidCount > 0 || changedCount === 0) return;
    setTouched(false);
    const payload = {} as CenterBusiness;
    for (const k of BUSINESS_FIELD_KEYS) payload[k] = form[k].trim();
    updateBusiness.mutate(payload, {
      // 서버가 돌려준 값이 새 기준선이자 새 화면 값이다. 응답을 화면에 되꽂지 않으면 서버가
      // 정규화한 사업자등록번호(1234567890 → 123-45-67890)와 입력칸이 어긋나, 방금 저장한 폼이
      // 곧바로 "바뀐 항목 1개"로 되살아나 미저장처럼 보인다.
      onSuccess: (center) => {
        setBaseline(pickBusiness(center.business));
        setForm(pickBusiness(center.business));
      },
    });
  }

  return (
    <div>
      <div className="grid grid-cols-2 gap-2">
        {BUSINESS_FIELD_KEYS.map((k) => {
          const hint = BUSINESS_INPUT_HINT[k];
          return (
            <div key={k} className={hint.wide ? "col-span-2" : undefined}>
              <Label>{BUSINESS_FIELD_LABEL[k]}</Label>
              <Input
                type={hint.type}
                inputMode={hint.inputMode}
                placeholder={hint.placeholder}
                value={form[k]}
                onChange={(e) => setField(k, e.target.value)}
              />
              {errors[k] && <p className="mt-1 text-[10.5px] text-danger">{errors[k]}</p>}
              {k === "biz_reg_no" && regCheckWarn && (
                <p className="mt-1 text-[10.5px] text-warn">
                  사업자등록증의 번호와 한 번 더 대조해 주세요 — 저장은 그대로 됩니다.
                </p>
              )}
            </div>
          );
        })}
      </div>

      {/* 저장 가능 조건(형식)과 게시 가능 조건(12칸 완성)이 다르다는 사실을, 지금 어느 쪽에
          서 있는지와 함께 보여준다. 이 안내가 없으면 "저장됐어요"를 문서가 시행 중이라는
          뜻으로 읽게 되고, 그 상태로 심사 제출·회원 고지가 나간다. */}
      {missing.length > 0 ? (
        <div className="mt-2 rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] leading-[1.8] text-warn">
          <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />
          아직 <b>{missing.length}칸</b>이 비어 있어요 —{" "}
          {missing.map((k) => BUSINESS_FIELD_LABEL[k]).join(" · ")}.
          <br />
          이 상태에서는 <b>이용약관 · 개인정보처리방침 · 민감정보 동의 · 계정 삭제 안내</b> 4개 문서가
          모두 <b>초안</b>으로 남습니다. 12칸을 전부 채우고 약관 시행일까지 지정해야 시행 상태가 돼요
          — 그 전에는 <b>앱스토어 심사 제출이나 회원 고지에 쓰면 안 됩니다</b>.
        </div>
      ) : changedCount > 0 ? (
        <div className="mt-2 rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] leading-[1.8] text-warn">
          <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />
          12칸이 모두 채워졌지만 <b>아직 저장 전</b>이에요. 저장해야 4개 문서가 초안을 벗습니다 —
          저장 전까지는 심사 제출·회원 고지에 쓰면 안 됩니다.
        </div>
      ) : initial.complete ? (
        <div className="mt-2 rounded-[10px] border border-ok/40 bg-ok/10 px-3 py-2 text-[11px] leading-[1.8] text-ok">
          <Check className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />
          12칸이 모두 등록됐어요. 이용약관 · 개인정보처리방침 · 민감정보 동의 · 계정 삭제 안내 4개
          문서가 <b>{form.effective_date} 시행</b>으로 이 값을 인쇄합니다.
        </div>
      ) : null}

      {serverMoved && (
        <p className="mt-2 rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] leading-[1.8] text-warn">
          <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />이 창을 연 뒤 다른 곳에서
          사업자 정보가 바뀌었어요 — 화면의 값은 그때 것입니다. 사업자 정보는{" "}
          <b>12칸을 통째로 덮어쓰기</b> 때문에 지금 저장하면 그쪽에서 채운 칸도 화면의 옛 값으로
          되돌아갑니다. 새로고침으로 최신 값을 먼저 확인해주세요.
        </p>
      )}
      {updateBusiness.isSuccess && !touched && (
        <p className="mt-2 text-[11px] text-ok">
          <Check className="mr-1 inline h-3 w-3" />
          저장됐어요 — {BUSINESS_EFFECT_NOTE}
        </p>
      )}
      {/* 서버 400 문구를 그대로 보여준다 — 미러가 놓친 규칙이 있어도 이유가 화면에 남는다. */}
      {updateBusiness.isError && (
        <p className="mt-2 text-[11px] text-danger">{updateBusiness.error.message}</p>
      )}

      <Button
        className="mt-2.5 w-full"
        disabled={updateBusiness.isPending || invalidCount > 0 || changedCount === 0}
        onClick={save}
      >
        <Save className="h-4 w-4" />{" "}
        {updateBusiness.isPending
          ? "저장 중…"
          : invalidCount > 0
            ? `형식을 확인해주세요 (${invalidCount}칸)`
            : changedCount === 0
              ? "바뀐 항목 없음"
              : `저장 (${changedCount}개 항목)`}
      </Button>
      <p className="mt-2.5 text-[10.5px] leading-[1.8] text-muted">
        빈 칸이 있어도 저장됩니다 — 아는 칸부터 채워 두세요. 다만 <b className="text-ink">12칸이 전부
        채워질 때까지 4개 문서는 초안 상태</b>이고, 저장은 12칸을 통째로 바꾸므로 지운 칸은 실제로
        비워집니다. 사업자등록번호는 저장할 때 서버가 123-45-67890 모양으로 맞춰 줘요.
      </p>
    </div>
  );
}

// ── 체육시설업 신고(P42, PUT /v1/center/facility — owner 전용) ──────────────────────────

// 응답에서 facility 절을 꺼내되, 없으면 **미확인과 같은 모양으로 접는다** — businessOf와 같은
// 자리다. 이 절은 P42 백엔드와 병렬 작업이라 구서버 응답에 아예 없을 수 있고(P41 세션과 배포가
// 엇갈리는 창도 같다), 그 순간이 크래시가 아니라 "아직 미확인"으로 보여야 한다 — 기본값
// unknown이 그 의미와 정확히 일치한다(types.ts EMPTY_FACILITY).
function facilityOf(c: Center): CenterFacility {
  return c.facility ?? EMPTY_FACILITY;
}

// 저장 직후 무엇이 달라지는지 — BUSINESS_EFFECT_NOTE와 같은 자리. 예약·정산은 하나도 움직이지
// 않고 **다음 계약서 발행**만 이 선언을 따른다(이미 발행·서명된 계약은 그대로다).
const FACILITY_EFFECT_NOTE =
  "다음 계약서부터 이 선언을 따라요 — 신고함은 신고번호가 인쇄되고, 신고 대상 아님은 신고번호 행이 빠지고, 미확인은 본문이 발행되지 않습니다.";

// 3단 라디오의 라벨·부연. 순서 고정(기본값 미확인이 맨 위) — 아래로 갈수록 선언의 무게가
// 커진다(신고함 = 신고번호 필요 · 신고 대상 아님 = 관할 구청 확인 선행).
const FACILITY_STATUS_OPTIONS: {
  value: FacilityReportStatus;
  label: string;
  hint: string;
}[] = [
  {
    value: "unknown",
    label: "미확인(기본)",
    hint: "아직 확인 전이에요 — 이 상태에서는 계약서 본문이 발행되지 않아요.",
  },
  {
    value: "reported",
    label: "신고함",
    hint: "체육시설업 신고를 마쳤어요 — 신고번호가 계약서 당사자 표에 인쇄돼요.",
  },
  {
    value: "exempt",
    label: "신고 대상 아님(확인됨)",
    hint: "관할 구청 확인을 마쳤어요 — 계약서에서 신고번호 행이 빠져요.",
  },
];

/**
 * 체육시설업 신고 상태 폼(P42, PUT /v1/center/facility — owner 전용).
 *
 * **3필드를 항상 전부 보낸다**(통 교체 — 와이어 계약이 바디에 3키를 요구한다). 신고번호는
 * 상태가 reported가 아니어도 폼 값 그대로 실어 보낸다: 상태를 잠시 바꿨다 되돌려도 입력해 둔
 * 번호가 사라지지 않고, 서버도 상태에 맞을 때만 계약서에 쓴다.
 *
 * baseline을 마운트 시점에 얼리는 이유는 BusinessEditForm과 같다 — initial은 폴링·창 포커스
 * 재조회로 움직이는 살아 있는 prop이라, 그대로 비교하면 다른 창의 저장이 "내가 바꾼 것"으로
 * 둔갑한다.
 */
function FacilityEditForm({ initial }: { initial: CenterFacility }) {
  const saveFacility = useSaveFacility();
  const radioName = useId();
  const reportNoId = useId();
  const insuranceId = useId();
  const [baseline, setBaseline] = useState<CenterFacility>(initial);
  const [status, setStatus] = useState<FacilityReportStatus>(initial.report_status);
  const [reportNo, setReportNo] = useState(initial.report_no);
  const [insurance, setInsurance] = useState(initial.insurance);
  // 저장 성공 문구는 이후 입력이 바뀌면 숨긴다 — 이웃 폼들과 같은 규약.
  const [touched, setTouched] = useState(false);

  // 서버 400 미러 — "신고함"인데 신고번호가 비면 저장을 잠근다. 판정을 화면이 앞당길 뿐
  // 집행자는 서버다(reported + 빈 번호 400).
  const reportNoMissing = status === "reported" && reportNo.trim() === "";

  // 공백만 늘린 값은 서버 입장에서 "안 바뀜" — BusinessEditForm의 trim 비교와 같은 근거.
  const changedCount = [
    status !== baseline.report_status,
    reportNo.trim() !== baseline.report_no.trim(),
    insurance.trim() !== baseline.insurance.trim(),
  ].filter(Boolean).length;

  // 이 창을 연 뒤 다른 창·다른 대표가 신고 상태를 바꿨나 — 통 교체라 지금 저장하면 그쪽 값이
  // 내 화면의 옛 값으로 덮인다(사업자 정보와 같은 경고 자리).
  const serverMoved =
    baseline.report_status !== initial.report_status ||
    baseline.report_no !== initial.report_no ||
    baseline.insurance !== initial.insurance;

  function save() {
    if (reportNoMissing || changedCount === 0) return;
    setTouched(false);
    saveFacility.mutate(
      { report_status: status, report_no: reportNo.trim(), insurance: insurance.trim() },
      {
        // 서버가 돌려준 값(200 same shape)이 새 기준선이자 새 화면 값 — BusinessEditForm과
        // 같은 재장전. 서버가 정규화한 값과 입력칸이 어긋나 "바뀐 항목"이 되살아나지 않게.
        onSuccess: (f) => {
          setBaseline(f);
          setStatus(f.report_status);
          setReportNo(f.report_no);
          setInsurance(f.insurance);
        },
      },
    );
  }

  return (
    <div>
      <div className="space-y-1.5">
        {FACILITY_STATUS_OPTIONS.map((opt) => (
          <label
            key={opt.value}
            className="flex items-start gap-2 rounded-[10px] bg-panel-2 px-3 py-2"
          >
            <input
              type="radio"
              name={radioName}
              className="mt-0.5"
              checked={status === opt.value}
              onChange={() => {
                setStatus(opt.value);
                setTouched(true);
              }}
            />
            <span className="min-w-0">
              <span className="block text-[12.5px] font-bold">{opt.label}</span>
              <span className="block text-[10.5px] leading-[1.7] text-muted">{opt.hint}</span>
            </span>
          </label>
        ))}
      </div>

      {status === "reported" && (
        <div className="mt-2">
          <Label htmlFor={reportNoId}>신고번호 (필수)</Label>
          <Input
            id={reportNoId}
            value={reportNo}
            placeholder="체육시설업 신고증에 적힌 번호"
            onChange={(e) => {
              setReportNo(e.target.value);
              setTouched(true);
            }}
          />
          {reportNoMissing && (
            <p className="mt-1 text-[10.5px] text-warn">
              "신고함"을 선택하면 신고번호가 필요해요 — 신고증에 적힌 번호를 입력해야 저장할 수
              있어요.
            </p>
          )}
        </div>
      )}

      <div className="mt-2">
        <Label htmlFor={insuranceId}>보증보험 종류·보장내용 (선택)</Label>
        <Textarea
          id={insuranceId}
          rows={2}
          value={insurance}
          placeholder='비워두면 계약서에 "가입하지 않았습니다"로 기재 — 제20조③'
          onChange={(e) => {
            setInsurance(e.target.value);
            setTouched(true);
          }}
        />
      </div>

      {serverMoved && (
        <p className="mt-2 rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] leading-[1.8] text-warn">
          <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />이 창을 연 뒤 다른 곳에서
          신고 상태가 바뀌었어요 — 화면의 값은 그때 것입니다. 저장은{" "}
          <b>3칸을 통째로 덮어쓰기</b> 때문에 지금 저장하면 그쪽에서 바꾼 값도 화면의 옛 값으로
          되돌아갑니다. 새로고침으로 최신 값을 먼저 확인해주세요.
        </p>
      )}
      {saveFacility.isSuccess && !touched && (
        <p className="mt-2 text-[11px] text-ok">
          <Check className="mr-1 inline h-3 w-3" />
          저장됐어요 — {FACILITY_EFFECT_NOTE}
        </p>
      )}
      {/* 서버 400 문구를 그대로 보여준다 — 미러가 놓친 규칙이 있어도 이유가 화면에 남는다. */}
      {saveFacility.isError && (
        <p className="mt-2 text-[11px] text-danger">{saveFacility.error.message}</p>
      )}

      <Button
        className="mt-2.5 w-full"
        disabled={saveFacility.isPending || reportNoMissing || changedCount === 0}
        onClick={save}
      >
        <Save className="h-4 w-4" />{" "}
        {saveFacility.isPending
          ? "저장 중…"
          : reportNoMissing
            ? "신고번호를 입력해주세요"
            : changedCount === 0
              ? "바뀐 항목 없음"
              : `저장 (${changedCount}개 항목)`}
      </Button>
      {/* 안내문 근거(P42 결정 1 · P28 — 계약서doc :810-818 각주): 업종 판단은 실태 기준,
          체력단련장업은 면적 하한 없는 신고 업종, 미신고 영업 처벌은 체육시설법 §38②1,
          기구 미비치 강습 전용 공간의 포섭은 지자체 유권해석 영역. UI에는 출처 없이 사실만. */}
      <p className="mt-2.5 text-[10.5px] leading-[1.8] text-muted">
        업종 판단은 상호가 아니라 시설·운영 <b className="text-ink">실태</b> 기준이에요 —
        "스튜디오"라는 이름과는 무관합니다.
        <br />
        체력단련장업은 면적 하한 없는 <b className="text-ink">신고 업종</b>이에요 — 미신고 영업은
        1년 이하 징역 또는 1천만원 이하 벌금.
        <br />
        기구 없이 강습만 하는 1:1 PT룸은 포섭 여부가 지자체 유권해석 영역이에요 — "신고 대상
        아님"은 관할 구청에 확인한 뒤 선택하세요.
        <br />
        미확인 상태에서는 계약서 본문이 발행되지 않습니다.
      </p>
    </div>
  );
}

function OffdaysModal({ staff, onClose }: { staff: Staff; onClose: () => void }) {
  const [offdays, setOffdays] = useState<string[]>(staff.offdays);
  const [newDate, setNewDate] = useState(todayStr());
  const setOffdaysMut = useSetOffdays();

  // 휴무일은 **앞으로의 예약을 막는** 값이다(service.CreateBooking). 지난 날짜를 넣으면
  // 아무것도 막지 못한 채 목록만 길어지고, 오타(2025→2026)를 잡아줄 것도 없다(P14 L3).
  // 이미 저장돼 있던 과거 휴무는 그대로 둔다 — 지난 기록을 손대는 창이 아니다.
  const past = newDate !== "" && newDate < todayStr();
  const duplicate = offdays.includes(newDate);

  function add() {
    if (!newDate || past || duplicate) return;
    setOffdays((prev) => [...prev, newDate].sort());
  }
  function remove(d: string) {
    setOffdays((prev) => prev.filter((x) => x !== d));
  }

  // 저장 대상이 실제로 바뀌었는지(추가/삭제). 두 목록 모두 정렬 상태로 비교한다 —
  // offdays는 add가 항상 sort해 두고, 서버 값은 순서를 보장하지 않는다.
  const savedSorted = [...staff.offdays].sort();
  const changed =
    offdays.length !== savedSorted.length || offdays.some((d, i) => d !== savedSorted[i]);

  return (
    <Modal open onClose={onClose} title={`휴무 설정 — ${staff.name}`}>
      <div className="space-y-3">
        <div className="flex gap-2">
          <Input
            type="date"
            value={newDate}
            min={todayStr()}
            onChange={(e) => setNewDate(e.target.value)}
          />
          <Button size="sm" variant="outline" onClick={add} disabled={!newDate || past || duplicate}>
            추가
          </Button>
        </div>
        {past && (
          <p className="text-[10.5px] text-warn">
            지난 날짜는 추가할 수 없어요 — 휴무일은 앞으로의 예약을 막는 설정이라 과거에는 효력이
            없습니다.
          </p>
        )}
        {!past && duplicate && (
          <p className="text-[10.5px] text-muted">이미 등록된 휴무일이에요.</p>
        )}
        {!offdays.length ? (
          <p className="text-[11px] text-muted">등록된 휴무일이 없습니다.</p>
        ) : (
          <div className="flex flex-wrap">
            {offdays.map((d) => (
              <Chip key={d} active onClick={() => remove(d)} aria-label={`${d} 휴무 빼기`}>
                {d} ×
              </Chip>
            ))}
          </div>
        )}
        {setOffdaysMut.isError && <p className="text-[11px] text-danger">{setOffdaysMut.error.message}</p>}
        <Button
          className="w-full"
          disabled={setOffdaysMut.isPending || !changed}
          onClick={() => setOffdaysMut.mutate({ uid: staff.uid, offdays }, { onSuccess: onClose })}
        >
          {setOffdaysMut.isPending ? "저장 중…" : changed ? "저장" : "바뀐 항목 없음"}
        </Button>
        <p className="text-[10.5px] text-muted">
          칩을 누르면 목록에서 빠지고, <b className="text-ink">저장을 눌러야 반영</b>됩니다 — 잘못
          눌렀다면 저장하지 말고 창을 닫으면 원래대로예요. 휴무일엔 해당 트레이너의 새 예약(단건·고정
          스케줄 선행 생성)이 서버에서 차단됩니다. 이미 잡힌 예약은 예약 화면에서 개별 조정하세요.
        </p>
      </div>
    </Modal>
  );
}

// ── 트레이너 프로필(v1.6, P05) ──────────────────────────────────────────

// 원형 아바타 — photo_url이 있으면 이미지, 없거나 로드 실패하면 Staff.color 배경 + 이름 첫 글자
// 이니셜(계약 v1.6 폴백 규약). URL이 바뀌면 실패 상태를 리셋해 재시도한다(모달 실시간 미리보기).
function StaffAvatar({
  name,
  color,
  photoUrl,
  size = "sm",
}: {
  name: string;
  color: string;
  photoUrl: string;
  size?: "sm" | "lg";
}) {
  const [broken, setBroken] = useState(false);
  useEffect(() => setBroken(false), [photoUrl]);
  const cls = size === "lg" ? "h-12 w-12 text-[16px]" : "h-7 w-7 text-[11px]";
  if (photoUrl && !broken) {
    return (
      <img
        src={photoUrl}
        alt=""
        onError={() => setBroken(true)}
        className={`${cls} shrink-0 rounded-full border border-line object-cover`}
      />
    );
  }
  return (
    <span
      aria-hidden
      className={`${cls} flex shrink-0 select-none items-center justify-center rounded-full font-extrabold text-white`}
      style={{ background: color || "#f43f5e" }}
    >
      {name.charAt(0)}
    </span>
  );
}

// 프로필 미등록 판정 — 전 필드가 빈 값(계약 v1.6: profile은 항상 객체·배열은 항상 []).
function isProfileEmpty(p: StaffProfile): boolean {
  return (
    !p.photo_url &&
    !p.title &&
    p.career_years === 0 &&
    !p.specialties.length &&
    !p.certifications.length &&
    !p.awards.length &&
    !p.bio
  );
}

// 칩 목록 입력 — 전문분야·자격증·수상 공용(v1.6: 원소 ≤80자·≤20개). 추가는 입력+버튼 또는
// Enter(한글 IME 조합 중 Enter는 isComposing 가드로 무시), 삭제는 칩 클릭(× 표기 —
// OffdaysModal 휴무 칩과 동일 UX). 중복 항목은 조용히 무시한다(휴무일 add와 같은 규약).
function ChipListEditor({
  label,
  values,
  onChange,
  placeholder,
}: {
  label: string;
  values: string[];
  onChange: (next: string[]) => void;
  placeholder: string;
}) {
  const inputId = useId();
  const [draft, setDraft] = useState("");
  const full = values.length >= 20;

  function add() {
    const v = draft.trim();
    if (!v || values.includes(v) || full) return;
    onChange([...values, v]);
    setDraft("");
  }

  return (
    <div>
      <Label htmlFor={inputId}>
        {label} ({values.length}/20)
      </Label>
      <div className="flex gap-2">
        <Input
          id={inputId}
          value={draft}
          maxLength={80}
          disabled={full}
          placeholder={full ? "최대 20개까지 등록할 수 있어요" : placeholder}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.nativeEvent.isComposing) {
              e.preventDefault();
              add();
            }
          }}
        />
        <Button size="sm" variant="outline" onClick={add} disabled={full || !draft.trim()}>
          <Plus className="h-3.5 w-3.5" /> 추가
        </Button>
      </div>
      {values.length > 0 && (
        <div className="mt-1 flex flex-wrap">
          {values.map((v) => (
            <Chip key={v} active onClick={() => onChange(values.filter((x) => x !== v))} aria-label={`${v} 삭제`}>
              {v} ×
            </Chip>
          ))}
        </div>
      )}
    </div>
  );
}

// ── 트레이너 사진 올리기(POST /v1/staff/{uid}/photo) ────────────────────

// 배포 시차 안내 — 어드민이 서버보다 먼저 올라간 창(CheckinQrCard의 NOT_DEPLOYED_MSG와 같은 자리).
// 404는 "이 배포에 그 주소가 없다"는 뜻이지 대표가 뭘 잘못한 게 아니다. 화면은 크래시하지 않고
// 이 문장만 남긴 뒤, 나머지 프로필 칸은 그대로 저장되게 둔다.
const PHOTO_NOT_DEPLOYED_MSG =
  "사진 올리기가 아직 서버에 올라가지 않았어요 — 서버가 업데이트되면 바로 쓸 수 있어요. 그때까지 이 창의 다른 정보는 정상적으로 저장됩니다.";

// 업로드 실패 → 한국어. **서버가 준 문구를 최우선으로 그대로 쓴다**(api.ts가 {error}를 message에
// 담아 준다 — 오프라인·전달 경로 실패도 이미 한국어로 정규화돼 있다). 여기서 덮는 건 서버가
// 문구를 줄 수 없는 두 경우뿐이다:
//   404  라우트 자체가 없어 본문이 없다(배포 시차).
//   413  보통 프록시가 내는 응답이라 우리 서버의 한국어 본문이 아니고, api.ts 폴백은 "잠시 후 다시
//        시도"라고 말하는데 그건 이 실패에서 **절대 통하지 않는 다음 행동**이다.
function photoUploadErrorKo(e: unknown): string {
  if (e instanceof ApiError) {
    if (e.status === 404) return PHOTO_NOT_DEPLOYED_MSG;
    if (e.status === 413) {
      return "사진 용량이 서버 상한을 넘었어요 — 더 작게 찍히거나 잘라 둔 사진으로 다시 올려주세요.";
    }
  }
  return e instanceof Error ? e.message : "사진을 올리지 못했어요 — 잠시 후 다시 시도해주세요.";
}

// <img src>에 넣어도 되는 값인가. 사진은 이제 서버가 준 https URL이지만, URL 칸 시절에 손으로
// 입력된 옛 값이 문서에 남아 있을 수 있어 스킴 검사는 유지한다(javascript: 등 주입 차단).
function safePhotoSrc(url: string): string {
  return /^https?:\/\//i.test(url) ? url : "";
}

/**
 * 사진 컨트롤 — 미리보기(=드롭 존) + [사진 선택] + [사진 지우기].
 *
 * 종전에는 "사진 URL" 텍스트 칸 하나였다. 대표가 가진 사진(폰 갤러리·바탕화면 파일)에는 URL이
 * 없으므로 그 칸으로는 **아무 사진도 넣을 수 없었다** — 어딘가에 먼저 업로드해 줄 사람이 필요했다.
 * 여기는 데스크톱 브라우저이고, 파일 선택창과 드래그앤드롭이 바로 그 일을 한다.
 *
 * 접근성: 실제 동작 경로는 **버튼**이다(파일 입력은 숨겨 두고 버튼이 click을 대신 부른다) —
 * 드롭 존은 마우스 사용자를 위한 보조 경로지 유일한 경로가 아니다.
 *
 * 저장 규약이 다른 이유: 서버가 업로드 응답의 photo_url을 프로필에 함께 저장한다(계약). 그래서
 * 올리는 즉시 반영이고, 화면은 그 사실을 감추지 않는다. 반대로 **지우기**는 프로필 저장 경로로
 * 보낸다(빈 photo_url) — 사진만 따로 지우는 동사가 계약에 없고, 있다 해도 "지우기 버튼 = 즉시
 * 삭제"는 되돌릴 수 없는 1클릭이라 이 집의 관례(저장을 눌러야 반영)와 어긋난다.
 */
function TrainerPhotoField({
  staff,
  photoUrl,
  onUploaded,
  onClear,
}: {
  staff: Staff;
  photoUrl: string;
  onUploaded: (url: string) => void;
  onClear: () => void;
}) {
  const upload = useUploadStaffPhoto();
  const fileRef = useRef<HTMLInputElement>(null);
  const [dragOver, setDragOver] = useState(false);
  // 브라우저 안에서 축소하다 난 실패(형식·디코드·용량) — 서버 실패와 표시 자리는 같지만
  // 생애주기가 다르다(뮤테이션 상태에 얹으면 다음 mutate가 지워 버린다).
  const [prepError, setPrepError] = useState<string | null>(null);
  const [preparing, setPreparing] = useState(false);
  // 방금 올린 사진의 축소 전/후 크기 — "왜 이렇게 빨리 올라갔지"에 대한 답이자, 폰 원본을
  // 그대로 보내지 않았다는 증거다.
  const [sizeNote, setSizeNote] = useState<{ from: number; to: number } | null>(null);

  const busy = preparing || upload.isPending;
  const notDeployed = upload.error instanceof ApiError && upload.error.status === 404;

  // 드롭 존을 살짝 빗나간 드롭으로 **브라우저가 그 파일로 이동해 버리는** 사고를 막는다.
  // 그 순간 이 모달의 미저장 입력(직함·소개문·칩 목록)이 통째로 사라진다 — 사진 한 장 올리려다
  // 프로필을 다시 쓰게 되는 셈이다. 이 필드가 떠 있는 동안(=프로필 창이 열린 동안)만 건다.
  useEffect(() => {
    const swallow = (e: DragEvent) => e.preventDefault();
    window.addEventListener("dragover", swallow);
    window.addEventListener("drop", swallow);
    return () => {
      window.removeEventListener("dragover", swallow);
      window.removeEventListener("drop", swallow);
    };
  }, []);

  async function handleFile(file: File) {
    setPrepError(null);
    setSizeNote(null);
    upload.reset(); // 지난 실패 문구가 새 시도 위에 남지 않게
    setPreparing(true);
    let prepared;
    try {
      prepared = await preparePhoto(file);
    } catch (e) {
      setPrepError(e instanceof Error ? e.message : "사진을 준비하지 못했어요.");
      return;
    } finally {
      setPreparing(false);
    }
    upload.mutate(
      {
        uid: staff.uid,
        body: { image: prepared.base64, content_type: prepared.content_type },
      },
      {
        onSuccess: (res) => {
          onUploaded(res.photo_url);
          setSizeNote({ from: prepared.source_bytes, to: prepared.bytes });
        },
      },
    );
  }

  function onDrop(e: ReactDragEvent) {
    e.preventDefault();
    setDragOver(false);
    if (busy) return;
    const file = e.dataTransfer.files?.[0];
    if (!file) {
      // 브라우저 탭·웹페이지의 이미지를 끌어오면 파일이 아니라 URL/텍스트만 실려 온다.
      setPrepError(
        "여기에 놓인 건 사진 파일이 아니에요 — 폴더에서 사진 파일을 끌어다 놓거나 [사진 선택]으로 골라주세요.",
      );
      return;
    }
    void handleFile(file);
  }

  return (
    <div className="flex flex-wrap items-start gap-3">
      {/* 미리보기 = 드롭 존. 사진이 없으면 색상 이니셜 아바타가 그대로 미리보기다. */}
      <div
        onDragOver={(e) => {
          e.preventDefault();
          if (!busy) setDragOver(true);
        }}
        // 아바타·안내문 같은 **자식 위로 옮겨가도** dragleave가 난다 — 그대로 끄면 존 안에서
        // 마우스를 움직이는 동안 강조가 깜빡인다. 진짜로 존 밖으로 나갔을 때만 끈다.
        onDragLeave={(e) => {
          if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragOver(false);
        }}
        onDrop={onDrop}
        className={`flex w-[132px] shrink-0 flex-col items-center gap-1.5 rounded-[12px] border border-dashed px-3 py-3 text-center transition ${
          dragOver ? "border-brand bg-brand/10" : "border-line bg-panel-2"
        }`}
      >
        <StaffAvatar
          name={staff.name}
          color={staff.color}
          photoUrl={safePhotoSrc(photoUrl)}
          size="lg"
        />
        <span className={`text-[10.5px] leading-[1.6] ${dragOver ? "text-brand" : "text-muted"}`}>
          {dragOver ? "여기에 놓으세요" : "사진을 여기로 끌어다 놓아도 돼요"}
        </span>
      </div>

      <div className="min-w-[220px] flex-1">
        <Label>프로필 사진 (비우면 색상 이니셜 아바타)</Label>
        <div className="flex flex-wrap gap-2">
          <Button
            size="sm"
            variant="outline"
            disabled={busy}
            onClick={() => fileRef.current?.click()}
          >
            <ImagePlus className="h-3.5 w-3.5" />{" "}
            {preparing ? "사진 준비 중…" : upload.isPending ? "올리는 중…" : "사진 선택"}
          </Button>
          {photoUrl !== "" && (
            <Button size="sm" variant="outline" className="text-danger" disabled={busy} onClick={onClear}>
              <Trash2 className="h-3.5 w-3.5" /> 사진 지우기
            </Button>
          )}
        </div>
        {/* 같은 파일을 다시 고르는 경우(실패 후 재시도)에도 change가 나도록 값을 비운다. */}
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => {
            const file = e.target.files?.[0];
            e.target.value = "";
            if (file) void handleFile(file);
          }}
        />
        <p className="mt-1.5 text-[10.5px] leading-[1.7] text-muted">
          폰에서 옮겨 둔 사진이나 컴퓨터 폴더의 사진을 그대로 올릴 수 있어요. 올리기 전에 브라우저가
          긴 변 {PHOTO_MAX_SIDE}px로 줄여 보내니 원본이 커도 괜찮아요.
        </p>
        {sizeNote && !upload.isError && (
          <p className="mt-1 text-[11px] text-ok">
            <Check className="mr-1 inline h-3 w-3" />
            사진이 저장됐어요 — {formatBytes(sizeNote.from)} → {formatBytes(sizeNote.to)}로 줄여
            올렸습니다.
          </p>
        )}
        {prepError && <p className="mt-1 text-[11px] text-danger">{prepError}</p>}
        {upload.isError && (
          <p
            className={`mt-1 text-[11px] ${
              notDeployed ? "rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 leading-[1.8] text-warn" : "text-danger"
            }`}
          >
            {notDeployed && <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />}
            {photoUploadErrorKo(upload.error)}
          </p>
        )}
      </div>
    </div>
  );
}

// 트레이너 프로필 편집(v1.6) — PUT /v1/staff/{uid}/profile은 "통 교체" 시맨틱: 폼 상태 전체를
// 항상 전송한다(머지 아님). 전부 비우고 저장하면 자연스럽게 "프로필 지우기"가 된다.
// 범위 위반(URL http(s)·직함 40자·연차 0~50·소개 500자·배열 20개/80자)은 서버 400 한국어
// 메시지를 그대로 인라인 표시 — 클라이언트는 maxLength·클램프로 선차단만 돕는다.
function ProfileModal({ staff, onClose }: { staff: Staff; onClose: () => void }) {
  const updateProfile = useUpdateStaffProfile();
  const [photoUrl, setPhotoUrl] = useState(staff.profile.photo_url);
  // **서버에 지금 저장돼 있는** 사진 주소. staff prop은 목록에서 클릭한 순간의 스냅샷이라
  // 업로드로 서버 값이 바뀌어도 따라오지 않는다 — "지우기를 눌렀는데 아직 저장 전"을 판정하려면
  // 살아 있는 기준선이 따로 필요하다.
  const [savedPhotoUrl, setSavedPhotoUrl] = useState(staff.profile.photo_url);
  const [title, setTitle] = useState(staff.profile.title);
  const [careerYears, setCareerYears] = useState(staff.profile.career_years);
  const [specialties, setSpecialties] = useState<string[]>(staff.profile.specialties);
  const [certifications, setCertifications] = useState<string[]>(staff.profile.certifications);
  const [awards, setAwards] = useState<string[]>(staff.profile.awards);
  const [bio, setBio] = useState(staff.profile.bio);

  const trimmedUrl = photoUrl.trim();
  // 사진을 지웠지만 아직 저장 전 — 업로드는 즉시 반영인데 지우기는 저장이 필요하다는
  // 비대칭이 이 화면의 유일한 함정이라, 그 상태를 화면이 직접 말한다.
  const photoCleared = savedPhotoUrl !== "" && trimmedUrl === "";

  function save() {
    updateProfile.mutate(
      {
        uid: staff.uid,
        profile: {
          photo_url: trimmedUrl,
          title: title.trim(),
          career_years: careerYears,
          specialties,
          certifications,
          awards,
          bio: bio.trim(),
        },
      },
      { onSuccess: onClose },
    );
  }

  return (
    <Modal open onClose={onClose} title={`프로필 편집 — ${staff.name}`} wide>
      <div className="space-y-3">
        <TrainerPhotoField
          staff={staff}
          photoUrl={trimmedUrl}
          onUploaded={(url) => {
            setPhotoUrl(url);
            setSavedPhotoUrl(url);
          }}
          onClear={() => setPhotoUrl("")}
        />
        {photoCleared && (
          <p className="text-[11px] text-warn">
            사진을 뺐어요 — <b>아래 저장을 눌러야</b> 실제로 지워집니다(그 전까지는 기존 사진이
            그대로예요). 지우면 색상 이니셜 아바타로 돌아갑니다.
          </p>
        )}

        <div className="grid grid-cols-2 gap-2">
          <div>
            <Label htmlFor="pf-title">직함 (40자 이내)</Label>
            <Input
              id="pf-title"
              value={title}
              maxLength={40}
              placeholder="예: 헤드 트레이너"
              onChange={(e) => setTitle(e.target.value)}
            />
          </div>
          <div>
            <Label htmlFor="pf-career">경력 연차 (0~50 · 0=미표기)</Label>
            <Input
              id="pf-career"
              type="number"
              min={0}
              max={50}
              step={1}
              value={careerYears}
              onChange={(e) =>
                setCareerYears(Math.min(50, Math.max(0, Math.round(Number(e.target.value) || 0))))
              }
            />
          </div>
        </div>

        <ChipListEditor
          label="전문분야"
          values={specialties}
          onChange={setSpecialties}
          placeholder="예: 재활 트레이닝"
        />
        <ChipListEditor
          label="자격증"
          values={certifications}
          onChange={setCertifications}
          placeholder="예: NSCA-CSCS"
        />
        <ChipListEditor
          label="수상·선수 경력"
          values={awards}
          onChange={setAwards}
          placeholder="예: 2024 보디빌딩 클래식 TOP5"
        />

        <div>
          {/* 카운터는 코드포인트 기준([...str].length) — 서버 rune 검증과 동일 계산. */}
          <Label htmlFor="pf-bio">소개문 ({[...bio].length}/500)</Label>
          <Textarea
            id="pf-bio"
            rows={5}
            value={bio}
            maxLength={500}
            placeholder="회원 앱에 보여질 소개를 적어주세요."
            onChange={(e) => setBio(e.target.value)}
          />
        </div>

        {updateProfile.isError && (
          <p className="text-[11px] text-danger">{updateProfile.error.message}</p>
        )}
        <Button className="w-full" disabled={updateProfile.isPending} onClick={save}>
          <Save className="h-4 w-4" /> {updateProfile.isPending ? "저장 중…" : "저장"}
        </Button>
        <p className="text-[10.5px] text-muted">
          프로필은 회원 열람 전제의 공개 정보예요(정산 정보와 무관). 모든 칸을 비우고 저장하면
          프로필이 지워집니다. <b className="text-ink">사진만 규약이 달라요</b> — 고르는 즉시
          올라가 저장되고, 나머지 칸은 저장을 눌러야 반영됩니다.
        </p>
      </div>
    </Modal>
  );
}

// ── 트레이너 초대(v1.8, POST /v1/staff) ─────────────────────────────────

// 초대 오류 → 한국어. 400(입력값 검증)은 서버 메시지가 항목별로 구체적이라 그대로 노출하고,
// 403·409만 이 화면 맥락의 카피로 덮는다(Login.tsx FB_ERROR_KO와 같은 취지).
// 409는 계약상 "이미 스태프" + "이미 회원 계정" 두 경우인데, 대표 입장에서 할 일은 둘 다
// "다른 이메일을 쓰거나 기존 계정을 정리한다"로 같아 한 문장으로 합친다.
function inviteErrorKo(e: unknown): string {
  if (e instanceof ApiError) {
    if (e.status === 409) return "이미 등록된 이메일이에요";
    if (e.status === 403) return "대표만 직원을 초대할 수 있어요";
  }
  return e instanceof Error ? e.message : "초대에 실패했어요";
}

// 초대 결과 — 계정 생성과 메일 발송은 실패 지점이 달라 결과도 나눠서 담는다.
interface InviteResult {
  name: string;
  email: string;
  mailError: string | null; // null = 메일까지 정상 발송
}

// 초대 = ① 계정 생성(POST /v1/staff) + ② 비밀번호 설정 메일, 2단 플로우. 서버는 임시 비밀번호로
// Firebase 계정을 만들되 응답에 담지 않으므로(유출 방지), 생성 직후 클라이언트가
// sendPasswordResetEmail을 보내 초대받은 사람이 스스로 비밀번호를 정하게 한다 — Login.tsx의
// "비밀번호를 잊으셨나요 / 처음 로그인이신가요?"와 같은 메일이다.
// ②만 실패해도 ①은 이미 성공(계정 존재)이라 결과를 뭉뚱그리지 않는다: 그 상태에서 "다시 초대"는
// 409로 막히고, 실제 해법은 로그인 화면에서의 재발송이기 때문이다.
function InviteStaffModal({ onClose }: { onClose: () => void }) {
  const createStaff = useCreateStaff();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<StaffRole>("trainer");
  const [payoutType, setPayoutType] = useState<PayoutType>("per_session");
  // 문자열 state — "미설정"(빈 값)과 0을 구분해야 한다(PolicyEditForm 홀딩 상한과 같은 이유).
  const [payoutValue, setPayoutValue] = useState("");
  // 2단 전체를 덮는 진행 플래그 — mutation.isPending만 보면 메일 발송 구간이 비어 그 사이
  // 재클릭이 통과한다(계정 중복 생성 시도 → 409).
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<InviteResult | null>(null);

  const trimmedName = name.trim();
  // 서버가 이메일을 소문자로 접어 계정을 만든다(domain.StaffCreate.Normalize) — 클라이언트도 같은
  // 값으로 보내고 같은 값으로 메일을 쏜다. 대문자로 입력해도 만들어진 계정과 초대 메일 주소,
  // 안내 문구가 서로 어긋나지 않게 하기 위해서다.
  const normalizedEmail = email.trim().toLowerCase();
  // 서버 왕복 전 1차 형식 가드 — 오타 주소로 계정이 만들어지면 초대 메일은 허공으로 가는데
  // 그 이메일은 409로 재사용까지 막힌다. 로컬@도메인.TLD 최소 형태만 본다(과한 정규식 금지 —
  // 정밀 검증은 서버 net/mail 파서 몫).
  const emailOk = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail);

  // 대표는 정산 개념이 없다(직원 표도 "—"로 표기) — 입력을 감추고 payout 자체를 보내지 않는다.
  // 서버도 미지정이면 DefaultPayout(회당 0원)으로 채운다.
  const showPayout = role === "trainer";
  const payoutRaw = payoutValue.trim();
  const parsedPayout = payoutRaw === "" ? null : Number(payoutRaw);
  // 상한은 서버 검증(domain.Payout.Validate — 회당 0~1,000,000원 / 요율 0~1 소수)을 그대로
  // 미러링한다. 400 왕복을 아끼려는 선차단일 뿐, 판정의 진실은 서버다.
  const payoutBad =
    parsedPayout !== null &&
    (!Number.isFinite(parsedPayout) ||
      parsedPayout < 0 ||
      (payoutType === "rate" ? parsedPayout > 100 : parsedPayout > 1_000_000));

  const canSubmit = !!trimmedName && emailOk && !(showPayout && payoutBad);

  async function submit() {
    if (busy || !canSubmit) return;
    setBusy(true);
    setError(null);
    try {
      await createStaff.mutateAsync({
        name: trimmedName,
        email: normalizedEmail,
        role,
        // rate는 0~1 소수 규약(formatPercent) — 입력은 %로 받고 저장 시 /100 한다
        // (PolicyEditForm 위약금율과 동일). 값을 비우면 payout 키 자체를 보내지 않는다.
        ...(showPayout && parsedPayout !== null
          ? {
              payout: {
                type: payoutType,
                value: payoutType === "rate" ? parsedPayout / 100 : parsedPayout,
              },
            }
          : {}),
      });
      // 이 줄부터는 무슨 일이 있어도 "계정은 만들어진" 상태다 — 아래 실패를 초대 실패로 되돌리지 않는다.
      try {
        await sendPasswordResetEmail(auth, normalizedEmail);
        setResult({ name: trimmedName, email: normalizedEmail, mailError: null });
      } catch (e) {
        setResult({
          name: trimmedName,
          email: normalizedEmail,
          mailError: e instanceof FirebaseError ? e.code : e instanceof Error ? e.message : "unknown",
        });
      }
    } catch (e) {
      setError(inviteErrorKo(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open onClose={onClose} title="트레이너 초대">
      {result ? (
        <div className="space-y-3">
          {result.mailError === null ? (
            <p className="text-[12.5px] text-ok">
              <Check className="mr-1 inline h-3.5 w-3.5" />
              <b>{result.name}</b> 님을 초대했습니다. {result.email}로 비밀번호 설정 메일을 보냈어요.
            </p>
          ) : (
            <>
              <p className="text-[12.5px] text-warn">
                <b>{result.name}</b> 님의 계정은 만들어졌지만 메일 발송에 실패했어요. 로그인 화면의
                "비밀번호를 잊으셨나요"로 재발송할 수 있어요.
              </p>
              <p className="text-[10.5px] text-muted">
                발송 실패 사유: {result.mailError} · 초대를 다시 누르지는 마세요 — 계정이 이미 있어
                "이미 등록된 이메일"로 막힙니다.
              </p>
            </>
          )}
          <Button className="w-full" variant="outline" onClick={onClose}>
            닫기
          </Button>
        </div>
      ) : (
        <div className="space-y-3">
          <div>
            <Label htmlFor="inv-name">이름</Label>
            <Input
              id="inv-name"
              value={name}
              maxLength={40}
              disabled={busy}
              placeholder="정혜린"
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div>
            <Label htmlFor="inv-email">이메일 (로그인 계정)</Label>
            <Input
              id="inv-email"
              type="email"
              value={email}
              maxLength={254}
              disabled={busy}
              autoComplete="off"
              placeholder="trainer@example.com"
              onChange={(e) => setEmail(e.target.value)}
            />
            {normalizedEmail !== "" && !emailOk && (
              <p className="mt-1 text-[10.5px] text-warn">
                이메일 형식을 확인해주세요 (예: trainer@example.com)
              </p>
            )}
          </div>
          <div>
            <Label htmlFor="inv-role">역할</Label>
            <Select
              id="inv-role"
              value={role}
              disabled={busy}
              onChange={(e) => setRole(e.target.value as StaffRole)}
            >
              <option value="trainer">트레이너</option>
              <option value="owner">대표</option>
            </Select>
          </div>

          {showPayout && (
            <div className="grid grid-cols-2 gap-2">
              <div>
                <Label htmlFor="inv-payout-type">정산 방식 (선택)</Label>
                <Select
                  id="inv-payout-type"
                  value={payoutType}
                  disabled={busy}
                  onChange={(e) => setPayoutType(e.target.value as PayoutType)}
                >
                  <option value="per_session">회당 지급</option>
                  <option value="rate">매출 요율</option>
                </Select>
              </div>
              <div>
                <Label htmlFor="inv-payout-value">
                  {payoutType === "per_session" ? "회당 금액 (원)" : "요율 (%)"}
                </Label>
                <Input
                  id="inv-payout-value"
                  type="number"
                  min={0}
                  max={payoutType === "rate" ? 100 : 1_000_000}
                  step={payoutType === "rate" ? 0.1 : 1000}
                  value={payoutValue}
                  disabled={busy}
                  placeholder="미설정"
                  onChange={(e) => setPayoutValue(e.target.value)}
                />
              </div>
            </div>
          )}
          {showPayout && payoutBad && (
            <p className="text-[10.5px] text-warn">
              {payoutType === "rate"
                ? "요율은 0~100 사이로 입력해주세요."
                : "회당 금액은 0~1,000,000원 사이로 입력해주세요."}
            </p>
          )}

          {error && <p className="text-[11px] text-danger">{error}</p>}

          <Button className="w-full" disabled={busy || !canSubmit} onClick={() => void submit()}>
            <UserPlus className="h-4 w-4" /> {busy ? "초대 중…" : "초대 보내기"}
          </Button>
          <p className="text-[10.5px] text-muted">
            초대하면 계정이 만들어지고 그 이메일로 비밀번호 설정 메일이 갑니다 — 임시 비밀번호를
            사람 손으로 전달하지 않아요. 정산은 비워둬도 되고, 휴무·프로필은 초대 후 직원 표에서
            설정하세요. 퇴사한 직원을 같은 이메일로 다시 초대하면 재입사로 처리되고 프로필·휴무가
            그대로 복원됩니다(직원 표의 "재입사" 버튼과 같은 결과예요).
          </p>
        </div>
      )}
    </Modal>
  );
}

// ── 직원 생애주기(v2.0, P08) ────────────────────────────────────────────
// 네 모달 모두 owner 전용 엔드포인트를 쓴다(화면 자체가 App.tsx owner 게이트 뒤에 있고,
// 버튼도 isOwner로 한 번 더 잠근다 — 눌러보고 403을 받는 UI를 만들지 않는다).

// 정정(PUT /v1/staff/{uid}) — 이름 오타·색·정산 조건·역할. **머지 시맨틱**이라 바뀐 필드만 싣는다:
// 전부 보내면 이름만 고친 요청이 정산 조건까지 재저장하고, 하나도 안 바뀌면 서버가 400
// ("수정할 항목이 없어요")을 낸다. status는 이 폼에 없다 — 상태 전이는 전용 동사만 담당한다.
function StaffEditModal({
  staff,
  isSelf,
  isLastActiveOwner,
  onClose,
}: {
  staff: Staff;
  isSelf: boolean;
  isLastActiveOwner: boolean;
  onClose: () => void;
}) {
  const updateStaff = useUpdateStaff();
  // 본인 정정이면 헤더 이름도 함께 갱신해야 한다 — 아래 onSuccess 참고.
  const { me, refreshMe } = useAuth();
  const [name, setName] = useState(staff.name);
  const [color, setColor] = useState(staff.color || "#f43f5e");
  const [role, setRole] = useState<StaffRole>(staff.role);
  const [payoutType, setPayoutType] = useState<PayoutType>(staff.payout.type);
  // rate는 0~1 소수 규약 — 입력은 %로 받고 저장 시 /100(InviteStaffModal·PolicyEditForm과 동일).
  // *10000/100은 0.125 → 12.5를 부동소수 노이즈 없이 복원한다.
  const [payoutValue, setPayoutValue] = useState(
    staff.payout.type === "rate"
      ? String(Math.round(staff.payout.value * 10000) / 100)
      : String(staff.payout.value),
  );

  // 역할 변경이 잠기는 두 자리 — 서버 거절 사유를 그대로 미러링한다(락아웃 방지).
  //  · 본인(400): owner가 스스로를 내리면 그 순간 owner 전용 API를 잃어 되돌릴 사람이 없다.
  //  · 마지막 활성 대표(409): 활성 owner 0명 = Firestore 직접 편집 외 복구 경로 소멸.
  const roleLocked = isSelf || isLastActiveOwner;
  const roleLockReason = isSelf
    ? "본인의 역할은 바꿀 수 없어요 — 자기 강등은 되돌릴 사람을 없앱니다."
    : "마지막 활성 대표의 역할은 바꿀 수 없어요 — 대표가 0명이 되면 센터가 잠깁니다.";

  const trimmedName = name.trim();
  const nameOk = trimmedName !== "" && [...trimmedName].length <= 40;
  const normalizedColor = color.trim().toLowerCase();
  const colorOk = /^#[0-9a-f]{6}$/.test(normalizedColor);
  // 대표는 정산 개념이 없다(표에서도 "—") — 트레이너로 고를 때만 입력을 연다.
  const showPayout = role === "trainer";
  const payoutRaw = payoutValue.trim();
  const parsedPayout = payoutRaw === "" ? NaN : Number(payoutRaw);
  // 상한은 서버 검증(domain.Payout.Validate — 회당 0~1,000,000원 / 요율 0~1 소수) 미러링.
  const payoutOk =
    Number.isFinite(parsedPayout) &&
    parsedPayout >= 0 &&
    (payoutType === "rate" ? parsedPayout <= 100 : parsedPayout <= 1_000_000);
  const nextPayout: Payout | null =
    showPayout && payoutOk
      ? { type: payoutType, value: payoutType === "rate" ? parsedPayout / 100 : parsedPayout }
      : null;

  const patch: StaffUpdateRequest = {};
  if (nameOk && trimmedName !== staff.name) patch.name = trimmedName;
  if (colorOk && normalizedColor !== (staff.color || "").toLowerCase()) patch.color = normalizedColor;
  if (!roleLocked && role !== staff.role) patch.role = role;
  if (nextPayout && (nextPayout.type !== staff.payout.type || nextPayout.value !== staff.payout.value)) {
    patch.payout = nextPayout;
  }
  const dirty = Object.keys(patch).length > 0;
  const inputsOk = nameOk && colorOk && (!showPayout || payoutOk);

  return (
    <Modal open onClose={onClose} title={`직원 정정 — ${staff.name}`}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-2">
          <div>
            <Label htmlFor="se-name">이름 (40자 이내)</Label>
            <Input
              id="se-name"
              value={name}
              maxLength={40}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div>
            <Label htmlFor="se-color">식별 색상 (스케줄 그리드·범례)</Label>
            <div className="flex gap-2">
              <input
                id="se-color"
                type="color"
                value={colorOk ? normalizedColor : "#f43f5e"}
                onChange={(e) => setColor(e.target.value)}
                className="h-[38px] w-11 shrink-0 rounded-[10px] border border-line bg-panel-2"
                aria-label="식별 색상 선택"
              />
              <Input value={color} maxLength={7} onChange={(e) => setColor(e.target.value)} />
            </div>
          </div>
        </div>
        {!nameOk && <p className="text-[10.5px] text-warn">이름을 1~40자로 입력해주세요.</p>}
        {!colorOk && <p className="text-[10.5px] text-warn">색상은 #rrggbb 형식이어야 해요.</p>}

        <div>
          <Label htmlFor="se-role">역할</Label>
          <Select
            id="se-role"
            value={role}
            disabled={roleLocked}
            onChange={(e) => setRole(e.target.value as StaffRole)}
          >
            <option value="trainer">트레이너</option>
            <option value="owner">대표</option>
          </Select>
          {roleLocked && <p className="mt-1 text-[10.5px] text-muted">{roleLockReason}</p>}
          {!roleLocked && role !== staff.role && (
            <p className="mt-1 text-[10.5px] text-warn">
              역할을 바꾸면 로그인 권한(대표 전용 화면·API)도 함께 바뀝니다.
            </p>
          )}
        </div>

        {showPayout && (
          <div className="grid grid-cols-2 gap-2">
            <div>
              <Label htmlFor="se-payout-type">정산 방식</Label>
              <Select
                id="se-payout-type"
                value={payoutType}
                onChange={(e) => setPayoutType(e.target.value as PayoutType)}
              >
                <option value="per_session">회당 지급</option>
                <option value="rate">매출 요율</option>
              </Select>
            </div>
            <div>
              <Label htmlFor="se-payout-value">
                {payoutType === "per_session" ? "회당 금액 (원)" : "요율 (%)"}
              </Label>
              <Input
                id="se-payout-value"
                type="number"
                min={0}
                max={payoutType === "rate" ? 100 : 1_000_000}
                step={payoutType === "rate" ? 0.1 : 1000}
                value={payoutValue}
                onChange={(e) => setPayoutValue(e.target.value)}
              />
            </div>
          </div>
        )}
        {showPayout && !payoutOk && (
          <p className="text-[10.5px] text-warn">
            {payoutType === "rate"
              ? "요율은 0~100 사이로 입력해주세요."
              : "회당 금액은 0~1,000,000원 사이로 입력해주세요."}
          </p>
        )}

        {updateStaff.isError && <p className="text-[11px] text-danger">{updateStaff.error.message}</p>}

        <Button
          className="w-full"
          disabled={updateStaff.isPending || !inputsOk || !dirty}
          onClick={() =>
            updateStaff.mutate(
              { uid: staff.uid, patch },
              {
                onSuccess: () => {
                  // 자기 이름을 바꿨으면 헤더·인사말도 함께 갱신한다(v2.2). 그 자리들은 이제
                  // staff 목록이 아니라 me.name을 1순위로 쓰므로 staff 캐시 무효화가 닿지 않는다.
                  // refreshMe는 실패해도 세션을 내리지 않는다.
                  if (staff.uid === me?.uid) void refreshMe();
                  onClose();
                },
              },
            )
          }
        >
          <Save className="h-4 w-4" /> {updateStaff.isPending ? "저장 중…" : "저장"}
        </Button>
        <p className="text-[10.5px] text-muted">
          바뀐 항목만 저장합니다. 퇴사·재입사는 이 창이 아니라 직원 표의 전용 버튼에서 처리해요 —
          상태는 담당 이관 검사를 거쳐야 바뀝니다.
        </p>
      </div>
    </Modal>
  );
}

// 미배정 회수 센티널 — 서버의 to_uid=""("미배정으로 회수")와 "아직 아무것도 안 고름"을
// 셀렉트 한 칸에서 구분해야 한다. 빈 바디 하나로 담당이 통째로 날아가는 사고를 막는 자리다.
const UNASSIGN = "__unassign__";

// 담당 일괄 이관(POST /v1/staff/{uid}/transfer). 회원·회원권·고정 스케줄·미래 예약을 한 번에
// 넘긴다. 인수자가 같은 슬롯에 이미 수업이 있으면 그 예약은 옮기지 않고 conflicts로 돌아오는데,
// **그걸 조용히 삼키면 대표는 이관이 끝난 줄 알고 퇴사를 다시 눌렀다가 또 막힌다** — 결과 화면의 핵심.
function TransferStaffModal({
  from,
  staff,
  onClose,
  onContinueToDeactivate,
}: {
  from: Staff;
  staff: Staff[];
  onClose: () => void;
  onContinueToDeactivate?: () => void;
}) {
  const transfer = useTransferStaff();
  const [to, setTo] = useState("");
  const [result, setResult] = useState<StaffTransferResult | null>(null);
  // 결과에 충돌이 있을 때만 예약을 이름·시각으로 푼다(그 전엔 예약 목록을 끌어올 이유가 없다).
  const bookingLabel = useBookingLabeler((result?.conflicts.length ?? 0) > 0);

  // 인수자 후보는 **재직자만**. 퇴사자에게 넘기면 그 사람의 퇴사 선행 조건이 되살아날 뿐이고
  // 서버도 409로 막는다. 이관 원본 본인도 뺀다(400 to_uid == uid).
  const candidates = staff.filter((s) => isStaffActive(s) && s.uid !== from.uid);

  if (result) {
    const { moved, conflicts } = result;
    // 서버는 여기서만 booking_id라는 이름을 쓴다(퇴사 blockers는 id) — 화면에 들어오기 전에
    // 내부 공통 표현(BookingRef)으로 맞춘다. 퇴사 창과 같은 순서(시간순)로 세워 두 목록이
    // 같은 사건을 같은 차례로 말하게 한다(서버 정렬은 문서 id 순이라 시각과 무관하다).
    const conflictRefs = conflicts
      .map(toBookingRef)
      .sort((a, b) => a.slot_key.localeCompare(b.slot_key));
    return (
      <Modal open onClose={onClose} title={`담당 이관 — ${from.name}`}>
        <div className="space-y-3">
          <p className="text-[12.5px] text-ok">
            <Check className="mr-1 inline h-3.5 w-3.5" />
            회원 {moved.members} · 회원권 {moved.passes} · 고정 스케줄 {moved.recurrings} · 예약{" "}
            {moved.bookings}건을 옮겼어요.
          </p>
          {conflicts.length > 0 ? (
            <div className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2">
              <div className="flex items-center gap-1 text-[11.5px] font-extrabold text-warn">
                <TriangleAlert className="h-3.5 w-3.5" /> 옮기지 못한 예약 {conflicts.length}건
              </div>
              <p className="mt-1 text-[10.5px] text-muted">
                인수자에게 같은 시간 수업이 이미 있어요(트레이너는 같은 시간 1팀). 이 예약들은 그대로
                남아 <b className="text-ink">퇴사 처리를 계속 막습니다</b> — 예약 화면에서 시간을 옮기거나
                취소한 뒤 다시 시도하세요.
              </p>
              <ul className="mt-1.5 max-h-[160px] space-y-0.5 overflow-y-auto text-[11.5px]">
                {conflictRefs.map((b) => (
                  <li key={b.id}>· {bookingLabel(b)}</li>
                ))}
              </ul>
            </div>
          ) : (
            <p className="text-[10.5px] text-muted">
              겹치는 시간이 없어 미래 예약까지 전부 옮겨졌어요. 회원권마다 원장에 "담당 이관" 기록이
              남습니다(잔여 세션은 그대로).
            </p>
          )}
          {onContinueToDeactivate && conflicts.length === 0 && (
            <Button className="w-full" onClick={onContinueToDeactivate}>
              <UserMinus className="h-4 w-4" /> 퇴사 처리 계속하기
            </Button>
          )}
          <Button className="w-full" variant="outline" onClick={onClose}>
            닫기
          </Button>
        </div>
      </Modal>
    );
  }

  return (
    <Modal open onClose={onClose} title={`담당 이관 — ${from.name}`}>
      <div className="space-y-3">
        <p className="text-[11.5px] text-muted">
          <b className="text-ink">{from.name}</b> 님의 담당 회원 · 유효한 회원권 · 고정 스케줄 · 예정된
          예약을 한 번에 넘깁니다. 지난 기록과 정산 귀속은 그대로 남아요.
        </p>
        <div>
          <Label htmlFor="tf-to">인수자</Label>
          <Select id="tf-to" value={to} onChange={(e) => setTo(e.target.value)}>
            <option value="">선택하세요</option>
            {candidates.map((s) => (
              <option key={s.uid} value={s.uid}>
                {s.name} ({s.role === "owner" ? "대표" : "트레이너"})
              </option>
            ))}
            <option value={UNASSIGN}>미배정으로 회수</option>
          </Select>
          {to === UNASSIGN && (
            <p className="mt-1 text-[10.5px] text-warn">
              담당이 비워집니다 — 회원 목록의 "미배정" 필터와 대시보드 미배정 KPI에 바로 잡혀요.
              단, 담당 없는 회원권으로는 새 예약을 만들 수 없습니다.
            </p>
          )}
          {!candidates.length && (
            <p className="mt-1 text-[10.5px] text-muted">
              넘길 수 있는 재직 직원이 없어요 — "미배정으로 회수"만 가능합니다.
            </p>
          )}
        </div>
        {transfer.isError && <p className="text-[11px] text-danger">{transfer.error.message}</p>}
        <Button
          className="w-full"
          disabled={transfer.isPending || !to}
          onClick={() =>
            transfer.mutate(
              { uid: from.uid, toUid: to === UNASSIGN ? "" : to },
              { onSuccess: setResult },
            )
          }
        >
          <ArrowRightLeft className="h-4 w-4" /> {transfer.isPending ? "이관 중…" : "이관하기"}
        </Button>
        <p className="text-[10.5px] text-muted">
          인수자에게 같은 시간 수업이 이미 있는 예약은 옮기지 않고 따로 알려드려요 — 이관이 트레이너
          동시 1건 규칙을 우회하지 않습니다.
        </p>
      </div>
    </Modal>
  );
}

// 예약 id → "김지훈 · 8/25 (월) 20:00". **이관 충돌(conflicts) 전용**이다.
//
// 퇴사 blockers는 계약 v2.1로 slot_key를 함께 받게 되어 이 조회를 쓰지 않는다(아래 참조).
// 충돌 쪽에 남긴 이유: 그 안내의 행동은 "예약 화면에서 그 수업을 찾아 시간을 옮기거나 취소"라
// **누구의 수업인지**가 있어야 찾을 수 있다. blockers의 행동("담당 이관" 버튼 한 번)과 달리
// 사람이 직접 그 예약을 짚어야 하는 자리다. 충돌이 실제로 생겼을 때만 켠다(enabled).
// 입력은 **내부 공통 표현 BookingRef 하나**다 — 서버가 blockers는 {id}, conflicts는 {booking_id}로
// 주지만 그 차이는 toBookingRef에서 끝난다(라벨러가 두 모양을 알 필요가 없다).
function useBookingLabeler(enabled: boolean) {
  const bookingsQ = useBookings(todayStr(), enabled);
  const membersQ = useMembers();
  return (ref: BookingRef): string => {
    const b = bookingsQ.data?.find((x) => x.id === ref.id);
    const key = ref.slot_key || b?.slot_key;
    const when = key ? formatSlotKey(key) : "";
    const who = b ? (membersQ.data?.find((m) => m.id === b.member_id)?.name ?? "") : "";
    if (who && when) return `${who} · ${when}`;
    if (when || who) return when || who;
    // 조회 중에 원시 id를 깜빡이지 않는다(Firestore id는 사람에게 아무 정보가 아니다).
    // 로딩이 끝나고도 못 찾으면(그 사이 취소된 예약) 그때는 id라도 남겨 추적할 수 있게 한다.
    return bookingsQ.isLoading || membersQ.isLoading ? "불러오는 중…" : ref.id;
  };
}

// 항목이 아주 많아도 모달이 무너지지 않게 앞부분만 펼치고 나머지는 건수로 접는다.
const MAX_BLOCKER_ITEMS = 8;

// 원소 타입이 두 가지다(계약 v2.1): 회원·회원권·고정 스케줄은 id 문자열, 예약은 {id, slot_key}.
// 목록 UI(제목·건수·접기)는 완전히 같아서 원소에서 key와 표시문만 뽑아 쓰도록 열어둔다.
function BlockerList<T>({
  title,
  items,
  idOf,
  label,
}: {
  title: string;
  items: T[];
  idOf: (item: T) => string;
  label: (item: T) => string;
}) {
  if (!items.length) return null;
  const shown = items.slice(0, MAX_BLOCKER_ITEMS);
  return (
    <div>
      <div className="text-[11px] font-extrabold">
        {title} <span className="text-muted">{items.length}건</span>
      </div>
      <ul className="mt-0.5 space-y-0.5 text-[11.5px] text-muted">
        {shown.map((item) => (
          <li key={idOf(item)}>· {label(item)}</li>
        ))}
        {items.length > shown.length && (
          <li className="text-[10.5px]">… 외 {items.length - shown.length}건</li>
        )}
      </ul>
    </div>
  );
}

const selfId = (id: string) => id;

// 409 본문(ApiError.data)은 검증되지 않은 JSON이다 — 서버 타입을 그대로 믿지 않고 이 모양으로
// 받아 정규화한다. v2.0 서버는 bookings를 id 문자열 배열로 주고 v2.1부터 {id, slot_key}다.
// 여기가 두 와이어 모양(구버전 문자열 · v2.1 객체)이 내부 BookingRef로 합류하는 지점이다.
type RawStaffBlockers = {
  members?: string[];
  passes?: string[];
  recurrings?: string[];
  bookings?: (string | Partial<BookingRef>)[];
};

// 409 본문에서 blockers를 꺼낸다. 네 배열이 전부 비면 null을 돌려 서버 문구를 그대로 쓰게 한다
// — blockers 없는 409(마지막 활성 대표)도 있고, 빈 패널은 아무것도 설명하지 못한다.
function staffBlockersOf(e: unknown): StaffBlockers | null {
  if (!(e instanceof ApiError) || e.status !== 409) return null;
  const raw = (e.data as { blockers?: RawStaffBlockers } | null | undefined)?.blockers;
  if (!raw) return null;
  const b: StaffBlockers = {
    members: raw.members ?? [],
    passes: raw.passes ?? [],
    recurrings: raw.recurrings ?? [],
    bookings: (raw.bookings ?? []).map((x) =>
      typeof x === "string" ? { id: x, slot_key: "" } : { id: x?.id ?? "", slot_key: x?.slot_key ?? "" },
    ),
  };
  const total = b.members.length + b.passes.length + b.recurrings.length + b.bookings.length;
  return total > 0 ? b : null;
}

// "2026-08-31"(날짜 입력) → RFC3339. 소급 퇴사일은 그날 18시(로컬)로 잡는다 — 00:00로 보내면
// 그날 진행한 수업·정산이 퇴사 이후로 기록된다. 서버가 UTC로 정규화해 보관한다.
function dateToRfc3339(dateStr: string): string {
  const d = new Date(`${dateStr}T18:00:00`);
  return Number.isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString();
}

// 퇴사 처리(POST /v1/staff/{uid}/deactivate). 이 작업의 핵심 화면이다.
// 서버는 담당(회원·활성 패스·미만료 고정 스케줄·미래 예약)이 하나라도 남아 있으면 409 + blockers로
// 거절한다. 이관 없이 비활성화하면 담당 회원이 "목록엔 미배정으로 보이는데 미배정 필터·KPI엔
// 잡히지 않는" 발견 불가능 상태가 되기 때문이다. 그래서 이 창은 두 가지를 한 화면에 둔다:
//   ① 왜 안 되는지 — 남은 항목을 **회원 이름으로 해석해서** 보여준다(id 나열 금지)
//   ② 그래서 뭘 해야 하는지 — 바로 이관 창으로 넘어가는 버튼
function DeactivateStaffModal({
  staff,
  onClose,
  onNeedTransfer,
}: {
  staff: Staff;
  onClose: () => void;
  onNeedTransfer: () => void;
}) {
  const deactivate = useDeactivateStaff();
  const membersQ = useMembers();
  const recurringsQ = useRecurrings();
  const [leftAt, setLeftAt] = useState(todayStr());
  const [blockers, setBlockers] = useState<StaffBlockers | null>(null);
  const [error, setError] = useState<string | null>(null);

  // 이 모달의 존재 이유는 "왜 안 되는지를 **이름으로** 보여주는 것"인데, 종전엔 조회가 실패하면
  // 라벨이 조용히 원시 문서 id로 퇴화해 목록이 정확히 금지된 모양(id 나열)이 됐다 —
  // membersQ/recurringsQ에 isError 분기가 없었기 때문이다(P14 M3, 올바른 패턴은 Members.tsx).
  // 셋으로 가른다: 조회 중 → "불러오는 중…" / 조회 실패 → 왜 이름이 없는지 말한다 /
  // 조회는 됐는데 없는 항목 → id를 남긴다(그 사이 삭제된 데이터의 유일한 추적 단서).
  const namesLoading = membersQ.isLoading || recurringsQ.isLoading;
  const namesFailed = membersQ.isError || recurringsQ.isError;
  const unresolved = (id: string) =>
    namesLoading ? "불러오는 중…" : namesFailed ? "이름을 불러오지 못했어요" : id;
  const memberLabel = (id: string) => membersQ.data?.find((m) => m.id === id)?.name ?? unresolved(id);
  const passLabel = (id: string) => {
    for (const m of membersQ.data ?? []) {
      const p = m.passes.find((x) => x.id === id);
      if (p) return `${m.name} · ${p.product} (잔여 ${p.remaining})`;
    }
    return unresolved(id);
  };
  const recurringLabel = (id: string) => {
    const r = recurringsQ.data?.find((x) => x.id === id);
    if (!r) return unresolved(id);
    const days = r.days.map((d) => WEEKDAY_LABEL[d]).join("·");
    return `${memberLabel(r.member_id)} · 매주 ${days} ${r.hour}:00 (~${r.until})`;
  };
  // 예약은 서버가 slot_key를 함께 싣는다(계약 v2.1) — 예약 목록(GET /v1/bookings)을 한 번 더
  // 조회하던 왕복을 없앴다. 회원 이름은 못 붙지만 이 목록의 행동은 "담당 이관" 버튼 하나이고,
  // 누구를 옮기는지는 바로 위 "담당 회원"·"유효한 회원권" 목록이 이름으로 이미 말한다.
  // 대신 시간순으로 세워 앞 8건이 **가장 먼저 조정해야 할 수업**이 되게 한다(서버 정렬은
  // 문서 id 순이라 시각과 무관하다).
  const bookingLabel = (b: BookingRef) => (b.slot_key ? formatSlotKey(b.slot_key) : b.id);
  const blockedBookings = [...(blockers?.bookings ?? [])].sort((a, b) =>
    a.slot_key.localeCompare(b.slot_key),
  );

  function submit() {
    setError(null);
    setBlockers(null);
    deactivate.mutate(
      // 오늘이면 left_at을 아예 보내지 않는다 — 서버가 "지금"을 기록하는 편이 정확하다.
      { uid: staff.uid, leftAt: leftAt === todayStr() ? undefined : dateToRfc3339(leftAt) },
      {
        onSuccess: onClose,
        onError: (e) => {
          const b = staffBlockersOf(e);
          if (b) setBlockers(b);
          else setError(e.message);
        },
      },
    );
  }

  return (
    <Modal open onClose={onClose} title={`퇴사 처리 — ${staff.name}`}>
      <div className="space-y-3">
        <div>
          <Label htmlFor="dc-left-at">퇴사일</Label>
          <Input
            id="dc-left-at"
            type="date"
            value={leftAt}
            max={todayStr()}
            onChange={(e) => setLeftAt(e.target.value || todayStr())}
          />
          <p className="mt-1 text-[10.5px] text-muted">
            지난 날짜로 소급 입력할 수 있어요(기본 오늘). 처리 즉시 로그인 계정이 잠기고 대표·트레이너
            권한이 회수됩니다 — 과거 정산·원장·수업 기록은 그대로 남아요.
          </p>
        </div>

        {blockers && (
          <div className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2.5">
            <div className="flex items-center gap-1 text-[11.5px] font-extrabold text-warn">
              <TriangleAlert className="h-3.5 w-3.5" /> 아직 담당이 남아 있어 퇴사할 수 없어요
            </div>
            <p className="mt-1 text-[10.5px] text-muted">
              먼저 아래 항목을 다른 직원에게 넘기거나 미배정으로 회수해야 합니다. 그냥 비활성화하면
              담당 회원이 "목록엔 미배정인데 미배정 필터·KPI엔 안 잡히는" 상태로 사라집니다.
            </p>
            {namesFailed && (
              <p className="mt-1.5 text-[10.5px] text-danger">
                회원·고정 스케줄 목록을 불러오지 못해 이름 대신 빈자리로 표시됩니다 — 잠시 후 창을
                닫았다 다시 열어주세요. 건수와 "담당 이관하기"는 그대로 쓸 수 있어요.
              </p>
            )}
            <div className="mt-2 max-h-[280px] space-y-2 overflow-y-auto">
              <BlockerList
                title="담당 회원"
                items={blockers.members}
                idOf={selfId}
                label={memberLabel}
              />
              <BlockerList
                title="유효한 회원권"
                items={blockers.passes}
                idOf={selfId}
                label={passLabel}
              />
              <BlockerList
                title="고정 스케줄"
                items={blockers.recurrings}
                idOf={selfId}
                label={recurringLabel}
              />
              <BlockerList
                title="예정된 예약"
                items={blockedBookings}
                idOf={(b) => b.id}
                label={bookingLabel}
              />
            </div>
            <Button className="mt-2.5 w-full" onClick={onNeedTransfer}>
              <ArrowRightLeft className="h-4 w-4" /> 담당 이관하기
            </Button>
          </div>
        )}

        {error && <p className="text-[11px] text-danger">{error}</p>}

        <Button
          className="w-full"
          variant="danger"
          disabled={deactivate.isPending}
          onClick={submit}
        >
          <UserMinus className="h-4 w-4" />{" "}
          {deactivate.isPending ? "처리 중…" : blockers ? "다시 퇴사 처리" : "퇴사 처리"}
        </Button>
        <p className="text-[10.5px] text-muted">
          계정을 지우지 않습니다 — 원장(잔여 세션의 유일한 출처)과 정산 비교표가 이 계정을 참조하고
          있고, 근로자 명부·정산 기록에는 법정 보존 의무가 있어요. 재입사도 언제든 가능합니다.
        </p>
      </div>
    </Modal>
  );
}

// 재입사(POST /v1/staff/{uid}/reactivate) — status=active · left_at 소거 · 권한/계정 복원.
// 퇴사 후 본인 명의로 회원 등록까지 마친 계정이면 서버가 409로 막는다(그 연결이 지워지므로) —
// 서버 문구를 그대로 보여준다.
function ReactivateStaffModal({ staff, onClose }: { staff: Staff; onClose: () => void }) {
  const reactivate = useReactivateStaff();
  return (
    <Modal open onClose={onClose} title={`재입사 — ${staff.name}`}>
      <div className="space-y-3">
        <p className="text-[12.5px]">
          <b>{staff.name}</b> 님을 다시 재직 상태로 되돌립니다 — 로그인 계정이 열리고{" "}
          {staff.role === "owner" ? "대표" : "트레이너"} 권한이 복원돼요.
        </p>
        <p className="text-[10.5px] text-muted">
          담당은 자동으로 돌아오지 않습니다. 퇴사 전에 넘긴 회원·회원권은 인수자에게 남아 있어요 —
          필요하면 재입사 후 "담당 이관"으로 다시 넘겨주세요.
        </p>
        {reactivate.isError && (
          <p className="text-[11px] text-danger">{reactivate.error.message}</p>
        )}
        <Button
          className="w-full"
          disabled={reactivate.isPending}
          onClick={() => reactivate.mutate(staff.uid, { onSuccess: onClose })}
        >
          <UserCheck className="h-4 w-4" /> {reactivate.isPending ? "처리 중…" : "재입사 처리"}
        </Button>
      </div>
    </Modal>
  );
}
