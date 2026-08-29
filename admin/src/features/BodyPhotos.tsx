// 체형 분석 — 목업 s-body 1:1(관리자 시점). 실제 촬영은 회원 앱 카메라(그리드·수평계) 몫이라
// 어드민은 회원 선택 + 저장된 사진 타임라인 열람 + 인바디 기록 입력/조회에 집중한다.
import { useMemo, useState } from "react";
import { Camera, Plus, ShieldAlert, Trash2 } from "lucide-react";
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
  Select,
  Spinner,
  TD,
  TH,
  THead,
  TR,
  Table,
} from "@/components/ui";
import { ApiError } from "@/lib/api";
import { useCreateInbody, useDeleteInbody, useBodyPhotos, useInbodyList, useMembers } from "@/lib/queries";
import { formatMonthDay, todayStr } from "@/lib/format";
import {
  DEFAULT_BODY_POSES,
  poseLabel,
  type BodyPhoto,
  type BodyPose,
  type Inbody,
  type PoseSpec,
} from "@/lib/types";
import { BodyPhotoLightbox } from "./BodyPhotoLightbox";
import { PoseSequenceEditor } from "./PoseSequenceEditor";



export function BodyPhotos() {
  const membersQ = useMembers();
  const [memberId, setMemberId] = useState("");
  const [pose, setPose] = useState<BodyPose>("");
  const [lightbox, setLightbox] = useState<BodyPhoto | null>(null);

  const member = membersQ.data?.find((m) => m.id === memberId);
  // 서버 규약과 **동형**으로 판정한다(domain.Consent.SensitiveConsentValid): 동의가 있고
  // 철회되지 않았을 때만 유효. 종전엔 revoked_at을 보지 않아, 철회한 회원에서 잠금 UI가 안 뜨고
  // 서버 403만 돌아왔다.
  const consentValid = !!member?.consent.sensitive && !member.consent.revoked_at;
  // **조회 조건을 화면 게이트와 일치시킨다.** 종전엔 회원을 고르는 순간 조회가 먼저 나가서,
  // 잠금 화면을 그리기도 전에 403이 서버 로그에 쌓였다 — 실제 권한 사고와 구분되지 않는다.
  const photosQ = useBodyPhotos(consentValid ? memberId : null);
  const inbodyQ = useInbodyList(consentValid ? memberId : null);
  /// 이 회원의 시퀀스(서버가 구체화해 준다) — 없으면 기본 4종.
  const sequence: PoseSpec[] = member?.body_poses?.length ? member.body_poses : DEFAULT_BODY_POSES;

  /// 칩 목록 = 시퀀스 ∪ **사진에 실재하는 key**.
  /// 합집합이 아니면 대표가 포즈를 뺀 순간 그 사진들이 어드민에서 통째로 사라진다
  /// (체형사진은 삭제 API가 없어 안 보이면 확인할 길이 없다).
  const poseKeys = useMemo(() => {
    const keys = sequence.map((p) => p.key);
    const leftovers = [...new Set((photosQ.data ?? []).map((p) => p.pose))]
      .filter((k) => !keys.includes(k))
      .sort();
    return [...keys, ...leftovers];
  }, [sequence, photosQ.data]);

  /// 선택 포즈가 목록 밖이면(회원 전환·시퀀스 변경) 첫 포즈로 접는다.
  const activePose = poseKeys.includes(pose) ? pose : (poseKeys[0] ?? "");

  const posePhotos = useMemo(
    () => (photosQ.data ?? []).filter((p) => p.pose === activePose).sort((a, b) => a.date.localeCompare(b.date)),
    [photosQ.data, activePose],
  );

  return (
    <div>
      <h2 className="text-[16.5px] font-bold">체형 분석</h2>
      <p className="mt-0.5 mb-3.5 text-xs text-muted">
        그리드 카메라로 같은 조건 촬영 → 날짜·포즈별 타임라인 비교. 촬영은 회원 앱에서 진행되며,
        여기서는 결과를 열람하고 인바디를 기록합니다.
      </p>

      <Card>
        <CardContent className="pt-3.5">
          <Label>회원 선택</Label>
          {/* 조회 실패를 빈 셀렉트("회원 0명")로 위장하지 않는다 — Members.tsx ErrorState 패턴. */}
          {membersQ.isError ? (
            <ErrorState error={membersQ.error} />
          ) : (
            <Select
              value={memberId}
              onChange={(e) => setMemberId(e.target.value)}
              className="max-w-xs"
              disabled={membersQ.isLoading}
            >
              <option value="">
                {membersQ.isLoading ? "회원 목록 불러오는 중…" : "회원을 선택하세요"}
              </option>
              {(membersQ.data ?? []).map((m) => (
                <option key={m.id} value={m.id}>
                  {m.name}
                </option>
              ))}
            </Select>
          )}
        </CardContent>
      </Card>

      {!memberId ? (
        <div className="mt-3">
          <EmptyState>회원을 선택하면 타임라인과 인바디 기록을 볼 수 있습니다.</EmptyState>
        </div>
      ) : !member ? (
        <div className="mt-3">
          {/* 목록 로딩 중이면 스피너, 로딩이 끝났는데도 없으면(삭제·스테일 선택) 무한 스피너 대신 안내. */}
          {membersQ.isLoading ? (
            <Spinner />
          ) : (
            <EmptyState>선택한 회원을 찾을 수 없습니다 — 목록에서 다시 선택해주세요.</EmptyState>
          )}
        </div>
      ) : !consentValid ? (
        <Card className="mt-3 border-danger/30 bg-danger/[0.06]">
          <CardContent className="flex items-start gap-2 pt-3.5 text-[12.5px] text-danger">
            <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" />
            <span>
              {member.consent.sensitive && member.consent.revoked_at
                ? "민감정보(체형사진 등) 처리 동의가 철회돼 촬영·조회가 잠겨 있습니다. 회원 관리에서 동의 상태를 먼저 확인하세요."
                : "민감정보(체형사진 등) 처리 동의가 없어 촬영·조회가 잠겨 있습니다. 회원 관리에서 동의 상태를 먼저 확인하세요."}
            </span>
          </CardContent>
        </Card>
      ) : (
        <>
        {lightbox && (
          <BodyPhotoLightbox
            photo={lightbox}
            label={poseLabel(lightbox.pose, sequence)}
            onClose={() => setLightbox(null)}
          />
        )}
        <div className="mt-3 grid gap-3 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle>
                {member.name} · 타임라인
                <span className="ml-2">
                  {poseKeys.map((k) => (
                    <Chip key={k} active={activePose === k} onClick={() => setPose(k)}>
                      {poseLabel(k, sequence)}
                    </Chip>
                  ))}
                </span>
              </CardTitle>
            </CardHeader>
            <CardContent>
              {photosQ.isLoading ? (
                <Spinner />
              ) : photosQ.isError ? (
                <ErrorState error={photosQ.error} />
              ) : !posePhotos.length ? (
                <EmptyState>이 포즈로 촬영된 사진이 없습니다.</EmptyState>
              ) : (
                <div className="flex gap-2 overflow-x-auto pb-1">
                  {posePhotos.map((p) => (
                    <button
                      key={p.id}
                      type="button"
                      onClick={() => setLightbox(p)}
                      title="클릭하면 원본을 불러옵니다"
                      className="flex h-[150px] w-[120px] shrink-0 flex-col items-center justify-center gap-1.5 rounded-[10px] border border-line bg-panel-2 text-[11px] text-muted hover:border-accent"
                    >
                      <Camera className="h-5 w-5" />
                      {formatMonthDay(p.date)}
                      {p.blurred && <Badge tone="warn">배경 블러됨</Badge>}
                    </button>
                  ))}
                </div>
              )}
              <p className="mt-2.5 text-[10.5px] text-muted">
                {/* 서버 checkBodyPhotoAccess와 같은 말 — 대표(owner)도 동의가 유효하면 본다.
                    "담당 트레이너만"은 열람 범위를 좁혀 말한 거짓이었다. */}
                사진을 클릭하면 원본을 불러옵니다. 열람은 회원 본인 · 담당 코치 · 대표만
                가능하고, 회원이 민감정보 동의를 철회하면 즉시 막힙니다.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>인바디</CardTitle>
            </CardHeader>
            <CardContent>
              {/* key=회원 — 회원을 바꾸면 폼을 통째로 리셋한다. 남아 있던 앞 회원의 입력값이
                  다음 회원 이름으로 저장되는 사고를 원천 차단(이제 6칸이 값을 유지하므로 필요). */}
              <InbodyForm key={memberId} memberId={memberId} />
              <div className="mt-3">
                {inbodyQ.isLoading ? (
                  <Spinner />
                ) : inbodyQ.isError ? (
                  <ErrorState error={inbodyQ.error} />
                ) : !inbodyQ.data?.length ? (
                  <EmptyState>인바디 기록이 없습니다.</EmptyState>
                ) : (
                  <InbodyList records={inbodyQ.data} />
                )}
              </div>
            </CardContent>
          </Card>

          {/* 회원별 포즈 시퀀스 — 앱 촬영 화면이 이 순서를 그대로 쓴다(계약 v2.10). */}
          <PoseSequenceEditor key={memberId} member={member} />
        </div>
        </>
      )}
    </div>
  );
}

// ── 인바디 사전 검증(서버 v2.9 미러) ────────────────────────────────────
// **출처: backend/internal/domain/measurement.go의 inbodyRanges — 서버가 진실이다.** 서버 표가
// 바뀌면 여기도 함께 바꿔야 한다(어긋나도 최종 판정은 서버 400이 하고, 그 문구를 그대로 띄운다).
// 서버는 6지표 전부에 "오입력 판별선" 범위를 걸고 0을 모두 거부한다 — JSON에서 미입력 숫자는
// 0.0이 되므로 "선택 입력"은 곧 "0kg 체중"이다. 여기서 같은 범위로 버튼을 잠그는 이유:
// 사전 검증 없이 보내면 사용자는 400을 받고서야 어느 칸이 문제인지 안다(서버만 아는 규칙을
// 폼이 모르면 저장이 전량 실패한다 — 홈워크 unknown-field 사태와 같은 클래스).
interface InbodyFieldSpec {
  key: "weight" | "smm" | "bfm" | "pbf" | "vfl" | "bmr"; // InbodyCreateRequest의 숫자 키와 동일
  label: string; // 서버 에러 문구의 지표명과 같은 문자열 — 400이 와도 어느 칸인지 바로 짚인다
  unit: string;
  min: number;
  max: number;
  overMaxHint?: string; // 상한 초과 시 덧붙임(서버와 같은 문구 — 무엇을 잘못 봤는지)
  helper?: string; // 에러가 없어도 상시 노출하는 안내
}
type InbodyFieldKey = InbodyFieldSpec["key"];

const INBODY_FIELDS: readonly InbodyFieldSpec[] = [
  { key: "weight", label: "체중", unit: "kg", min: 20, max: 300 },
  { key: "smm", label: "골격근량(SMM)", unit: "kg", min: 5, max: 120 },
  {
    key: "bfm",
    label: "체지방량(BFM)",
    unit: "kg",
    min: 1,
    max: 200,
    overMaxHint: "체지방량이에요 — 제지방량(FFM) 칸이 아니에요",
  },
  { key: "pbf", label: "체지방률(PBF)", unit: "%", min: 1, max: 70 },
  {
    key: "vfl",
    label: "내장지방레벨(VFL)",
    unit: "",
    min: 1,
    max: 30,
    overMaxHint: "내장지방'레벨'이에요 — 단면적(cm²)이 아니에요",
    // 상시 노출: 인바디 770 등의 결과지에는 내장지방이 단면적(cm², 100 근처)으로도 찍혀 그 값을
    // 그대로 옮겨 적는 실수가 실제로 난다. 사전 검증이 요청을 막으면 서버의 같은 취지 힌트가
    // 사용자에게 도달할 기회가 없으므로, 에러 이전에 여기서 먼저 말한다.
    helper: "'레벨'(1~30)이에요 — 결과지의 단면적(cm²)이 아니에요",
  },
  { key: "bmr", label: "기초대사량(BMR)", unit: "kcal", min: 500, max: 5000 },
];

const EMPTY_INBODY_FIELDS: Record<InbodyFieldKey, string> = {
  weight: "",
  smm: "",
  bfm: "",
  pbf: "",
  vfl: "",
  bmr: "",
};

// 빈 칸은 에러가 아니라 미완성이다 — 붉히지 않고 버튼만 잠근다(입력 전부터 6칸이 새빨간 폼은
// 사용자를 혼내는 폼이다). 값이 있으면 서버와 같은 범위·같은 힌트로 판정한다.
function inbodyFieldError(f: InbodyFieldSpec, raw: string): string | null {
  if (raw.trim() === "") return null;
  const v = Number(raw);
  if (!Number.isFinite(v)) return "숫자로 입력해주세요";
  if (v < f.min || v > f.max) {
    let msg = `${f.min}~${f.max}${f.unit} 사이로 입력해주세요`;
    if (v > f.max && f.overMaxHint) msg += ` — ${f.overMaxHint}`;
    return msg;
  }
  return null;
}

// 교차 검증 미러 — 서버 domain.Inbody.Validate()와 같은 순서·같은 문구. 체/제 오기(BFM 칸에
// 제지방량 FFM을 적음)는 개별 범위를 태연히 통과하고 여기서만 잡힌다(FFM은 보통 체중의 70~90%).
// 덧셈이 양쪽 다 IEEE754 배정밀도(Go float64 = JS number)라 서버와 판정이 갈리지 않는다.
function inbodyCrossError(weight: number, smm: number, bfm: number): string | null {
  if (smm >= weight)
    return `골격근량(${smm}kg)이 체중(${weight}kg)보다 클 수 없어요 — 두 값을 다시 확인해주세요`;
  if (bfm >= weight)
    return `체지방량(${bfm}kg)이 체중(${weight}kg)보다 클 수 없어요 — 제지방량(FFM)을 적으신 건 아닌지 확인해주세요`;
  if (smm + bfm > weight)
    return `골격근량(${smm}kg)+체지방량(${bfm}kg)이 체중(${weight}kg)을 넘어요 — 체지방량 칸에 제지방량(FFM)을 적으신 건 아닌지 확인해주세요`;
  return null;
}

function InbodyForm({ memberId }: { memberId: string }) {
  const [date, setDate] = useState(todayStr());
  // 6칸 전부 **빈 입력**으로 시작한다(0 채움 금지). 종전엔 useState(0)이라 ① 안 지운 0이 그대로
  // 저장되고 ② 서버 v2.9가 0을 전부 거부하므로 "체중만 채우면 저장" 게이트로는 100% 400이었다.
  const [fields, setFields] = useState(EMPTY_INBODY_FIELDS);
  const createInbody = useCreateInbody();

  const setField = (key: InbodyFieldKey) => (v: string) => setFields((f) => ({ ...f, [key]: v }));
  const num = (k: InbodyFieldKey) => Number(fields[k]);

  const errors = Object.fromEntries(
    INBODY_FIELDS.map((f) => [f.key, inbodyFieldError(f, fields[f.key])]),
  ) as Record<InbodyFieldKey, string | null>;
  const allFilled = INBODY_FIELDS.every((f) => fields[f.key].trim() !== "");
  const anyRangeError = INBODY_FIELDS.some((f) => errors[f.key] !== null);

  // 교차 검증은 세 값이 개별 범위를 통과한 뒤에만 본다 — 서버도 범위 검사가 먼저다(같은 순서).
  const crossReady = (["weight", "smm", "bfm"] as const).every(
    (k) => fields[k].trim() !== "" && errors[k] === null,
  );
  const crossError = crossReady ? inbodyCrossError(num("weight"), num("smm"), num("bfm")) : null;

  // 미래 측정일은 서버가 400(KST 기준 오늘). 어드민은 한국 데스크에서 쓰므로 로컬 todayStr()과
  // 같은 판이다. max는 피커의 미래 선택을 막고, 직접 타이핑은 아래 dateError가 받는다.
  const today = todayStr();
  const dateError = !date ? "측정일을 입력해주세요" : date > today ? "측정일은 미래일 수 없어요" : null;

  const canSubmit = allFilled && !anyRangeError && !crossError && !dateError;
  // 409(같은 날 중복)의 다음 행동은 이 화면 안에 있다 — 아래 목록에서 그 날짜 행을 지우고
  // 다시 저장(서버에 PUT이 없어 이것이 유일한 정정 동선). 입력값은 성공 전엔 지우지 않는다.
  const isDuplicate = createInbody.error instanceof ApiError && createInbody.error.status === 409;

  function submit() {
    if (!canSubmit) return;
    createInbody.mutate(
      {
        member_id: memberId,
        date,
        weight: num("weight"),
        smm: num("smm"),
        bfm: num("bfm"),
        pbf: num("pbf"),
        vfl: num("vfl"),
        bmr: num("bmr"),
      },
      { onSuccess: () => setFields(EMPTY_INBODY_FIELDS) },
    );
  }

  return (
    <div>
      <div className="grid grid-cols-3 gap-1.5 sm:grid-cols-4">
        <div className="col-span-3 sm:col-span-4">
          <Label>측정일</Label>
          <Input
            type="date"
            value={date}
            max={today}
            onChange={(e) => setDate(e.target.value)}
            className={dateError ? "border-danger" : undefined}
          />
          {dateError && <p className="mt-0.5 text-[10px] leading-snug text-danger">{dateError}</p>}
        </div>
        {INBODY_FIELDS.map((f) => (
          <NumField
            key={f.key}
            label={f.label}
            value={fields[f.key]}
            onChange={setField(f.key)}
            placeholder={`${f.min}~${f.max}${f.unit}`}
            error={errors[f.key]}
            helper={f.helper}
          />
        ))}
      </div>
      {crossError && <p className="mt-1.5 text-[11px] leading-snug text-danger">{crossError}</p>}
      {createInbody.isError && (
        <p className="mt-1.5 text-[11px] leading-snug text-danger">{createInbody.error.message}</p>
      )}
      {isDuplicate && (
        <p className="mt-0.5 text-[10.5px] leading-snug text-muted">
          아래 목록에서 그 날짜 행을 삭제한 뒤 다시 저장하면 돼요 — 입력한 값은 그대로 남아 있어요.
        </p>
      )}
      {!allFilled && (
        <p className="mt-1.5 text-[10.5px] text-muted">
          6개 지표를 모두 입력해야 저장할 수 있어요 — 빈 칸(0)은 서버가 거부해요.
        </p>
      )}
      <Button size="sm" className="mt-2" onClick={submit} disabled={createInbody.isPending || !canSubmit}>
        <Plus className="h-3.5 w-3.5" /> 기록 추가
      </Button>
    </div>
  );
}

function NumField({
  label,
  value,
  onChange,
  placeholder,
  error,
  helper,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  error: string | null;
  helper?: string;
}) {
  return (
    <div>
      <Label>{label}</Label>
      <Input
        type="number"
        step="0.1"
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        className={error ? "border-danger" : undefined}
      />
      {error ? (
        <p className="mt-0.5 text-[10px] leading-snug text-danger">{error}</p>
      ) : helper ? (
        <p className="mt-0.5 text-[10px] leading-snug text-muted">{helper}</p>
      ) : null}
    </div>
  );
}

function InbodyList({ records }: { records: Inbody[] }) {
  const sorted = [...records].sort((a, b) => b.date.localeCompare(a.date));
  const deleteInbody = useDeleteInbody();
  // 파괴적 액션 2단 확인 — Schedule.tsx 고정 스케줄 삭제와 같은 confirmId 규약. 같은 날 재입력이
  // 409로 막히고 서버에 PUT이 없으므로, 이 삭제가 **그날 오타를 고치는 유일한 동선**이다
  // (409 → 아래 목록에서 그 날짜 행 삭제 → 폼의 남은 값으로 재저장).
  const [confirmId, setConfirmId] = useState<string | null>(null);
  const target = sorted.find((r) => r.id === confirmId);

  function openConfirm(id: string) {
    setConfirmId(id);
    deleteInbody.reset(); // 앞 삭제의 에러 문구가 새 확인 위에 남지 않게
  }

  return (
    <>
      <Table>
        <THead>
          <TR>
            <TH>날짜</TH>
            <TH>체중</TH>
            <TH>SMM</TH>
            <TH>PBF</TH>
            <TH></TH>
          </TR>
        </THead>
        <tbody>
          {sorted.map((r, i) => {
            const prev = sorted[i + 1];
            return (
              <TR key={r.id} className={confirmId === r.id ? "bg-danger/[0.06]" : undefined}>
                <TD className="text-muted">
                  {r.date}
                  {/* v2.9 source — 회원 셀프 입력분 표시(지우기 전에 누가 넣었는지 보이게).
                      staff·""(v2.9 이전)는 배지 없음. */}
                  {r.source === "member_self" && (
                    <Badge tone="muted" className="ml-1">
                      회원 입력
                    </Badge>
                  )}
                </TD>
                <TD>{r.weight}kg</TD>
                <TD>
                  {r.smm}kg <Delta value={prev ? r.smm - prev.smm : undefined} goodWhenUp />
                </TD>
                <TD>
                  {r.pbf}% <Delta value={prev ? r.pbf - prev.pbf : undefined} goodWhenUp={false} />
                </TD>
                <TD>
                  {confirmId === r.id ? (
                    <span className="text-[10.5px] font-extrabold text-danger">확인 중 ↓</span>
                  ) : (
                    <Button size="sm" variant="outline" onClick={() => openConfirm(r.id)}>
                      <Trash2 className="h-3 w-3" /> 삭제
                    </Button>
                  )}
                </TD>
              </TR>
            );
          })}
        </tbody>
      </Table>

      {target && (
        <div className="mt-2 rounded-[10px] border border-danger/40 bg-danger/[0.08] p-3">
          <p className="text-[11.5px] leading-relaxed text-danger">
            <b>{target.date}</b> 인바디 기록(체중 {target.weight}kg · 골격근량 {target.smm}kg ·
            체지방률 {target.pbf}%)을 삭제합니다. 이 날짜 기록이 삭제돼요 — <b>되돌리는 기능이
            없어요.</b> 잘못 입력한 값이라면 지운 뒤 위 폼에서 같은 날짜로 다시 입력하면 돼요
            (기록이 있는 동안엔 같은 날 저장이 막혀 있어서, 지우는 게 정정의 유일한 방법이에요).
            {target.source === "member_self" &&
              " 이 기록은 회원이 앱에서 직접 입력했어요 — 지우면 회원 화면에서도 사라져요."}
          </p>
          <div className="mt-2 flex gap-2">
            <Button
              size="sm"
              variant="danger"
              disabled={deleteInbody.isPending}
              onClick={() =>
                deleteInbody.mutate(
                  { id: target.id, memberId: target.member_id },
                  { onSuccess: () => setConfirmId(null) },
                )
              }
            >
              {deleteInbody.isPending ? "삭제 중…" : "삭제 확정"}
            </Button>
            <Button
              size="sm"
              variant="ghost"
              disabled={deleteInbody.isPending}
              onClick={() => setConfirmId(null)}
            >
              돌아가기
            </Button>
          </div>
        </div>
      )}
      {deleteInbody.isError && (
        <p className="mt-1 text-[11px] text-danger">삭제 실패: {deleteInbody.error.message}</p>
      )}
    </>
  );
}

function Delta({ value, goodWhenUp }: { value: number | undefined; goodWhenUp: boolean }) {
  if (value === undefined || Math.abs(value) < 0.05) return null;
  const up = value > 0;
  const good = up === goodWhenUp;
  return (
    <span className={good ? "text-ok" : "text-danger"}>
      {up ? "▲" : "▼"}
      {Math.abs(value).toFixed(1)}
    </span>
  );
}
