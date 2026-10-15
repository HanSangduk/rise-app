// Home Work — 목업 s-hw 1:1. 배정 폼(scope·부상 자동제외·items 에디터·반복) + 현황.
// "현황"은 목업처럼 회원별이 아니라 배정건별 완료율로 집계한다 — hw-checks 조회가 계약 확장
// 가정([가정 3])이라 회원별 교차 집계까지 쌓으면 불확실성이 커져, 배정 단위 집계로 범위를 좁혔다.
import { useMemo, useState } from "react";
import { AlertTriangle, ChevronDown, ChevronRight, Plus, Send, Trash2 } from "lucide-react";
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
  ProgressBar,
  Select,
  Spinner,
} from "@/components/ui";
import { useAuth } from "@/lib/auth";
import { useCreateHomework, useHomeworks, useHwChecks, useMembers } from "@/lib/queries";
import { addDays, ratioState, todayStr } from "@/lib/format";
import {
  WEEKDAY_LABEL,
  type Homework,
  type HomeworkItem,
  type HomeworkScheduleType,
  type HomeworkScope,
  type MemberWithPasses,
  type Weekday,
} from "@/lib/types";

const WEEKDAYS: Weekday[] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

const TEMPLATES: Record<string, HomeworkItem[]> = {
  "하체 기초": [
    { name: "스쿼트", sets: 3, reps: "15", note: "무릎 방향 주의" },
    { name: "런지", sets: 3, reps: "10(양쪽)", note: "" },
  ],
  코어: [
    { name: "플랭크", sets: 3, reps: "40초", note: "" },
    { name: "데드버그", sets: 3, reps: "12", note: "" },
  ],
  "어깨 재활": [
    { name: "밴드 외회전", sets: 3, reps: "15", note: "천천히, 통증 없이" },
    { name: "힙힌지 드릴", sets: 3, reps: "10", note: "벽 터치" },
    { name: "걷기", sets: null, reps: "30분", note: "주 3회" },
  ],
};

export function Homework() {
  const { me } = useAuth();
  const isOwner = me?.role === "owner";
  const membersQ = useMembers();
  const homeworksQ = useHomeworks();
  const createHomework = useCreateHomework();

  const [scope, setScope] = useState<HomeworkScope>("individual");
  const [individualId, setIndividualId] = useState("");
  const [manuallyIncluded, setManuallyIncluded] = useState<Set<string>>(new Set());
  const [items, setItems] = useState<HomeworkItem[]>([
    { name: "", sets: 3, reps: "", note: "" },
  ]);
  const [scheduleType, setScheduleType] = useState<HomeworkScheduleType>("weekly");
  const [days, setDays] = useState<Set<Weekday>>(new Set(["mon", "wed", "fri"]));
  const [from, setFrom] = useState(todayStr());
  const [to, setTo] = useState(addDays(todayStr(), 27));

  const scopeTargets = useMemo(() => {
    const all = membersQ.data ?? [];
    if (scope === "individual") return individualId ? all.filter((m) => m.id === individualId) : [];
    if (scope === "my_members") return all.filter((m) => m.trainer_id === me?.uid);
    return all; // center_notice
  }, [membersQ.data, scope, individualId, me?.uid]);

  // 부상 자동 제외는 일괄 배정(담당 전체·센터 공지)에만 적용 — 개인 지정은 재활 배정일 수 있어 제외하지 않는다.
  const injuredInScope = useMemo(
    () => (scope === "individual" ? [] : scopeTargets.filter((m) => m.flags.some((f) => f.type === "injury"))),
    [scope, scopeTargets],
  );
  const finalTargets = scopeTargets.filter((m) => !injuredInScope.includes(m) || manuallyIncluded.has(m.id));
  // 서버로 나가는 두 값. **후보 전체**(부상 회원 포함)를 target_member_ids로 보내고, 되살릴
  // 사람만 include로 지목한다 — 서버가 제외를 자기가 다시 계산하기 때문이다(domain.ResolveTargets).
  // 이미 걸러낸 목록(finalTargets)을 보내면 include 대상이 후보에 없어 수동 포함이 무시된다.
  const candidateIds = scopeTargets.map((m) => m.id);
  // manuallyIncluded는 scope를 바꿔도 남는 state다 — 지금 실제로 부상 제외 대상인 사람만 싣는다.
  const includeIds = injuredInScope.filter((m) => manuallyIncluded.has(m.id)).map((m) => m.id);

  // 센터 공지형(전 회원) 배정의 2단 확인. 서버에 Home Work **삭제 API가 없다**
  // (router.go: GET·POST /homeworks 둘뿐) — 한 번 나간 배정은 전 회원 앱 홈에 그대로 남고
  // 회수할 방법이 어드민에도 서버에도 없다. 개인·담당 전체 배정과 달리 "잘못 보냈으면 그
  // 회원에게 말하면 되는" 범위를 넘어서므로, 되돌릴 수 없는 다른 동작들(노쇼·환불·납부 확정)과
  // 같은 인라인 2단 확인을 건다.
  const [assignConfirm, setAssignConfirm] = useState(false);
  const needsAssignConfirm = scope === "center_notice";

  // 템플릿 칩이 입력분을 덮어쓰기 전에 받는 확인(=고른 템플릿 이름). null이면 확인 대기 없음.
  const [templateConfirm, setTemplateConfirm] = useState<string | null>(null);
  // "지금 입력분이 있다" 판정. 이름·횟수·메모 어느 칸이든 손댔으면 덮어쓰기가 손실이다 —
  // sets는 초기값 3이 들어 있어 판정에서 뺀다(안 건드린 새 행도 dirty로 잡히면 확인이 늘 뜬다).
  const itemsDirty = items.some(
    (it) => it.name.trim() !== "" || it.reps.trim() !== "" || it.note.trim() !== "",
  );
  const filledItemCount = items.filter(
    (it) => it.name.trim() !== "" || it.reps.trim() !== "" || it.note.trim() !== "",
  ).length;

  function applyTemplate(name: string, mode: "replace" | "append") {
    const tpl = TEMPLATES[name].map((it) => ({ ...it }));
    setItems((prev) =>
      mode === "replace"
        ? tpl
        : // 빈 행(아직 아무것도 안 적은 마지막 줄)까지 남기면 배정 항목 사이에 구멍이 생긴다.
          [...prev.filter((it) => it.name.trim() !== ""), ...tpl],
    );
    setTemplateConfirm(null);
  }

  function toggleManualInclude(id: string) {
    setManuallyIncluded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleDay(d: Weekday) {
    setDays((prev) => {
      const next = new Set(prev);
      if (next.has(d)) next.delete(d);
      else next.add(d);
      return next;
    });
  }

  function updateItem(i: number, patch: Partial<HomeworkItem>) {
    setItems((prev) => prev.map((it, idx) => (idx === i ? { ...it, ...patch } : it)));
  }

  // 매주 반복인데 요일 0개면 "언제 하라는 과제인지"가 성립하지 않는다 — 제출 차단.
  const weeklyDaysMissing = scheduleType === "weekly" && days.size === 0;
  // 항목명이 하나도 없으면 서버에 보낼 과제가 없다. 종전엔 submit()만 이걸 보고 조용히
  // return해서, 버튼은 눌리는데 로딩도 에러도 안 뜨는 먹통 상태가 됐다 — disabled에도 건다.
  const itemsMissing = !items.some((it) => it.name.trim());
  // 기간 역전(시작 > 종료) — 같은 폼이 요일 누락을 막고 예약·회원권 폼은 날짜 역전을 검사한다.
  const rangeInverted = !!from && !!to && to < from;
  const submitBlocked =
    !finalTargets.length || itemsMissing || weeklyDaysMissing || rangeInverted;

  function submit() {
    if (submitBlocked) return;
    createHomework.mutate(
      {
        trainer_id: me?.uid ?? "",
        scope,
        target_member_ids: candidateIds,
        // 부상 자동제외를 뒤집을 회원. excluded(서버 파생값)를 보내면 400이다 — types.ts
        // HomeworkCreateRequest 주석 참고.
        include: includeIds,
        items: items.filter((it) => it.name.trim()),
        schedule: {
          type: scheduleType,
          days: scheduleType === "weekly" ? Array.from(days) : [],
          from,
          to,
        },
      },
      {
        onSuccess: () => {
          setItems([{ name: "", sets: 3, reps: "", note: "" }]);
          setManuallyIncluded(new Set());
          // 확인 패널을 닫는다 — 남겨두면 폼이 비워진 상태에서 "확정" 버튼이 계속 떠 있어
          // 같은 배정을 한 번 더 보낸 것처럼 읽힌다(회수 수단이 없는 동작이라 더 위험하다).
          setAssignConfirm(false);
          // 템플릿 확인도 함께 닫는다 — 항목이 비워졌으니 "0개 항목을 덮어쓴다"는 물음만 남는다.
          setTemplateConfirm(null);
        },
      },
    );
  }

  return (
    <div>
      <h2 className="text-[16.5px] font-bold">Home Work</h2>
      <p className="mt-0.5 mb-3.5 text-xs text-muted">
        수업 밖 과제를 배정하고, 완료율로 관리합니다.
      </p>

      <div className="grid gap-3 lg:grid-cols-[3fr_2fr]">
        <Card>
          <CardHeader>
            <CardTitle>새 Home Work 배정</CardTitle>
            {/* 센터 공지형(전 회원)은 확인을 한 단계 거친다 — 아래 assignConfirm 주석. */}
            <Button
              size="sm"
              disabled={submitBlocked || createHomework.isPending}
              onClick={() => (needsAssignConfirm ? setAssignConfirm(true) : submit())}
            >
              <Send className="h-3.5 w-3.5" /> {createHomework.isPending ? "배정 중…" : "배정 → 앱 전송"}
            </Button>
          </CardHeader>
          <CardContent>
            {/* needsAssignConfirm까지 함께 보는 이유: 확인을 띄운 뒤 배정 대상 칩을 바꾸면
                패널만 남아 "무엇을 확인하는 중인지"가 화면과 어긋난다. */}
            {assignConfirm && needsAssignConfirm && (
              <div className="mb-2.5 rounded-[10px] border border-danger/40 bg-danger/[0.08] p-3">
                <p className="text-[11.5px] leading-relaxed text-danger">
                  <AlertTriangle className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />
                  센터 <b>전 회원 {finalTargets.length}명</b>의 앱 홈에 이 과제가 뜹니다.{" "}
                  <b>배정 후에는 취소할 수 없어요</b> — 배정을 지우는 기능이 아직 없어서, 잘못
                  보내도 회수하거나 수정할 수 없습니다. 대상·항목·기간을 한 번만 더 봐주세요.
                </p>
                <div className="mt-2 flex gap-2">
                  <Button
                    size="sm"
                    variant="danger"
                    disabled={submitBlocked || createHomework.isPending}
                    onClick={submit}
                  >
                    {createHomework.isPending ? "배정 중…" : "전 회원에게 배정 확정"}
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    disabled={createHomework.isPending}
                    onClick={() => setAssignConfirm(false)}
                  >
                    돌아가기
                  </Button>
                </div>
              </div>
            )}
            {weeklyDaysMissing && (
              <p className="mb-2 text-[11px] text-warn">매주 반복은 요일을 1개 이상 선택해야 배정할 수 있어요.</p>
            )}
            {itemsMissing && (
              <p className="mb-2 text-[11px] text-warn">항목명을 1개 이상 입력해야 배정할 수 있어요.</p>
            )}
            {rangeInverted && (
              <p className="mb-2 text-[11px] text-warn">기간 종료일은 시작일 이후여야 해요.</p>
            )}
            {createHomework.isSuccess && (
              <p className="mb-2 text-[11px] text-ok">
                배정 완료 — 대상 회원 앱의 "오늘 Home Work"에 표시됩니다.
              </p>
            )}
            {createHomework.isError && (
              <p className="mb-2 text-[11px] text-danger">배정 실패: {createHomework.error.message}</p>
            )}
            {/* 회원 조회 실패를 "대상 0명"으로 위장하지 않는다 — 조회가 깨진 상태에서 "내 담당
                전체"를 누르면 대상이 0명으로 보여 배정을 포기하게 된다(Members.tsx 패턴 재사용). */}
            {membersQ.isError && (
              <div className="mb-2">
                <ErrorState error={membersQ.error} onRetry={() => void membersQ.refetch()} />
              </div>
            )}
            <div className="mb-1 text-[11.5px] text-muted">배정 대상</div>
            <div className="mb-2 flex flex-wrap">
              <Chip active={scope === "individual"} onClick={() => setScope("individual")}>
                회원 1명
              </Chip>
              <Chip active={scope === "my_members"} onClick={() => setScope("my_members")}>
                내 담당 전체
              </Chip>
              {isOwner && (
                <Chip active={scope === "center_notice"} onClick={() => setScope("center_notice")}>
                  센터 공지형 (대표 전용)
                </Chip>
              )}
            </div>
            {scope === "individual" && (
              <Select value={individualId} onChange={(e) => setIndividualId(e.target.value)} className="mb-2">
                <option value="">회원을 선택하세요</option>
                {(membersQ.data ?? []).map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.name}
                  </option>
                ))}
              </Select>
            )}
            {scope !== "individual" && (
              <p className="mb-2 text-[11px] text-muted">
                {membersQ.isLoading
                  ? "대상 계산 중…"
                  : membersQ.isError
                    ? "회원 목록을 불러오지 못해 대상을 셀 수 없어요."
                    : `대상 ${finalTargets.length}명 (자동 계산됨)`}
              </p>
            )}

            {injuredInScope.length > 0 && (
              <Card className="mb-2.5 border-warn/30 bg-warn/[0.08]">
                <CardContent className="pt-3">
                  <div className="flex items-start gap-1.5 text-[11px] text-warn">
                    <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                    <span>
                      부상 플래그 회원은 자동 제외됩니다 — 개별로 다시 포함할 수 있습니다.
                    </span>
                  </div>
                  <div className="mt-1.5">
                    {injuredInScope.map((m) => (
                      <Chip key={m.id} active={manuallyIncluded.has(m.id)} onClick={() => toggleManualInclude(m.id)}>
                        {m.name} {manuallyIncluded.has(m.id) ? "(포함)" : "(제외)"}
                      </Chip>
                    ))}
                  </div>
                </CardContent>
              </Card>
            )}

            <ItemsEditor items={items} onUpdate={updateItem} onAdd={() => setItems((p) => [...p, { name: "", sets: 3, reps: "", note: "" }])} onRemove={(i) => setItems((p) => p.filter((_, idx) => idx !== i))} />

            <div className="mt-2.5 flex flex-wrap items-center gap-1.5 text-[11.5px]">
              <span className="text-muted">반복:</span>
              <Chip active={scheduleType === "weekly"} onClick={() => setScheduleType("weekly")}>
                매주 반복
              </Chip>
              <Chip active={scheduleType === "once"} onClick={() => setScheduleType("once")}>
                1회성
              </Chip>
              {scheduleType === "weekly" && (
                <span className="ml-1 flex flex-wrap">
                  {WEEKDAYS.map((d) => (
                    <Chip key={d} active={days.has(d)} onClick={() => toggleDay(d)}>
                      {WEEKDAY_LABEL[d]}
                    </Chip>
                  ))}
                </span>
              )}
            </div>
            <div className="mt-2 flex flex-wrap items-center gap-1.5 text-[11.5px]">
              <span className="text-muted">기간:</span>
              <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="w-auto" />
              <span className="text-muted">~</span>
              <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="w-auto" />
            </div>

            <div className="mt-2.5 text-[11.5px]">
              <span className="text-muted">템플릿: </span>
              {Object.keys(TEMPLATES).map((name) => (
                <Chip
                  key={name}
                  active={templateConfirm === name}
                  onClick={() => {
                    // 빈 폼이면 종전대로 즉시 채운다 — 잃을 것이 없는 자리에 마찰을 더하지 않는다.
                    if (!itemsDirty) {
                      applyTemplate(name, "replace");
                      return;
                    }
                    setTemplateConfirm((cur) => (cur === name ? null : name));
                  }}
                >
                  {name}
                </Chip>
              ))}
            </div>
            {/* 템플릿 칩이 **손으로 넣던 항목을 통째로 덮어쓰던 자리**다. 칩이 에디터 아래에
                있어 더 잘 눌리는데 되돌리기(undo)가 없어, 한 번의 오클릭이 방금 적은 과제를
                지웠다. 빈 폼이 아니면 무엇이 일어나는지 먼저 말하고 두 갈래를 준다 —
                "덮어쓰기"는 잃는 것을 수로 밝히고, "뒤에 추가"는 아무것도 잃지 않는 쪽이다.
                Modal 대신 인라인 패널인 이유는 이 폼의 다른 확인들(예약 화면 노쇼·취소 패널)과
                같은 규약이고, window.confirm은 이 어드민 어디에도 쓰지 않기 때문이다. */}
            {templateConfirm && (
              <div className="mt-1.5 rounded-[10px] border border-warn/40 bg-warn/[0.08] p-2.5">
                <p className="text-[11px] leading-relaxed text-warn">
                  <b>{templateConfirm}</b> 템플릿 {TEMPLATES[templateConfirm].length}항목을
                  넣습니다. 지금 입력한 {filledItemCount}개 항목을 <b>덮어쓰면 되돌릴 수 없어요</b>.
                </p>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  <Button size="sm" variant="danger" onClick={() => applyTemplate(templateConfirm, "replace")}>
                    덮어쓰기
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => applyTemplate(templateConfirm, "append")}>
                    뒤에 추가
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => setTemplateConfirm(null)}>
                    취소
                  </Button>
                </div>
              </div>
            )}

            {/* 배정 실패 메시지는 폼 상단(성공 문구 옆) 1곳에서만 — 같은 에러 이중 표시 제거. */}
            {/* 이 폼의 비가역성을 한자리에 적는다 — 배정도, 템플릿 덮어쓰기도 되돌리는 버튼이
                없다. 확인 패널은 누른 뒤에야 보이지만 이 문장은 누르기 전부터 보인다. */}
            <p className="mt-2.5 text-[10.5px] leading-relaxed text-muted">
              배정하면 회원 앱 홈에 뜨고, 회원이 체크하면 완료율로 집계됩니다.{" "}
              <b className="text-warn">배정을 취소·수정하는 기능이 아직 없어요</b> — 보내기 전에
              대상과 항목을 확인해주세요. 템플릿 칩도 지금 입력한 항목을 덮어쓰면 되돌릴 수
              없습니다(덮어쓰기 전에 한 번 물어봐요). 리마인드 푸시 발송은 준비 중이에요.
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>현황</CardTitle>
          </CardHeader>
          <CardContent>
            {homeworksQ.isLoading ? (
              <Spinner />
            ) : homeworksQ.isError ? (
              <ErrorState error={homeworksQ.error} onRetry={() => void homeworksQ.refetch()} />
            ) : !homeworksQ.data?.length ? (
              <EmptyState>배정된 Home Work가 없습니다.</EmptyState>
            ) : (
              homeworksQ.data.map((hw) => (
                <HomeworkStatusRow key={hw.id} hw={hw} members={membersQ.data ?? []} />
              ))
            )}
            <p className="mt-2.5 text-[10.5px] leading-relaxed text-muted">
              완료율 = 배정 인원 중 완료 체크를 남긴 회원 비율입니다(분모는 배정 인원 고정 —
              제출을 멈춘 회원은 분모에 그대로 남습니다). 완료율 하락은 이탈 신호이기도 합니다 —
              회원 상세와 대시보드에 함께 집계됩니다.
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

function ItemsEditor({
  items,
  onUpdate,
  onAdd,
  onRemove,
}: {
  items: HomeworkItem[];
  onUpdate: (i: number, patch: Partial<HomeworkItem>) => void;
  onAdd: () => void;
  onRemove: (i: number) => void;
}) {
  return (
    <div className="space-y-1.5">
      {items.map((it, i) => (
        // 폰 폭(375px)에서 5열 고정 grid는 각 칸이 50px 아래로 찌그러져 placeholder조차 안 보였다
        // — 이 저장소는 "폰 브라우저에서 Home Work까지 가능합니다"라고 약속하고 있다(README).
        // 좁을 땐 2열로 접어(항목명·메모는 전폭, 세트/횟수는 반반) 각 칸이 실제 입력 가능한
        // 폭을 갖게 하고, sm(640px) 이상에서만 종전의 한 줄 5열로 편다. 행 경계가 사라지면
        // 어느 줄이 한 항목인지 알 수 없으므로 좁을 때만 테두리를 준다.
        <div
          key={i}
          className="grid grid-cols-2 items-center gap-1.5 rounded-[10px] border border-line/60 p-1.5 sm:grid-cols-[1fr_70px_90px_1fr_28px] sm:border-0 sm:p-0"
        >
          <Input
            value={it.name}
            onChange={(e) => onUpdate(i, { name: e.target.value })}
            placeholder="항목명(예: 밴드 외회전)"
            className="col-span-2 sm:col-span-1"
          />
          <Input
            type="number"
            value={it.sets ?? ""}
            onChange={(e) => onUpdate(i, { sets: e.target.value ? Number(e.target.value) : null })}
            placeholder="세트"
          />
          <Input value={it.reps} onChange={(e) => onUpdate(i, { reps: e.target.value })} placeholder="15 / 30분" />
          <Input
            value={it.note}
            onChange={(e) => onUpdate(i, { note: e.target.value })}
            placeholder="메모"
            className="col-span-2 sm:col-span-1"
          />
          <button
            onClick={() => onRemove(i)}
            className="col-span-2 flex h-8 w-7 items-center justify-center justify-self-end rounded-lg text-muted hover:bg-panel-2 hover:text-danger sm:col-span-1"
            aria-label="항목 삭제"
          >
            <Trash2 className="h-3.5 w-3.5" />
          </button>
        </div>
      ))}
      <Button size="sm" variant="outline" onClick={onAdd}>
        <Plus className="h-3.5 w-3.5" /> 항목 추가
      </Button>
    </div>
  );
}

function HomeworkStatusRow({ hw, members }: { hw: Homework; members: MemberWithPasses[] }) {
  // v1.4 UX: 행 클릭 → 회원별 완료 현황 펼침(HwCheck.member_id 기반 — 누가 하고 있는지 보인다).
  const [expanded, setExpanded] = useState(false);
  const checksQ = useHwChecks(hw.id);

  // ── 완료율의 분모는 "배정 인원"이다(format.ts ratioState 3상태 규약) ──────────────
  // 종전 분모는 **제출된 체크의 칸 수**였다: 과제를 한 번도 안 연 회원은 분자에도 분모에도
  // 없어서 10명 중 1명이 3항목을 체크하면 3/3 = 100% 초록이 떴고, 이탈해서 제출을 멈출수록
  // 분모가 줄어 완료율이 **올라갔다** — 바로 아래 "완료율 하락은 이탈 신호" 카피가 가리키는
  // 지표가 구조적으로 하락할 수 없었다. 분모를 서버가 확정한 배정 인원으로 고정한다.
  //
  // ?? [] 는 방어가 아니라 **계약 준수**다: 서버의 []string·[]bool 필드에 omitempty가 없어
  // 비어 있으면 [] 가 아니라 null로 온다(Go의 nil 슬라이스 마샬링). ResolveTargets는 제외자가
  // 없으면 excluded를 nil로 돌려주므로 정상 배정에서도 excluded: null이 실려 온다 —
  // .includes()를 바로 부르면 그 행에서 화면이 죽는다.
  const allTargetIds = hw.target_member_ids ?? [];
  const excludedIds = hw.excluded ?? [];
  const targetIds = allTargetIds.filter((id) => !excludedIds.includes(id));
  const targetCount = targetIds.length;
  // 분자 = 완료 체크를 1개 이상 남긴 **배정 회원 수**. 배정 밖 회원의 체크(스코프 잔재)는 세지
  // 않는다 — 분자가 분모를 넘는 순간 지표가 아니라 버그가 된다.
  const engaged = checksQ.data
    ? new Set(
        checksQ.data
          .filter((c) => targetIds.includes(c.member_id) && (c.done ?? []).some(Boolean))
          .map((c) => c.member_id),
      ).size
    : undefined;
  // 분모 0(배정 인원 0) = "집계 대상 0건", 조회 실패·로딩 = "미상". 둘 다 0%로 단정하지 않는다.
  const rate = ratioState(
    engaged !== undefined && targetCount > 0 ? engaged / targetCount : null,
    targetCount,
  );
  // 제출된 체크의 항목 단위 집계 — 펼침 영역의 보조 지표로만 쓴다(완료율의 분모가 아니다).
  const submittedSlots = checksQ.data?.reduce((sum, c) => sum + (c.done ?? []).length, 0) ?? 0;
  const submittedDone =
    checksQ.data?.reduce((sum, c) => sum + (c.done ?? []).filter(Boolean).length, 0) ?? 0;
  // 미제출 인원은 **배정 회원 기준**으로만 센다 — perMember에는 배정 밖 회원의 체크도 섞인다.
  const submittedTargets = checksQ.data
    ? new Set(
        checksQ.data.filter((c) => targetIds.includes(c.member_id)).map((c) => c.member_id),
      ).size
    : 0;

  // 회원별 집계: done 배열의 true 개수(완료 항목 수) / 전체 칸 수 — 제출된 체크 기준.
  const perMember = useMemo(() => {
    const map = new Map<string, { done: number; total: number }>();
    for (const c of checksQ.data ?? []) {
      const cur = map.get(c.member_id) ?? { done: 0, total: 0 };
      const done = c.done ?? [];
      cur.done += done.filter(Boolean).length;
      cur.total += done.length;
      map.set(c.member_id, cur);
    }
    return [...map.entries()].sort((a, b) => b[1].done - a[1].done);
  }, [checksQ.data]);

  const label =
    hw.scope === "individual"
      ? (members.find((m) => m.id === allTargetIds[0])?.name ?? "개인 배정")
      : hw.scope === "my_members"
        ? `담당 전체 (${targetCount}명)`
        : `센터 공지 (${targetCount}명)`;

  return (
    <div className="my-2">
      <button
        onClick={() => setExpanded((e) => !e)}
        className="w-full text-left"
        aria-expanded={expanded}
      >
        <div className="mb-0.5 flex items-center justify-between text-[11.5px]">
          <span className="flex min-w-0 items-center gap-1 truncate">
            {expanded ? (
              <ChevronDown className="h-3 w-3 shrink-0 text-muted" />
            ) : (
              <ChevronRight className="h-3 w-3 shrink-0 text-muted" />
            )}
            {label}{" "}
            <Badge tone={hw.scope === "center_notice" ? "brand" : "muted"}>
              {(hw.items ?? []).length}항목
            </Badge>
          </span>
          <span className="font-bold">
            {rate.kind === "value" ? `${engaged}/${targetCount}명 · ${rate.text}` : rate.text}
          </span>
        </div>
        {rate.kind === "value" ? (
          <ProgressBar
            value={(rate.rate ?? 0) * 100}
            barClassName={
              rate.rate === 1 ? "bg-ok" : (rate.rate ?? 0) < 0.4 ? "bg-warn" : undefined
            }
          />
        ) : (
          // 빈 게이지는 "0%"로 읽힌다 — 모르는 자리엔 게이지 대신 이유를 쓴다(계약 v2.1).
          <p className="text-[10.5px] text-muted">
            {checksQ.isLoading
              ? "체크 현황 불러오는 중…"
              : checksQ.isError
                ? "체크 현황을 불러오지 못해 완료율을 낼 수 없어요."
                : rate.note}
          </p>
        )}
      </button>
      {expanded && (
        <div className="mt-1.5 rounded-[10px] bg-panel-2 px-3 py-2 text-[11px]">
          {checksQ.isLoading ? (
            <span className="text-muted">불러오는 중…</span>
          ) : checksQ.isError ? (
            <span className="text-danger">체크 현황을 불러오지 못했어요.</span>
          ) : !perMember.length ? (
            <span className="text-muted">
              배정 {targetCount}명 중 아직 제출된 체크가 없어요.
            </span>
          ) : (
            <div className="space-y-1">
              <div className="pb-1 text-[10.5px] text-muted">
                배정 {targetCount}명 · 미제출 {Math.max(0, targetCount - submittedTargets)}명 ·
                제출된 체크 항목 {submittedDone}/{submittedSlots}
              </div>
              {perMember.map(([memberId, agg]) => (
                <div key={memberId} className="flex items-center justify-between gap-2">
                  <span className="truncate">
                    {/* 타 담당 회원은 목록 스코프 밖일 수 있다 — raw id는 노출하지 않는다. */}
                    {members.find((m) => m.id === memberId)?.name ?? "(다른 담당 회원)"}
                  </span>
                  <span className={agg.done > 0 ? "font-bold text-ok" : "text-muted"}>
                    완료 {agg.done}/{agg.total}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
