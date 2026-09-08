// 앱 가입 요청 큐(P69) — 회원 관리 탭 **최상단**에 마운트되는 카드(대표 전용, Members.tsx가 isOwner로
// 게이트). 종전엔 설정·직원 탭의 8장 카드 중 6번째였고 회원 관리·네비 어디에도 흔적이 없어, 대표가
// "앱에서 가입 요청을 보냈다는데 볼 곳이 없다"고 했다 — "신청한 회원"은 회원 관리에서 찾는다.
//
// 이 파일은 Settings.tsx에서 **코드 이동**이다(재작성 아님): ApproveJoinModal·RejectJoinModal·
// useFreshIds·isJoinRequestGone·JoinRequestGoneNotice와 그 판정·문구·주석(P55·P58)은 그대로다.
// 회원 관리로 온 뒤 새로 생긴 것은 셋 — ① 요청 시각(상대)·경과 강조 ② 회원 목록과 대조하는 중복
// 감지(같은 화면이 useMembers를 이미 들고 있어 prop으로 받는다) ③ 승인 직후 그 회원 자동 선택.
//
// 서버 계약(v2.34): approve는 **새 회원 레코드 생성 + 계정 연결**이고, 기존 회원에 붙이는 동사는 없다.
// 같은 번호의 살아 있는 회원이 이미 있으면 서버가 **409로 승인을 거부**한다(service.go JoinApprove —
// 회원이 2명 되는 C-2 변종 차단). 이 화면의 중복 힌트·확인 창 경고는 그 판정을 **먼저** 보여줘
// 대표가 헛되이 누르지 않게 하는 것이고, 방어선은 서버다. 서버 미배포 상태에서는 화면 경고만 남는다.
import { useEffect, useRef, useState } from "react";
import { Check, TriangleAlert, UserX } from "lucide-react";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, ErrorState, Modal, Spinner } from "@/components/ui";
import { ApiError, isRouteNotFound } from "@/lib/api";
import { cn } from "@/lib/cn";
import {
  formatDateTimeKo,
  formatPhoneKR,
  formatRelativeKo,
  maskPhoneKR,
  normalizePhoneKR,
  staffLabel,
} from "@/lib/format";
import { useApproveJoin, useJoinRequests, useRejectJoin } from "@/lib/queries";
import { isJoinPending, type JoinRequest, type Member, type Staff } from "@/lib/types";

// 요청이 기다린 시간의 경고 단계. 앱 대기실이 "승인이 늦으면 데스크에 문의해주세요"라고 안내하므로
// 데스크 쪽 화면이 먼저 말해야 한다 — 24h 넘으면 warn, 72h 넘으면 danger.
const WAIT_WARN_MS = 24 * 3_600_000;
const WAIT_DANGER_MS = 72 * 3_600_000;

// 회원 목록과의 대조 결과. 우선순위 ① 정규화 번호 일치(탈퇴 제외) ② 이름 일치(탈퇴 제외) ③ 이름 일치
// 탈퇴자. 탈퇴 회원은 phone이 파기되므로(P22) 번호로는 잡히지 않고 이름만 남는다 — 탈퇴자의 재가입은
// 승인이 유일한 경로(JoinConfirm이 withdrawn을 400으로 막는다)라 힌트만 주고 승인은 정상 경로다.
type DuplicateHit =
  | { kind: "phone"; member: Member; others: number }
  | { kind: "name"; member: Member; others: number }
  | { kind: "withdrawn"; member: Member; others: number };

function nameKey(s: string): string {
  return s.replace(/\s+/g, "").toLowerCase();
}

function findDuplicate(r: JoinRequest, members: Member[]): DuplicateHit | null {
  const phoneKey = normalizePhoneKR(r.phone);
  const live = members.filter((m) => m.status !== "withdrawn");
  if (phoneKey) {
    // 같은 번호 회원이 2명 이상이면(가족 공용 번호·과거 중복 등록) 첫 사람을 대표로 보이고 나머지는
    // 수로만 말한다 — 힌트는 "있어요"까지고 결정은 사람 몫이다.
    const byPhone = live.filter((m) => normalizePhoneKR(m.phone) === phoneKey);
    if (byPhone.length) return { kind: "phone", member: byPhone[0], others: byPhone.length - 1 };
  }
  const nk = nameKey(r.name);
  if (nk) {
    const byName = live.filter((m) => nameKey(m.name) === nk);
    if (byName.length) return { kind: "name", member: byName[0], others: byName.length - 1 };
    const gone = members.filter((m) => m.status === "withdrawn" && nameKey(m.name) === nk);
    if (gone.length) return { kind: "withdrawn", member: gone[0], others: gone.length - 1 };
  }
  return null;
}

function withdrawnDateLabel(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return `${d.getMonth() + 1}월 ${d.getDate()}일`;
}

export function JoinRequestQueue({
  members,
  membersError,
  staff,
  onOpenMember,
  onApproved,
  focusRequestId,
}: {
  /** 회원 목록(useMembers 데이터). undefined = 아직 응답 전(로딩 중) — 힌트를 단정하지 않는다. */
  members: Member[] | undefined;
  /** 회원 목록 조회 실패 — 중복 감지를 못 한다는 사실을 힌트 자리에 남긴다(승인은 막지 않는다). */
  membersError: boolean;
  /** 담당 코치 이름 해석용(useStaff 데이터). 없으면 "담당 미확인". */
  staff: Staff[] | undefined;
  /** 힌트의 [회원 보기] — 회원 관리가 선택·필터(탈퇴 칩)를 맞춘다. */
  onOpenMember: (memberId: string, opts: { withdrawn: boolean }) => void;
  /** 승인 성공 — 서버가 돌려준 새 회원. 회원 관리가 그 회원을 선택해 담당 배정으로 잇는다. */
  onApproved: (member: Member) => void;
  /** 대시보드 이름 링크로 들어온 요청 id — 그 행을 강조하고, 없으면 "방금 처리됐어요"를 말한다. */
  focusRequestId?: string | null;
}) {
  const joinReqQ = useJoinRequests();
  // 가입 요청 승인은 되돌릴 수 없다(승인 즉시 그 계정이 회원 데이터를 본다) — 목록이 폴링으로
  // 움직이는 화면에서 한 번의 오클릭이 **남의 계정을 남의 기록에 붙인다**. 확인 창을 한 단계 둔다.
  const [approveTarget, setApproveTarget] = useState<JoinRequest | null>(null);
  // 거절은 승인보다 **더** 되돌릴 수 없다: 서버가 신청자의 이름·번호를 지워 버려, 잘못 거절하면
  // 누구였는지조차 화면에서 복구할 수 없다(P55). 그래서 확인 창 + 그 안의 동의 체크 한 겹을 더 둔다.
  const [rejectTarget, setRejectTarget] = useState<JoinRequest | null>(null);

  // 서버는 최신순으로 주는데, 그대로 그리면 폴링(60초·창 포커스)으로 새 요청이 **맨 위에 삽입**돼
  // 보고 있던 행이 전부 한 칸 내려간다 — 승인 버튼을 누르려던 손 밑에서 대상이 바뀌는 구조다.
  // 요청 시각 오름차순(먼저 온 순)으로 고정하면 새 요청은 항상 **끝에 붙어** 기존 행이 움직이지
  // 않는다. 처리 순서도 선착순이라 화면 순서와 대표의 일 처리 순서가 같아진다.
  // (동시각 tie는 id로 갈라 매 응답마다 순서가 흔들리지 않게 한다.)
  //
  // **처리된 요청은 걸러낸다**(P55): 승인·거절이 큐에서 사라지는 것이 계약이고 서버 필터가 그
  // 집행자이지만, 필터가 얹히기 전 배포에서는 승인·거절된 행까지 그대로 내려온다
  // (store.ListJoinRequests에 상태 조건이 없다). 그 상태에선 이미 처리한 사람이 큐에 계속 남아
  // "승인"·"거절" 버튼을 달고 있고, 대표는 처리했는지 아닌지를 화면에서 판단할 수 없다.
  // 서버 필터가 배포되면 이 줄은 아무것도 거르지 않는 no-op가 된다(isJoinPending 주석).
  const joinRequests = [...(joinReqQ.data ?? [])]
    .filter(isJoinPending)
    .sort((a, b) => a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id));
  // 끝에 붙은 새 요청이 그냥 묻히지 않게 표시만 남긴다(최신순 정렬이 하던 "눈에 띄기" 역할).
  // 응답 전(undefined)과 "응답이 빈 목록"을 구분해 넘긴다 — 첫 응답이 기준선이다.
  const freshJoinIds = useFreshIds(joinReqQ.data ? joinRequests.map((r) => r.id) : undefined);

  // 상대 시각은 렌더 시점 시계다. 이 카드는 1분 폴링으로 어차피 다시 그려지므로 별도 타이머를 두지
  // 않는다 — "12분 전"이 13분에 정확히 바뀌는 것이 이 자리의 관심사가 아니다.
  const now = Date.now();

  // 대시보드에서 온 강조 대상이 **응답을 받았는데도** 목록에 없다 — 그 사이 처리됐거나 회원이 앱에서
  // 직접 연결됐다(gone 규칙 재사용). 응답 전에는 단정하지 않는다.
  const focusGone =
    !!focusRequestId && !!joinReqQ.data && !joinRequests.some((r) => r.id === focusRequestId);
  const focusRef = useRef<HTMLDivElement | null>(null);
  // 첫 응답이 도착했을 때 한 번만 스크롤한다 — 폴링마다 스크롤이 튀면 안 된다(deps가 data 자체가
  // 아니라 "도착했는가"인 이유).
  const loaded = joinReqQ.data !== undefined;
  useEffect(() => {
    if (focusRequestId && loaded && focusRef.current) {
      focusRef.current.scrollIntoView({ block: "center" });
    }
  }, [focusRequestId, loaded]);

  const staffName = (uid: string): string => {
    const s = staff?.find((x) => x.uid === uid);
    return s ? staffLabel(s) : "담당 미확인";
  };

  // 0건이면 **한 줄로 접는다**(숨기지 않는다) — 위치를 학습시켜 다음엔 못 찾는 일이 없게. 둘째
  // 문장은 "왜 없을 수 있는지": 번호가 등록된 회원은 자동 매칭으로 요청 없이 연결되고(v2.27 A-5),
  // 다른 센터를 고른 요청은 그 센터 큐에만 쌓인다(v2.33) — "보냈는데요"와 빈 큐가 만날 때의 답.
  if (!joinReqQ.isLoading && !joinReqQ.isError && joinRequests.length === 0) {
    return (
      <div className="mb-3 flex min-h-[36px] flex-wrap items-center gap-x-2 gap-y-0.5 rounded-[10px] border border-line bg-panel px-3 py-1.5 text-[11.5px]">
        <span className="font-bold text-muted">앱 가입 요청</span>
        <span>앱에서 온 가입 요청이 없어요 — 요청이 오면 여기에 먼저 떠요.</span>
        <span className="text-muted">
          번호가 이미 등록된 회원은 요청 없이 자동으로 연결되고, 다른 센터를 고른 요청은 그 센터에만 떠요.
        </span>
        {focusGone && (
          <span className="basis-full text-warn">
            <TriangleAlert className="mr-1 inline h-3.5 w-3.5" />그 요청은 방금 처리됐거나 회원이
            앱에서 직접 연결됐어요.
          </span>
        )}
      </div>
    );
  }

  return (
    <>
      <Card className="mb-3">
        <CardHeader>
          <CardTitle>앱 가입 요청</CardTitle>
          {/* 배지는 목록과 **같은 수**를 말한다 — 응답 길이(처리분 포함)로 세면 목록엔 없는
              건수가 헤더에 뜬다("2건"인데 줄은 하나). 대시보드 대기 건수·네비 배지도 같은 판정을 쓴다. */}
          {joinReqQ.data && <Badge tone="brand">{joinRequests.length}건 대기</Badge>}
        </CardHeader>
        <CardContent>
          {joinReqQ.isLoading ? (
            <Spinner />
          ) : joinReqQ.isError ? (
            // 대시보드와 같은 문장 — 같은 조회(useJoinRequests)라 실패도 같이 난다.
            <ErrorState error={joinReqQ.error} onRetry={() => void joinReqQ.refetch()} />
          ) : (
            <div className="space-y-1.5">
              {focusGone && (
                <p className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] text-warn">
                  <TriangleAlert className="mr-1 inline h-3.5 w-3.5" />그 요청은 방금 처리됐거나
                  회원이 앱에서 직접 연결됐어요 — 아래는 지금 남아 있는 요청입니다.
                </p>
              )}
              {joinRequests.map((r) => {
                const dup = members ? findDuplicate(r, members) : null;
                const waited = now - new Date(r.created_at).getTime();
                const relative = formatRelativeKo(r.created_at, now);
                const focused = focusRequestId === r.id;
                return (
                  <div
                    key={r.id}
                    ref={focused ? focusRef : undefined}
                    className={cn(
                      "rounded-[10px] bg-panel-2 px-3 py-2 text-[12.5px]",
                      focused && "ring-2 ring-brand/60",
                    )}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-0.5">
                        <b>{r.name}</b>
                        {/* 표기 통일(P69) — 앱이 친 원문(010-… 또는 +82…)은 title에만 남긴다. */}
                        <span className="text-muted" title={r.phone}>
                          {formatPhoneKR(r.phone) || r.phone}
                        </span>
                        <span
                          className={cn(
                            "text-[11px]",
                            Number.isNaN(waited) || waited < WAIT_WARN_MS
                              ? "text-muted"
                              : waited < WAIT_DANGER_MS
                                ? "text-warn"
                                : "text-danger",
                          )}
                          title={formatDateTimeKo(r.created_at)}
                        >
                          {/* 시각을 못 읽는 응답이면 원문을 그대로 — 지어내지 않는다. */}
                          {relative ? `${relative} 요청` : r.created_at}
                          {!Number.isNaN(waited) && waited >= WAIT_DANGER_MS
                            ? " · 3일 넘게 기다리는 중"
                            : !Number.isNaN(waited) && waited >= WAIT_WARN_MS
                              ? " · 하루 넘게 기다리는 중"
                              : ""}
                        </span>
                        {/* 이 화면을 열어둔 사이에 새로 들어온 요청 — 목록 끝에 붙으므로 표시로 알린다. */}
                        {freshJoinIds.has(r.id) && <Badge tone="brand">새 요청</Badge>}
                      </span>
                      <span className="flex shrink-0 items-center gap-1">
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => setApproveTarget(r)}
                          title="확인 창에서 이름·번호를 한 번 더 보고 승인합니다"
                        >
                          <Check className="h-3.5 w-3.5" /> 승인
                        </Button>
                        {/* 거절이 **승인보다 눈에 덜 띄어야** 한다: 결과가 더 무겁고(이름·번호가
                            지워진다) 이 큐에서 자주 쓰는 동사가 아니다. 그래서 면 없는 ghost로 두어
                            손이 먼저 가는 자리는 승인이 갖게 하고, 무게는 확인 창에서 세운다. */}
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => setRejectTarget(r)}
                          title="거절하면 신청자의 이름·번호가 지워집니다 — 확인 창에서 한 번 더 확인합니다"
                        >
                          <UserX className="h-3.5 w-3.5" /> 거절
                        </Button>
                      </span>
                    </div>
                    {/* 중복 감지 힌트 — 회원 목록 상태에 따라 세 갈래: 실패(확인 불가 고지) / 응답 전(아무
                        말도 하지 않는다 — "없어요"를 단정하면 로딩 중에 승인을 눌러 회원이 2명 된다) /
                        도착(대조 결과). */}
                    {membersError ? (
                      <p className="mt-1 text-[10.5px] leading-[1.7] text-muted">
                        회원 목록을 못 불러와 같은 번호가 있는지 확인하지 못했어요 — 승인 전에 회원
                        검색으로 확인해주세요.
                      </p>
                    ) : dup ? (
                      <DuplicateHint hit={dup} staffName={staffName} onOpenMember={onOpenMember} />
                    ) : null}
                  </div>
                );
              })}
            </div>
          )}
          {/* 승인·거절 실패 문구는 각 확인 창 안에 있다(창이 열린 채로 남아 재시도가 그 자리에서 된다). */}
          <p className="mt-2.5 text-[10.5px] leading-[1.8] text-muted">
            {/* 내부 티켓 번호(P48)·"폴백 경로" 같은 개발 용어는 화면에서 뺀다(어드민 UX 감사). */}
            전화번호가 자동으로 맞지 않은 회원의 "센터 찾기" 요청만 여기 쌓입니다. 목록은 1분마다
            자동 갱신되고, 먼저 온 순으로 고정돼 새 요청이 끼어들어도 기존 줄이 밀리지 않습니다.
            <br />
            우리 회원이 아니거나 잘못 들어온 요청은 <b className="text-ink">거절</b>로 큐에서
            내립니다 — 거절하면 그 사람의 이름·번호는 지워지고, 필요하면 회원이 앱에서 다시 요청할
            수 있어요.
          </p>
        </CardContent>
      </Card>

      {approveTarget && (
        <ApproveJoinModal
          request={approveTarget}
          onClose={() => setApproveTarget(null)}
          // 목록에서 사라진 요청(다른 기기에서 이미 승인·취소됨)을 계속 승인 대상으로 붙들지 않는다.
          gone={!joinRequests.some((r) => r.id === approveTarget.id)}
          // 확인 창의 경고는 **지금 목록**으로 다시 판정한다 — 창을 연 사이에 대표가 회원 번호를
          // 고쳤거나 다른 창에서 등록했으면 힌트가 바뀌어야 한다.
          duplicate={members ? findDuplicate(approveTarget, members) : null}
          membersUnknown={!members}
          onApproved={onApproved}
        />
      )}
      {rejectTarget && (
        <RejectJoinModal
          request={rejectTarget}
          onClose={() => setRejectTarget(null)}
          // 승인 창과 **같은 판정**(다른 기기에서 이미 처리됨) — 두 창이 다른 규칙을 쓰면 같은
          // 목록을 보고도 한쪽만 "사라진 요청"이라고 말한다.
          gone={!joinRequests.some((r) => r.id === rejectTarget.id)}
        />
      )}
    </>
  );
}

// 행 아래 중복 힌트(warn 톤). 문구는 "있어요"까지만 — 가족이 한 번호를 쓰는 경우(부모 번호로 자녀
// 등록)나 동명이인이 있어 결정은 사람이 한다. 각 갈래의 다음 행동을 같은 문장에 붙인다.
function DuplicateHint({
  hit,
  staffName,
  onOpenMember,
}: {
  hit: DuplicateHit;
  staffName: (uid: string) => string;
  onOpenMember: (memberId: string, opts: { withdrawn: boolean }) => void;
}) {
  const m = hit.member;
  const othersNote = hit.others > 0 ? ` 외 ${hit.others}명` : "";
  return (
    <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-[10.5px] leading-[1.7] text-warn">
      <span>
        <TriangleAlert className="mr-1 inline h-3 w-3" />
        {hit.kind === "phone" ? (
          <>
            같은 번호의 회원이 있어요 — <b>{m.name}</b>
            {othersNote} (담당 {m.trainer_id ? staffName(m.trainer_id) : "미배정"}) · 앱{" "}
            {m.app_linked ? "연결됨" : "미연결"}
          </>
        ) : hit.kind === "name" ? (
          <>
            같은 이름의 회원이 있어요 — <b>{m.name}</b>
            {othersNote} ({maskPhoneKR(m.phone) || "번호 없음"}). 번호가 다르면 다른 사람일 수
            있어요.
          </>
        ) : (
          <>
            같은 이름의 탈퇴 회원이 있어요{othersNote}
            {withdrawnDateLabel(m.withdrawn_at) ? ` (탈퇴 ${withdrawnDateLabel(m.withdrawn_at)})` : ""}.
            재가입이면 그대로 승인하면 돼요.
          </>
        )}
      </span>
      <Button
        size="sm"
        variant="ghost"
        className="h-6 px-2 text-[10.5px]"
        onClick={() => onOpenMember(m.id, { withdrawn: hit.kind === "withdrawn" })}
      >
        회원 보기
      </Button>
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

// 승인·거절 대상이 **서버에 없다**(리소스 404 — 라우터 404는 제외). 뜻은 하나다: 이 요청은
// 처리할 것이 아니라 없어진 것이다(회원이 그 사이 앱에서 직접 연결됐거나 다른 기기에서 처리됨).
// 목록 재조회는 훅(useApproveJoin·useRejectJoin onError)이 이미 했다 — 여기서는 말만 한다.
// 409(이미 처리됨)는 서버 문구가 그 자체로 정확해 일반 갈래로 흘린다.
function isJoinRequestGone(e: unknown): boolean {
  return e instanceof ApiError && e.status === 404 && !isRouteNotFound(e);
}

function JoinRequestGoneNotice() {
  return (
    <p className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] leading-[1.8] text-warn">
      <TriangleAlert className="mr-1 inline h-3.5 w-3.5" />
      이 요청은 이미 처리됐거나 회원이 그 사이 앱에서 직접 연결됐어요 — 목록을 새로 불러왔으니
      창을 닫고 확인해주세요. 이 사람에게는 <b>승인도 거절도 더 필요 없어요</b>(이미 연결된
      회원을 승인으로 다시 만들면 기존 기록과 어긋납니다).
    </p>
  );
}

// 가입 요청 승인 확인 — 되돌리기가 없는 유일한 1클릭 동작이라 한 단계를 세운다.
//
// 왜 폴링을 끄지 않고 확인 창을 세웠나: 회원 앱이 "센터에서 승인하면 연결돼요"라고 약속하고
// 대기 화면에 머문다(queries.ts JOIN_REQUESTS_POLL_MS). 폴링을 끄면 그 약속이 깨진다.
// 정렬 고정만으로도 삽입에 의한 밀림은 사라지지만, **삭제**(다른 기기·다른 대표가 먼저 승인)와
// 손이 이미 움직이는 중인 클릭까지는 막지 못한다 — 그래서 대상을 객체로 붙들고 이름·번호를
// 다시 보여준 뒤에 실행한다. 승인은 하루 0~2건이라 한 클릭의 비용이 오연결 위험보다 싸다.
//
// 중복 감지(P69)가 얹힌 뒤 창은 세 얼굴이다:
//   번호 일치 · 앱 미연결  제목이 바뀌고("이미 있는 회원과 번호가 같아요") 동의 체크 뒤에만 승인이
//                         열린다 — 승인하면 그 사람이 **2명**이 된다. 올바른 수습은 승인이 아니라
//                         회원 번호 확인 → 회원이 앱에서 같은 번호를 다시 인증 → 자동 연결(요청은
//                         서버가 파기). 화면 문구가 그 순서를 그대로 말한다.
//   번호 일치 · 앱 연결됨  승인 **비활성**. 이미 연결된 회원의 잔여 요청(A-5 이전 좀비)이라 거절이
//                         정리다. 서버도 어차피 409로 막지만 화면이 먼저 말한다.
//   이름만 일치           경고 한 줄, 체크 없음 — 동명이인이 정상 경로다.
// 거절 창의 동의 체크를 승인 창에 **일반적으로** 두지 않는 이유(RejectJoinModal 주석)는 그대로다 —
// 체크는 번호 일치라는 특정 사고 경로에만 붙는다.
function ApproveJoinModal({
  request,
  onClose,
  gone,
  duplicate,
  membersUnknown,
  onApproved,
}: {
  request: JoinRequest;
  onClose: () => void;
  gone: boolean;
  duplicate: DuplicateHit | null;
  /** 회원 목록이 아직 없다(로딩·실패) — 중복 여부를 모른다고 말한다. */
  membersUnknown: boolean;
  onApproved: (member: Member) => void;
}) {
  const approveJoin = useApproveJoin();
  const [acknowledged, setAcknowledged] = useState(false);
  const phoneDup = duplicate?.kind === "phone" ? duplicate : null;
  const blockedByLinked = !!phoneDup && phoneDup.member.app_linked;
  const needsAck = !!phoneDup && !phoneDup.member.app_linked;
  return (
    <Modal
      open
      onClose={onClose}
      title={phoneDup ? "이미 있는 회원과 번호가 같아요" : "가입 요청 승인"}
    >
      <div className="space-y-3">
        <p className="text-[12.5px]">
          <b>{request.name}</b>{" "}
          <span className="text-muted" title={request.phone}>
            {formatPhoneKR(request.phone) || request.phone}
          </span>{" "}
          님을 이 센터 회원으로 연결합니다.
        </p>
        {gone ? (
          <p className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] text-warn">
            <TriangleAlert className="mr-1 inline h-3.5 w-3.5" />이 요청이 목록에서 사라졌어요 —
            다른 기기에서 이미 처리됐을 수 있습니다. 창을 닫고 목록을 다시 확인해주세요.
          </p>
        ) : phoneDup ? (
          <div className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2.5">
            <div className="flex items-center gap-1 text-[11.5px] font-extrabold text-warn">
              <TriangleAlert className="h-3.5 w-3.5" /> 같은 번호의 회원 — {phoneDup.member.name}
              {phoneDup.others > 0 ? ` 외 ${phoneDup.others}명` : ""} · 앱{" "}
              {phoneDup.member.app_linked ? "연결됨" : "미연결"}
            </div>
            {blockedByLinked ? (
              <p className="mt-1 text-[10.5px] leading-[1.8] text-muted">
                이 요청은 지난 요청의 잔여일 가능성이 커요 — <b className="text-ink">거절로 정리하세요</b>.
                그 회원은 이미 앱에 연결돼 있어 승인으로 다시 만들면 기록이 둘로 갈립니다.
              </p>
            ) : (
              <p className="mt-1 text-[10.5px] leading-[1.8] text-muted">
                승인하면 <b className="text-ink">{phoneDup.member.name} 님이 2명</b>이 됩니다. 이
                사람이 그 회원이면 승인하지 말고 회원 정보의 번호를 확인한 뒤, 회원에게 앱에서{" "}
                <b className="text-ink">'번호 다시 인증하기'</b>를 눌러 달라고 하세요 — 같은 번호를
                다시 인증하면 자동으로 연결되고 이 요청은 저절로 사라져요.
              </p>
            )}
          </div>
        ) : (
          <p className="text-[10.5px] text-muted">
            승인하면 그 계정이 바로 이 회원의 기록을 보게 되고{" "}
            <b className="text-ink">되돌리는 버튼은 없습니다</b>. 목록은 1분마다 갱신되니 눈앞의 그
            사람이 맞는지 이름·번호를 한 번만 확인해주세요.
          </p>
        )}
        {!gone && duplicate?.kind === "name" && (
          <p className="text-[10.5px] leading-[1.7] text-warn">
            <TriangleAlert className="mr-1 inline h-3 w-3" />
            같은 이름의 회원({duplicate.member.name} · {maskPhoneKR(duplicate.member.phone) || "번호 없음"})이
            있어요 — 동명이인이 아닌지 번호를 한 번 더 보세요.
          </p>
        )}
        {!gone && membersUnknown && (
          <p className="text-[10.5px] leading-[1.7] text-muted">
            회원 목록을 못 불러와 같은 번호의 회원이 있는지 확인하지 못했어요 — 승인 전에 회원
            검색으로 확인해주세요.
          </p>
        )}
        {!gone && needsAck && (
          <label className="flex items-start gap-2 text-[11.5px] leading-[1.7]">
            <input
              type="checkbox"
              className="mt-0.5"
              checked={acknowledged}
              onChange={(e) => setAcknowledged(e.target.checked)}
            />
            <span>회원이 2명이 될 수 있다는 것을 확인했어요</span>
          </label>
        )}
        {approveJoin.isError &&
          (isJoinRequestGone(approveJoin.error) ? (
            <JoinRequestGoneNotice />
          ) : (
            <p className="text-[11px] text-danger">승인 실패: {approveJoin.error.message}</p>
          ))}
        <Button
          className="w-full"
          disabled={approveJoin.isPending || gone || blockedByLinked || (needsAck && !acknowledged)}
          onClick={() =>
            approveJoin.mutate(request.id, {
              // 창은 성공까지 마운트돼 있어 mutate-레벨 콜백이 떨어지지 않는다(queries.ts 주석).
              onSuccess: (member) => {
                onApproved(member);
                onClose();
              },
            })
          }
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

// 가입 요청 거절 확인(P55) — 승인 창의 쌍둥이지만 **한 겹이 더 있다**.
//
// 승인과 거절 중 되돌리기가 더 어려운 쪽은 거절이다: 승인은 잘못돼도 그 계정이 누구였는지 화면에
// 남아 회원 관리에서 수습할 수 있는데, 거절은 서버가 이름·번호를 지워 **누구를 거절했는지조차**
// 남지 않는다(다시 요청해 달라고 연락할 번호가 화면에 없다). 그런데 목록에서의 클릭 비용은
// 두 버튼이 같다 — 그 비대칭을 여기서 메운다:
//   · 목록 버튼: 승인은 outline(면 있음), 거절은 ghost(면 없음) — 손이 먼저 가는 자리를 가른다.
//   · 확인 창: 무엇이 지워지는지 문장으로 말하고, **동의 체크를 눌러야** 거절 버튼이 열린다.
// 승인 창에 같은 체크를 두지 않는 이유도 같다 — 하루 0~2건의 정상 경로에 마찰을 더하면 대표는
// 두 창의 체크를 똑같이 습관으로 눌러 넘기게 되고, 그 순간 이 장치는 양쪽 다 무의미해진다.
function RejectJoinModal({
  request,
  onClose,
  gone,
}: {
  request: JoinRequest;
  onClose: () => void;
  gone: boolean;
}) {
  const rejectJoin = useRejectJoin();
  const [understood, setUnderstood] = useState(false);
  return (
    <Modal open onClose={onClose} title="가입 요청 거절">
      <div className="space-y-3">
        <p className="text-[12.5px]">
          <b>{request.name}</b>{" "}
          <span className="text-muted" title={request.phone}>
            {formatPhoneKR(request.phone) || request.phone}
          </span>{" "}
          님의 가입 요청을 거절합니다. 이 계정은{" "}
          <b className="text-ink">이 센터의 회원이 되지 않습니다</b>.
        </p>
        {gone ? (
          <p className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] text-warn">
            <TriangleAlert className="mr-1 inline h-3.5 w-3.5" />이 요청이 목록에서 사라졌어요 —
            다른 기기에서 이미 처리됐을 수 있습니다. 창을 닫고 목록을 다시 확인해주세요.
          </p>
        ) : (
          <div className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2.5">
            <div className="flex items-center gap-1 text-[11.5px] font-extrabold text-warn">
              <TriangleAlert className="h-3.5 w-3.5" /> 이름·번호가 지워지고 되돌릴 수 없어요
            </div>
            <p className="mt-1 text-[10.5px] leading-[1.8] text-muted">
              거절하면 서버가 <b className="text-ink">{request.name}</b> 님의{" "}
              <b className="text-ink">이름과 전화번호를 지웁니다</b> — 승인되지 않은 사람의 정보를
              센터가 계속 들고 있지 않기 위해서예요. 되돌리는 버튼이 없고, 지워진 뒤에는{" "}
              <b className="text-ink">누구였는지 이 화면에서 확인할 수 없습니다</b>.
            </p>
            <p className="mt-1.5 text-[10.5px] leading-[1.8] text-muted">
              잘못 거절했다면 그 회원에게 <b className="text-ink">앱에서 다시 요청</b>해 달라고
              직접 연락해야 해요(새 요청으로 큐에 다시 쌓입니다). 우리 회원이 맞는지 헷갈리면
              거절하지 말고 창을 닫아 두세요 — 요청은 그대로 남아 있습니다.
            </p>
          </div>
        )}
        {!gone && (
          <label className="flex items-start gap-2 text-[11.5px] leading-[1.7]">
            <input
              type="checkbox"
              className="mt-0.5"
              checked={understood}
              onChange={(e) => setUnderstood(e.target.checked)}
            />
            <span>
              이름·번호가 지워지고 되돌릴 수 없다는 것을 확인했어요
            </span>
          </label>
        )}
        {rejectJoin.isError &&
          // 404는 두 가지다(P56 B6·B12). 라우터 404(code=route_not_found)만 "미배포"고, 그 외
          // 404는 **요청 문서가 없다**는 뜻 — 회원이 그 사이 앱에서 직접 연결돼 JoinConfirm이
          // pending을 파기한 좀비 경합이 유일한 원인이다. 종전엔 둘을 못 갈라 후자에도 "미배포 —
          // 그동안은 승인만 처리하세요"라고 했는데, 그 지시대로 승인하면 P55 C-2(진짜 레코드에
          // 붙은 회원권·예약·기록·사진을 빈 레코드로 갈아치움)다. 지금은 서버 가드가 409로 막지만
          // 지시 자체가 틀렸다 — 없어진 요청은 처리할 것이 아니라 목록에서 빠져야 하는 것이다.
          (isRouteNotFound(rejectJoin.error) ? (
            <p className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] leading-[1.8] text-warn">
              <TriangleAlert className="mr-1 inline h-3.5 w-3.5" />
              거절 기능이 아직 서버에 올라가지 않았어요 — 서버가 업데이트되면 쓸 수 있습니다. 이
              요청은 그대로 남아 있으니 창을 닫아 두고 그때 다시 거절하면 돼요.
            </p>
          ) : isJoinRequestGone(rejectJoin.error) ? (
            <JoinRequestGoneNotice />
          ) : (
            <p className="text-[11px] text-danger">거절 실패: {rejectJoin.error.message}</p>
          ))}
        <Button
          className="w-full"
          variant="danger"
          disabled={rejectJoin.isPending || gone || !understood}
          onClick={() => rejectJoin.mutate(request.id, { onSuccess: onClose })}
        >
          <UserX className="h-4 w-4" /> {rejectJoin.isPending ? "거절 중…" : "거절하기"}
        </Button>
        <Button className="w-full" variant="outline" onClick={onClose}>
          취소
        </Button>
      </div>
    </Modal>
  );
}
