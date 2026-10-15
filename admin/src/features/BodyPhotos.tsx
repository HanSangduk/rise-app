// 체형 분석 — 목업 s-body 1:1(관리자 시점). 실제 촬영은 회원 앱 카메라(그리드·수평계) 몫이라
// 어드민은 회원 선택 + 저장된 사진 타임라인 열람 + 인바디 기록 입력/조회에 집중한다.
//
// [P58 A2·B2 + v2.28] 삭제·복원·대표 점검 도구가 붙었고, 동의 철회 잠금의 **범위**가 서버 사실과 같아졌다:
//   · 잠기는 것  사진 **내용** 열람(라이트박스)·복원(checkBodyPhotoAccess) · 인바디 **입력**(CreateInbody — 동의 필수 400)
//   · 안 잠기는 것  사진 **존재 목록**(v2.28 — 잠긴 회원이면 서버가 403 대신 BodyPhotoMeta[]: 날짜·포즈만) ·
//                  사진 삭제(P56 B1 — 삭제는 철회 뒤에 **더** 필요한 동작) · 인바디 목록·삭제(스코프만) ·
//                  포즈 시퀀스 편집(PUT /members — 동의 무관) · 대표 점검 도구
// 종전엔 철회 시 오른쪽 컬럼 전체를 잠금 카드로 바꿔 인바디까지 사라졌고, 삭제 요청을 처리할 사진 목록도
// 없었다(403) — 서버가 허용하는 것을 클라이언트가 막는 자리(P56 클래스 6).
//
// 목록 조회 하나(include_deleted=true)가 세 화면을 먹인다: 타임라인(살아 있는 Full) · 잠긴 목록(살아 있는
// Meta) · 휴지통(deleted_at 있는 것 — 새로고침해도 서버가 준다). 응답 모양으로 잠금을 판정한다
// (types.ts isFullBodyPhoto) — 서버가 진실이고, 회원 캐시의 동의 상태는 목록이 비어 판별이 안 될 때의 보조다.
import { useMemo, useState } from "react";
import {
  Camera,
  Plus,
  RotateCcw,
  ShieldAlert,
  Trash2,
  TriangleAlert,
  Wrench,
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
  Select,
  Spinner,
  TD,
  TH,
  THead,
  TR,
  Table,
} from "@/components/ui";
import { ApiError, isMediaNotConfigured } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import {
  useBodyPhotos,
  useCreateInbody,
  useDeleteBodyPhoto,
  useDeleteInbody,
  useInbodyList,
  useMembers,
  usePurgeBodyPhotos,
  useReconcileBodyPhotos,
  useRestoreBodyPhoto,
} from "@/lib/queries";
import { formatMonthDay, todayStr } from "@/lib/format";
import {
  BODY_PHOTO_PURGE_AFTER_DAYS,
  DEFAULT_BODY_POSES,
  bodyPhotoPurgeDaysLeft,
  isFullBodyPhoto,
  poseLabel,
  type BodyPhoto,
  type BodyPhotoListItem,
  type BodyPose,
  type Inbody,
  type Member,
  type PoseSpec,
} from "@/lib/types";
import { BodyPhotoLightbox } from "./BodyPhotoLightbox";
import { PoseSequenceEditor } from "./PoseSequenceEditor";

export function BodyPhotos() {
  const { me } = useAuth();
  // 대표 전용 도구(정합 검사·기한 지난 사진 파기)는 서버도 owner만 허용한다 — 트레이너에겐
  // 카드 자체를 그리지 않는다(눌러보고 403을 받는 UI를 만들지 않는다).
  const isOwner = me?.role === "owner";
  const membersQ = useMembers();
  const [memberId, setMemberId] = useState("");
  const [pose, setPose] = useState<BodyPose>("");
  const [lightbox, setLightbox] = useState<BodyPhoto | null>(null);

  const member = membersQ.data?.find((m) => m.id === memberId);
  // 서버 규약과 **동형**으로 판정한다(domain.Consent.SensitiveConsentValid): 동의가 있고
  // 철회되지 않았을 때만 유효. 목록이 비어 응답 모양으로 판별할 수 없을 때의 보조 판정이고,
  // 잠금 문구(철회 vs 미동의)를 고르는 데 쓴다.
  const consentValid = !!member?.consent.sensitive && !member.consent.revoked_at;
  // 회원만 고르면 조회한다(v2.28). 종전엔 동의가 유효할 때만 불렀다 — 잠긴 회원은 서버가 403이라
  // 로그만 더럽혔기 때문인데, 이제 잠긴 회원에는 Meta[]가 200으로 오므로 조회를 막을 이유가 없다.
  const photosQ = useBodyPhotos(memberId || null);
  // 인바디 목록은 동의를 보지 않는다(서버 ListInbody = checkMemberScope뿐).
  const inbodyQ = useInbodyList(memberId || null);
  const items: BodyPhotoListItem[] = photosQ.data ?? [];
  // **응답 모양이 진실이다.** Meta(storage_path 없음)면 잠긴 회원. 한 응답에 두 모양이 섞이지 않는다.
  const locked = items.length ? !isFullBodyPhoto(items[0]) : !consentValid;
  const livePhotos = items.filter((p) => !p.deleted_at);
  const trashPhotos = items.filter((p) => !!p.deleted_at);
  // 타임라인은 원본을 열 수 있는 것(Full)만 — 잠긴 회원의 Meta는 아래 LockedPhotoList가 그린다.
  const liveFull = livePhotos.filter(isFullBodyPhoto);
  /// 이 회원의 시퀀스(서버가 구체화해 준다) — 없으면 기본 4종.
  const sequence: PoseSpec[] = member?.body_poses?.length ? member.body_poses : DEFAULT_BODY_POSES;

  /// 칩 목록 = 시퀀스 ∪ **사진에 실재하는 key**.
  /// 합집합이 아니면 대표가 포즈를 뺀 순간 그 사진들이 어드민에서 통째로 사라진다
  /// (삭제는 원본을 연 라이트박스에서만 되므로, 안 보이는 사진은 지울 수도 없다).
  const poseKeys = useMemo(() => {
    const keys = sequence.map((p) => p.key);
    const leftovers = [...new Set(liveFull.map((p) => p.pose))].filter((k) => !keys.includes(k)).sort();
    return [...keys, ...leftovers];
  }, [sequence, liveFull]);

  /// 선택 포즈가 목록 밖이면(회원 전환·시퀀스 변경) 첫 포즈로 접는다.
  const activePose = poseKeys.includes(pose) ? pose : (poseKeys[0] ?? "");

  const posePhotos = useMemo(
    () => liveFull.filter((p) => p.pose === activePose).sort((a, b) => a.date.localeCompare(b.date)),
    [liveFull, activePose],
  );

  return (
    <div>
      <h2 className="text-[16.5px] font-bold">체형 분석</h2>
      <p className="mt-0.5 mb-3.5 text-xs text-muted">
        그리드 카메라로 같은 조건 촬영 → 날짜·포즈별 타임라인 비교. 촬영은 회원 앱에서 진행되며,
        여기서는 결과를 열람하고 인바디를 기록합니다. 잘못 올라간 사진은 원본을 연 뒤 지울 수 있어요.
      </p>

      <Card>
        <CardContent className="pt-3.5">
          <Label>회원 선택</Label>
          {/* 조회 실패를 빈 셀렉트("회원 0명")로 위장하지 않는다 — Members.tsx ErrorState 패턴. */}
          {membersQ.isError ? (
            <ErrorState error={membersQ.error} onRetry={() => void membersQ.refetch()} />
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
      ) : (
        <>
        {lightbox && !locked && (
          <BodyPhotoLightbox
            photo={lightbox}
            label={poseLabel(lightbox.pose, sequence)}
            onClose={() => setLightbox(null)}
            footer={
              <PhotoDeleteControl
                photo={lightbox}
                label={poseLabel(lightbox.pose, sequence)}
                // 삭제 성공 = 목록 재조회까지 끝난 뒤(useDeleteBodyPhoto가 invalidate 프로미스를 돌려준다)
                // — 닫힌 라이트박스 뒤의 타임라인에 방금 지운 사진이 잠깐이라도 남지 않는다.
                onDeleted={() => setLightbox(null)}
              />
            }
          />
        )}
        <div className="mt-3 grid gap-3 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle>
                {member.name} · 타임라인
                {!locked && (
                  <span className="ml-2">
                    {poseKeys.map((k) => (
                      <Chip key={k} active={activePose === k} onClick={() => setPose(k)}>
                        {poseLabel(k, sequence)}
                      </Chip>
                    ))}
                  </span>
                )}
              </CardTitle>
            </CardHeader>
            <CardContent>
              {locked ? (
                /* 잠금은 **이 카드 안**에서만 — 인바디·포즈 편집·휴지통·대표 도구는 그대로 그린다.
                   잠긴 회원에게도 목록은 있다(v2.28 Meta) — 삭제 요청을 처리하는 자리. */
                <>
                  <ConsentLockNotice member={member} />
                  <LockedPhotoList
                    items={livePhotos}
                    sequence={sequence}
                    loading={photosQ.isLoading}
                    error={photosQ.isError ? photosQ.error : null}
                    onRetry={() => void photosQ.refetch()}
                  />
                </>
              ) : photosQ.isLoading ? (
                <Spinner />
              ) : photosQ.isError ? (
                <ErrorState error={photosQ.error} onRetry={() => void photosQ.refetch()} />
              ) : !posePhotos.length ? (
                <EmptyState>
                  {/* "없습니다"로 끝내면 대표는 이 화면에서 업로드 버튼을 찾아 헤맨다 —
                      촬영은 **회원 앱 카메라(그리드·수평계)에서만** 되고 어드민에는 올리는
                      경로가 없다(이 파일 헤더 규약). 원인과 다음 행동을 같이 적는다. */}
                  {poseLabel(activePose, sequence)} 포즈로 촬영된 사진이 아직 없어요.
                  <div className="mt-1 text-[11.5px]">
                    체형사진은 <b className="text-ink">회원 앱의 촬영 화면</b>에서만 찍을 수
                    있어요(어드민에서 올리는 방법은 없습니다) — 회원에게 앱에서 촬영을 부탁하거나,
                    아래 "포즈 시퀀스"에서 이 센터가 쓰는 포즈 순서를 먼저 정해주세요.
                  </div>
                </EmptyState>
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
              {!locked && (
                <p className="mt-2.5 text-[10.5px] text-muted">
                  {/* 서버 checkBodyPhotoAccess와 같은 말 — 대표(owner)도 동의가 유효하면 본다.
                      "담당 트레이너만"은 열람 범위를 좁혀 말한 거짓이었다. */}
                  사진을 클릭하면 원본을 불러옵니다. 열람은 회원 본인 · 담당 코치 · 대표만
                  가능하고, 회원이 민감정보 동의를 철회하면 즉시 막힙니다. 삭제는 원본 창 아래
                  버튼으로 — 지운 뒤 {BODY_PHOTO_PURGE_AFTER_DAYS}일 안에 복원할 수 있어요.
                </p>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>인바디</CardTitle>
            </CardHeader>
            <CardContent>
              {consentValid ? (
                /* key=회원 — 회원을 바꾸면 폼을 통째로 리셋한다. 남아 있던 앞 회원의 입력값이
                   다음 회원 이름으로 저장되는 사고를 원천 차단(이제 6칸이 값을 유지하므로 필요). */
                <InbodyForm key={memberId} memberId={memberId} />
              ) : (
                /* 서버 CreateInbody가 동의를 요구한다(400 "동의(sensitive)가 없거나 철회되어 저장할
                   수 없음") — 폼을 그려 놓고 저장에서 400을 받게 하지 않는다. 목록·삭제는 열려 있다. */
                <p className="rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2.5 text-[11px] leading-[1.8] text-warn">
                  <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />
                  민감정보 동의가 없거나 철회돼 <b>새 인바디 기록은 저장할 수 없어요</b>(서버가
                  거부합니다). 이미 있는 기록은 아래에서 그대로 보고 지울 수 있어요.
                </p>
              )}
              <div className="mt-3">
                {inbodyQ.isLoading ? (
                  <Spinner />
                ) : inbodyQ.isError ? (
                  <ErrorState error={inbodyQ.error} onRetry={() => void inbodyQ.refetch()} />
                ) : !inbodyQ.data?.length ? (
                  <EmptyState>
                    {/* 다음 행동이 동의 상태에 따라 다르다 — 폼이 없는 회원에게 "위 6칸을
                        채우세요"라고 하면 존재하지 않는 칸을 찾게 된다. */}
                    {consentValid
                      ? '인바디 기록이 아직 없어요 — 위 6칸을 채우고 "기록 추가"를 누르면 첫 기록이 남습니다.'
                      : "인바디 기록이 아직 없어요 — 민감정보 동의가 없거나 철회돼 새 기록도 저장할 수 없어요(회원이 앱에서 다시 동의하면 열립니다)."}
                  </EmptyState>
                ) : (
                  <InbodyList records={inbodyQ.data} />
                )}
              </div>
            </CardContent>
          </Card>

          {trashPhotos.length > 0 && (
            <TrashCard photos={trashPhotos} sequence={sequence} locked={locked} />
          )}

          {/* 회원별 포즈 시퀀스 — 앱 촬영 화면이 이 순서를 그대로 쓴다(계약 v2.10). 동의와 무관한
              회원 설정(PUT /members)이라 철회 중에도 편집된다 — 재동의 뒤 첫 촬영부터 적용된다. */}
          <PoseSequenceEditor key={memberId} member={member} />

          {isOwner && <OwnerPhotoTools memberId={memberId} memberName={member.name} />}
        </div>
        </>
      )}
    </div>
  );
}

// 동의 잠금 안내 — 타임라인 카드 안에서만 그린다(P58 B2). 무엇이 잠기고 무엇이 안 잠기는지를
// 서버 사실 그대로 적는다: 내용 열람·복원·인바디 입력은 잠기고, 존재 목록·삭제·인바디 목록·삭제는 아니다.
function ConsentLockNotice({ member }: { member: Member }) {
  return (
    <div className="flex items-start gap-2 rounded-[10px] border border-danger/30 bg-danger/[0.06] px-3 py-3 text-[12.5px] text-danger">
      <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" />
      {/* **철회는 센터가 풀 수 없다.** 종전 문구는 두 경우 모두 "회원 관리에서 동의 상태를 먼저
          확인하세요"라며 대표를 회원 관리로 보냈는데, 그 화면은 초록 체크(동의됨)를 보여주고 수정
          폼의 체크박스도 이미 켜져 있으며 저장해도 철회 기록은 그대로 남는다 — 시킨 대로 갔다가
          아무것도 못 바꾸고 같은 잠금으로 돌아오는 닫힌 고리였다. 풀 수 있는 사람은 회원 본인뿐
          이라는 사실을 여기서 말한다. 판정을 sensitive가 아니라 **revoked_at 하나로** 가르는 이유:
          철회하면서 동의 플래그까지 꺼진 응답(sensitive=false + revoked_at 있음)도 같은 고리에
          빠지는데, 종전 조건(sensitive && revoked_at)은 그 경우를 "동의 없음"으로 보내 "체크하면
          열린다"는 거짓 안내를 했다. */}
      {member.consent.revoked_at ? (
        <span className="leading-[1.8]">
          회원이 민감정보(체형사진 등) 처리 동의를 철회해{" "}
          {member.consent.revoked_at.slice(0, 10)}부터 촬영·사진 열람·복원이 잠겨 있어요.{" "}
          <b>회원이 앱 마이 탭의 "민감정보(인바디·체형사진) 동의"에서 다시 동의하면 바로 열려요 — 센터에서는 풀 수 없어요.</b>{" "}
          이미 찍어 둔 사진은 지워지지 않고 그대로 보관돼요.
          <br />
          <b>사진 열람은 잠겼지만 삭제 요청은 처리할 수 있어요</b> — 아래 목록(날짜·포즈만 보여요)에서
          골라 지우세요. 인바디는 이 잠금과 무관해요 — 옆 카드에서 기록을 그대로 보고 지울 수 있고,
          새 기록 입력만 막혀요.
        </span>
      ) : (
        <span className="leading-[1.8]">
          민감정보(체형사진 등) 처리 동의를 아직 받지 않아 촬영과 사진 열람이 잠겨 있어요.
          회원에게 동의를 받으셨다면 <b>회원 관리 → 수정</b>에서 동의 항목을 체크해주세요. 이미 올라온
          사진이 있으면 아래 목록(날짜·포즈만)에서 지울 수 있고, 인바디 기록은 옆 카드에서 그대로
          볼 수 있어요 — 새 기록 입력만 동의 뒤에 열려요.
        </span>
      )}
    </div>
  );
}

// ── 잠긴 회원의 사진 목록(v2.28 BodyPhotoMeta) — 삭제 요청을 처리하는 자리 ─────────────
//
// 사진은 열리지 않는다(storage_path가 없고, 있어도 Storage 규칙이 막는다). 보이는 것은 **어느 날
// 어느 포즈의 사진이 있는가**뿐이다 — 삭제 요청을 받은 스태프가 대상을 고르는 데 필요한 최소.
// 이 정보가 새 노출인가: 아니다. 이 목록을 볼 수 있는 사람은 스코프 안의 스태프(담당 코치·대표)뿐이고
// (스코프 밖은 여전히 403), 그들은 그 사진을 찍은 당사자라 존재 사실은 이미 안다. 철회가 거두는 것은
// 내용을 계속 **보는** 처리이고, 삭제는 정보주체의 요청을 이행하는 처리라 동의와 별개로 정당하다.
function LockedPhotoList({
  items,
  sequence,
  loading,
  error,
  onRetry,
}: {
  items: BodyPhotoListItem[];
  sequence: PoseSpec[];
  loading: boolean;
  error: unknown;
  onRetry: () => void;
}) {
  // 2단 확인 — InbodyList의 confirmId 규약. 행 옆 [삭제] → 목록 아래 확인 패널.
  const [confirmId, setConfirmId] = useState<string | null>(null);
  const sorted = useMemo(() => [...items].sort((a, b) => b.date.localeCompare(a.date)), [items]);
  const target = sorted.find((p) => p.id === confirmId);

  return (
    <div className="mt-3">
      <div className="mb-1 text-[11.5px] font-extrabold">사진 목록 — 날짜·포즈만 (열람 불가)</div>
      {loading ? (
        <Spinner />
      ) : error ? (
        <ErrorState error={error} onRetry={onRetry} />
      ) : !sorted.length ? (
        <EmptyState>남아 있는 사진이 없습니다.</EmptyState>
      ) : (
        <ul className="space-y-1.5">
          {sorted.map((p) => (
            <li
              key={p.id}
              className={`flex flex-wrap items-center justify-between gap-2 rounded-[10px] px-3 py-2 text-[12px] ${
                confirmId === p.id ? "bg-danger/[0.06]" : "bg-panel-2"
              }`}
            >
              <span>
                <b>{poseLabel(p.pose, sequence)}</b> · {formatMonthDay(p.date)}
                <span className="ml-2 text-[10.5px] text-muted">열람 잠김</span>
              </span>
              {confirmId === p.id ? (
                <span className="text-[10.5px] font-extrabold text-danger">확인 중 ↓</span>
              ) : (
                <Button size="sm" variant="outline" className="text-danger" onClick={() => setConfirmId(p.id)}>
                  <Trash2 className="h-3 w-3" /> 삭제
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}
      {target && (
        <div className="mt-2">
          <PhotoDeleteConfirm
            photo={target}
            label={poseLabel(target.pose, sequence)}
            locked
            onCancel={() => setConfirmId(null)}
            onDeleted={() => setConfirmId(null)}
          />
        </div>
      )}
      <p className="mt-2 text-[10.5px] leading-[1.7] text-muted">
        이 목록에서는 사진이 열리지 않아요 — 어느 날 어느 포즈의 사진이 있는지만 보이고, 회원이 삭제를
        요청했을 때 대상을 고르는 용도예요. 여기서 지우면 {BODY_PHOTO_PURGE_AFTER_DAYS}일 유예 뒤 파기되고,
        <b className="text-ink"> 즉시 파기가 필요하면 회원이 앱 마이 탭에서 직접 지우는 것이 확실해요</b>
        (본인 삭제는 유예 없이 바로 파기돼요).
      </p>
    </div>
  );
}

// ── 체형사진 삭제(v2.14, P58 A2) ─────────────────────────────────────────
//
// 확인 패널 하나를 두 자리가 나눠 쓴다 — 라이트박스 footer(원본이 보이는 자리)와 잠긴 회원의 Meta 목록.
// 2단 인라인 확인 — 이 파일의 InbodyList·CheckinQr와 같은 집안 관례다. 가입 승인·거절처럼 별도
// 모달을 세우지 않는 이유: 그 둘은 되돌릴 수 없는 동사라 창 하나를 더 두는 값어치가 있었지만,
// 스태프의 사진 삭제는 소프트 삭제라 30일 안에 되돌릴 수 있다. 되돌릴 수 있는 동사에 같은 무게를
// 얹으면 대표는 두 확인을 똑같이 습관으로 눌러 넘기고, 정작 무거운 쪽의 확인이 무의미해진다
// (RejectJoinModal 주석의 같은 논거).
function PhotoDeleteConfirm({
  photo,
  label,
  locked,
  onCancel,
  onDeleted,
}: {
  photo: BodyPhotoListItem;
  label: string;
  locked: boolean;
  onCancel: () => void;
  onDeleted: () => void;
}) {
  const del = useDeleteBodyPhoto();
  return (
    <div className="rounded-[10px] border border-danger/40 bg-danger/[0.08] p-3">
      <p className="text-[11.5px] leading-relaxed text-danger">
        <b>
          {label} · {formatMonthDay(photo.date)}
        </b>{" "}
        사진을 삭제합니다. 회원 앱{locked ? "" : "과 이 타임라인"}에서 바로 사라지고,{" "}
        {locked ? (
          <>
            {BODY_PHOTO_PURGE_AFTER_DAYS}일 유예 뒤 파일까지 완전히 파기돼요. 유예 중 복원은{" "}
            <b>회원이 다시 동의한 뒤에만</b> 할 수 있어요(복원은 열람과 같은 문을 탑니다).
          </>
        ) : (
          <>
            <b>{BODY_PHOTO_PURGE_AFTER_DAYS}일 안에는 아래 "최근 삭제"에서 복원할 수 있어요.</b>{" "}
            {BODY_PHOTO_PURGE_AFTER_DAYS}일이 지나면 파일까지 완전히 파기돼요 — 그날의 몸은 다시 못
            찍으니 사진을 한 번 더 보고 진행하세요.
          </>
        )}
      </p>
      {del.isError && <p className="mt-1.5 text-[11px] text-danger">삭제 실패: {del.error.message}</p>}
      <div className="mt-2 flex gap-2">
        <Button
          size="sm"
          variant="danger"
          disabled={del.isPending}
          onClick={() =>
            del.mutate(
              {
                id: photo.id,
                memberId: photo.member_id,
                storagePath: isFullBodyPhoto(photo) ? photo.storage_path : undefined,
              },
              { onSuccess: onDeleted },
            )
          }
        >
          {del.isPending ? "삭제 중…" : "삭제 확정"}
        </Button>
        <Button size="sm" variant="ghost" disabled={del.isPending} onClick={onCancel}>
          돌아가기
        </Button>
      </div>
    </div>
  );
}

// 라이트박스 footer — 한 줄 안내 + [삭제] → 확인 패널(BodyPhotoLightbox 주석: 보지 않은 사진을 지우는
// UI를 만들지 않는다 — 원본이 눈앞에 있는 자리가 지우는 자리다).
function PhotoDeleteControl({
  photo,
  label,
  onDeleted,
}: {
  photo: BodyPhoto;
  label: string;
  onDeleted: () => void;
}) {
  const [confirming, setConfirming] = useState(false);
  if (!confirming) {
    return (
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-[10.5px] leading-[1.7] text-muted">
          잘못 올라간 사진이면 지울 수 있어요 — 지운 뒤 {BODY_PHOTO_PURGE_AFTER_DAYS}일 안에는
          복원할 수 있어요.
        </span>
        <Button size="sm" variant="outline" className="text-danger" onClick={() => setConfirming(true)}>
          <Trash2 className="h-3 w-3" /> 삭제
        </Button>
      </div>
    );
  }
  return (
    <PhotoDeleteConfirm
      photo={photo}
      label={label}
      locked={false}
      onCancel={() => setConfirming(false)}
      onDeleted={onDeleted}
    />
  );
}

// ── 최근 삭제(서버 휴지통, v2.28 include_deleted) · 복원(v2.14) ───────────────
//
// 서버가 deleted_at이 찍힌 사진을 목록에 실어 주므로(include_deleted=true) 새로고침·다른 기기에서도
// 같은 휴지통이 보인다 — "30일 안에 복원"이 세션을 넘어 참이다. 잠긴 회원(Meta)의 삭제분도 같이
// 오지만 복원은 열람 게이트를 타므로(RestoreBodyPhoto → checkBodyPhotoAccess) 잠긴 동안은 버튼을 잠근다.
function TrashCard({
  photos,
  sequence,
  locked,
}: {
  photos: BodyPhotoListItem[];
  sequence: PoseSpec[];
  locked: boolean;
}) {
  const restore = useRestoreBodyPhoto();
  // 마지막으로 복원을 누른 행 — 진행 표시("복원 중…")와 실패 문구를 그 행 밑에 붙인다
  // (카드 하단에 뭉치면 어느 사진인지 모른다).
  const [activeId, setActiveId] = useState<string | null>(null);
  // 파기가 가까운 것부터 — 대표가 먼저 봐야 하는 행이 위에 온다.
  const sorted = useMemo(
    () => [...photos].sort((a, b) => (a.deleted_at ?? "").localeCompare(b.deleted_at ?? "")),
    [photos],
  );

  return (
    <Card className="lg:col-span-2">
      <CardHeader>
        <CardTitle>
          <Trash2 className="mr-1.5 -mt-0.5 inline h-4 w-4" />
          최근 삭제 — {BODY_PHOTO_PURGE_AFTER_DAYS}일 안에 복원 가능
        </CardTitle>
        <Badge tone="muted">{sorted.length}장</Badge>
      </CardHeader>
      <CardContent>
        <ul className="space-y-1.5">
          {sorted.map((p) => {
            const left = bodyPhotoPurgeDaysLeft(p);
            const failed = activeId === p.id && restore.isError;
            return (
              <li key={p.id} className="rounded-[10px] bg-panel-2 px-3 py-2 text-[12px]">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <span>
                    <b>{poseLabel(p.pose, sequence)}</b> · {formatMonthDay(p.date)}
                    <span className="ml-2 text-[10.5px] text-muted">
                      {left === null
                        ? "파기 예정일 미상"
                        : left === 0
                          ? "오늘 파기돼요"
                          : `${left}일 뒤 완전 파기`}
                    </span>
                  </span>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={restore.isPending || locked}
                    onClick={() => {
                      setActiveId(p.id);
                      restore.mutate({ id: p.id, memberId: p.member_id });
                    }}
                  >
                    <RotateCcw className="h-3 w-3" />{" "}
                    {restore.isPending && activeId === p.id ? "복원 중…" : "복원"}
                  </Button>
                </div>
                {failed && (
                  <p className="mt-1 text-[10.5px] text-danger">복원 실패: {restore.error.message}</p>
                )}
              </li>
            );
          })}
        </ul>
        {locked && (
          <p className="mt-2 text-[10.5px] leading-[1.7] text-warn">
            <TriangleAlert className="mr-1 -mt-0.5 inline h-3 w-3" />
            동의가 없거나 철회된 동안에는 복원할 수 없어요(복원은 사진을 되살리는 일이라 열람과 같은
            문을 탑니다). 회원이 다시 동의하면 유예가 남아 있는 한 복원돼요.
          </p>
        )}
        <p className="mt-2 text-[10.5px] leading-[1.7] text-muted">
          지운 사진은 삭제한 날부터 {BODY_PHOTO_PURGE_AFTER_DAYS}일간 여기 남아 있다가 파일까지 완전히
          파기돼요. 새로고침하거나 다른 기기에서 열어도 같은 목록이 보여요.
        </p>
      </CardContent>
    </Card>
  );
}

// ── 대표 점검 도구(v2.14 purge · v2.15 reconcile) ───────────────────────
//
// 설정 탭이 아니라 여기 있는 이유: reconcile은 **회원 한 명의 폴더**를 훑는다(서버가 member 필수).
// 회원을 고르는 셀렉트가 이 화면에 있으니 여기서 부르는 게 맞고, 설정 탭에 두면 같은 셀렉트를
// 하나 더 만들어야 한다. purge는 센터 전체 대상이지만 같은 주제(보관·파기)라 한 카드에 둔다.
//
// 파기 경계 미구성(STORAGE_BUCKET 비어 있음)이면 서버가 503 + code:"media_not_configured"로 거절한다
// (P57 A4 · v2.28 — 종전엔 `nil,nil` 강등이라 항상 "고아 0건"이 나와 조용히 무력화됐다). 판정은
// api.ts isMediaNotConfigured(code만 본다). 그 503을 일반 장애로 말하지 않고 이유를 적는다 — 대표가
// 고칠 수 있는 게 아니라 배포 설정을 쥔 쪽의 일이고, 재시도로는 낫지 않는다.
const MEDIA_NOT_CONFIGURED_MSG =
  "파기 경계가 설정되지 않았어요 — 서버 배포 설정에 저장소(STORAGE_BUCKET)가 비어 있어 파일을 훑거나 지울 수 없어요. 설정되기 전엔 삭제한 사진의 파일도 실제로 지워지지 않으니, 서버 설정을 관리하는 쪽에 알려주세요. 다시 눌러도 달라지지 않아요.";

function OwnerPhotoTools({ memberId, memberName }: { memberId: string; memberName: string }) {
  const reconcile = useReconcileBodyPhotos();
  const purge = usePurgeBodyPhotos();
  const [confirmApply, setConfirmApply] = useState(false);
  const [confirmPurge, setConfirmPurge] = useState(false);
  // 마지막 응답 — 조회(apply=false)와 정리(apply=true)가 같은 뮤테이션이라 applied로 가른다.
  // 회원이 바뀌면 부모가 key로 리마운트하지 않으므로 memberId를 결과와 함께 기억해 남의 결과를
  // 이 회원 것처럼 보이지 않게 한다.
  const [resultFor, setResultFor] = useState<string | null>(null);
  const result = resultFor === memberId ? reconcile.data : undefined;

  function runReconcile(apply: boolean) {
    reconcile.mutate(
      { member: memberId, apply },
      {
        onSuccess: () => {
          setResultFor(memberId);
          setConfirmApply(false);
        },
      },
    );
  }

  return (
    <Card className="lg:col-span-2">
      <CardHeader>
        <CardTitle>
          <Wrench className="mr-1.5 -mt-0.5 inline h-4 w-4" />
          보관·파기 점검 (대표)
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4 text-[12px]">
        {/* ── 정합 검사 ── */}
        <div>
          <div className="mb-1 text-[11.5px] font-extrabold">정합 검사 — {memberName} 님의 사진 저장소</div>
          <p className="text-[10.5px] leading-[1.8] text-muted">
            저장소 폴더를 거꾸로 훑어 <b className="text-ink">기록이 없는 파일(고아)</b>을 찾아요.
            삭제가 파일 먼저·기록 나중이라 정상 경로에선 생기지 않지만, 파기 경계가 꺼진 채 지운
            사진은 파일만 남을 수 있어요 — 그 파일은 어떤 목록에도 보이지 않아 여기서만 찾을 수 있어요.
            검사만으로는 아무것도 지우지 않아요.
          </p>
          <div className="mt-2 flex flex-wrap gap-2">
            <Button
              size="sm"
              variant="outline"
              disabled={reconcile.isPending}
              onClick={() => {
                setConfirmApply(false);
                runReconcile(false);
              }}
            >
              <Wrench className="h-3 w-3" /> {reconcile.isPending && !confirmApply ? "검사 중…" : "정합 검사"}
            </Button>
          </div>
          {reconcile.isError && (
            <p
              className={`mt-2 text-[11px] leading-[1.8] ${
                isMediaNotConfigured(reconcile.error)
                  ? "rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-warn"
                  : "text-danger"
              }`}
            >
              {isMediaNotConfigured(reconcile.error) && (
                <TriangleAlert className="mr-1 -mt-0.5 inline h-3.5 w-3.5" />
              )}
              {isMediaNotConfigured(reconcile.error) ? MEDIA_NOT_CONFIGURED_MSG : reconcile.error.message}
            </p>
          )}
          {result && (
            <div className="mt-2 rounded-[10px] bg-panel-2 px-3 py-2.5">
              <div className="flex flex-wrap items-center gap-2">
                <span>
                  저장소 파일 <b>{result.storage_objects}</b>개 · 기록이 가리키는 파일{" "}
                  <b>{result.known_paths}</b>개
                </span>
                {result.applied ? (
                  <Badge tone={result.deleted === result.orphans.length ? "ok" : "warn"}>
                    고아 {result.deleted}개 파기됨
                    {result.deleted !== result.orphans.length && ` (${result.orphans.length}개 중)`}
                  </Badge>
                ) : result.orphans.length === 0 ? (
                  <Badge tone="ok">고아 파일 없음</Badge>
                ) : (
                  <Badge tone="warn">고아 {result.orphans.length}개</Badge>
                )}
              </div>
              {!result.applied && result.orphans.length > 0 && (
                <>
                  <details className="mt-1.5 text-[10.5px] text-muted">
                    <summary className="cursor-pointer">경로 보기</summary>
                    <ul className="mt-1 space-y-0.5 font-mono text-[10px] break-all">
                      {result.orphans.map((o) => (
                        <li key={o}>{o}</li>
                      ))}
                    </ul>
                  </details>
                  {!confirmApply ? (
                    <Button
                      size="sm"
                      variant="outline"
                      className="mt-2 text-danger"
                      onClick={() => setConfirmApply(true)}
                    >
                      <Trash2 className="h-3 w-3" /> 고아 파일 {result.orphans.length}개 파기
                    </Button>
                  ) : (
                    <div className="mt-2 rounded-[10px] border border-danger/40 bg-danger/[0.08] p-3">
                      <p className="text-[11.5px] leading-relaxed text-danger">
                        기록이 없는 파일 <b>{result.orphans.length}개</b>를 저장소에서 지웁니다.
                        기록이 가리키는 파일(유예 중인 삭제분 포함)은 건드리지 않아요. 되돌릴 수 없어요.
                      </p>
                      <div className="mt-2 flex gap-2">
                        <Button
                          size="sm"
                          variant="danger"
                          disabled={reconcile.isPending}
                          onClick={() => runReconcile(true)}
                        >
                          {reconcile.isPending ? "파기 중…" : "파기 확정"}
                        </Button>
                        <Button
                          size="sm"
                          variant="ghost"
                          disabled={reconcile.isPending}
                          onClick={() => setConfirmApply(false)}
                        >
                          취소
                        </Button>
                      </div>
                    </div>
                  )}
                </>
              )}
            </div>
          )}
        </div>

        {/* ── 기한 지난 사진 파기(센터 전체) ── */}
        <div className="border-t border-line pt-3">
          <div className="mb-1 text-[11.5px] font-extrabold">기한 지난 사진 파기 — 센터 전체</div>
          <p className="text-[10.5px] leading-[1.8] text-muted">
            삭제 후 {BODY_PHOTO_PURGE_AFTER_DAYS}일이 지난 사진은 평소에도 조회 때마다 조금씩
            파기돼요. 회원 요청이나 점검으로 <b className="text-ink">지금 당장</b> 지워야 할 때 눌러요
            — 한 번에 최대 25건이라 더 남았으면 다시 누르면 돼요. 유예가 남은 사진은 건드리지 않아요.
          </p>
          {!confirmPurge ? (
            <Button
              size="sm"
              variant="outline"
              className="mt-2"
              disabled={purge.isPending}
              onClick={() => {
                purge.reset();
                setConfirmPurge(true);
              }}
            >
              <Trash2 className="h-3 w-3" /> 지금 파기
            </Button>
          ) : (
            <div className="mt-2 rounded-[10px] border border-danger/40 bg-danger/[0.08] p-3">
              <p className="text-[11.5px] leading-relaxed text-danger">
                유예 {BODY_PHOTO_PURGE_AFTER_DAYS}일이 지난 사진의 <b>파일과 기록을 완전히
                파기</b>합니다(센터 전체, 최대 25건). 되돌릴 수 없어요.
              </p>
              <div className="mt-2 flex gap-2">
                <Button
                  size="sm"
                  variant="danger"
                  disabled={purge.isPending}
                  onClick={() => purge.mutate(undefined, { onSuccess: () => setConfirmPurge(false) })}
                >
                  {purge.isPending ? "파기 중…" : "파기 확정"}
                </Button>
                <Button size="sm" variant="ghost" disabled={purge.isPending} onClick={() => setConfirmPurge(false)}>
                  취소
                </Button>
              </div>
            </div>
          )}
          {purge.isSuccess && (
            <p className="mt-2 text-[11px] text-ok">
              {purge.data.purged === 0
                ? "파기할 사진이 없어요 — 유예가 지난 사진이 없습니다."
                : `${purge.data.purged}건을 파기했어요.${purge.data.purged >= 25 ? " 더 남았을 수 있으니 한 번 더 눌러주세요." : ""}`}
            </p>
          )}
          {purge.isError && (
            <p
              className={`mt-2 text-[11px] leading-[1.8] ${
                isMediaNotConfigured(purge.error)
                  ? "rounded-[10px] border border-warn/40 bg-warn/10 px-3 py-2 text-warn"
                  : "text-danger"
              }`}
            >
              {isMediaNotConfigured(purge.error) ? MEDIA_NOT_CONFIGURED_MSG : `파기 실패: ${purge.error.message}`}
            </p>
          )}
        </div>
      </CardContent>
    </Card>
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
      {/* 폰 폭(375px)에서 3열은 각 칸이 100px 아래로 눌려 "1000~4000kcal" 같은 placeholder가
          잘려 나갔다 — 무엇을 넣는 칸인지 화면이 말하지 못하는 상태다. 좁을 땐 2열로 접고
          sm(640px) 이상에서만 종전의 4열로 편다(측정일은 언제나 전폭). */}
      <div className="grid grid-cols-2 gap-1.5 sm:grid-cols-4">
        <div className="col-span-2 sm:col-span-4">
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
          6개 지표를 모두 입력해야 저장할 수 있어요 — 빈 칸은 0으로 기록돼 저장되지 않아요.
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
