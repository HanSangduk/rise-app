import { useMemo, useState } from "react";
import { ArrowDown, ArrowUp, Plus, RotateCcw, Trash2 } from "lucide-react";
import { Button, Card, CardContent, CardHeader, CardTitle, Input } from "@/components/ui";
import { useUpdateMember } from "@/lib/queries";
import {
  DEFAULT_BODY_POSES,
  POSE_LABEL_MAX,
  POSE_MAX_COUNT,
  type Member,
  type PoseSpec,
} from "@/lib/types";

/**
 * 회원별 체형 촬영 포즈 시퀀스 편집(계약 v2.10).
 *
 * 종전에는 차렷·T자·전굴·OH스쿼트 4종이 앱·서버·어드민 세 곳에 하드코딩돼 있었다 —
 * 개발자가 임의로 정한 값이라 센터마다 다른 촬영 프로토콜을 담을 수 없었다.
 *
 * **화면에서 묻는 것은 "뭐라고 부를지"(표시명) 하나뿐이다.** 종전엔 표시명 옆에 `key` 칸을
 * 나란히 두고 `front_relax` 같은 영문 슬러그를 대표가 직접 지어내게 했다. key는 사진 파일명
 * 조각이라 서버가 `^[a-z0-9_]{1,24}$`를 강제하는데(하이픈은 파일명 구분자), 그건 저장 구조의
 * 사정이지 센터의 규칙이 아니다 — 한국어만 쓰는 대표가 스스로 알아낼 방법이 없는 값을 묻고
 * 답할 때까지 저장을 잠갔다. 지금은 **제품이 key를 만든다**: 기존 행은 저장된 key를 그대로
 * 들고 다니고, 새 행에는 목록 안에서 겹치지 않는 `pose_1`… 을 붙인다. 화면에 key 입력이
 * 없으므로 저장된 key는 **구조적으로 불변**이다("저장한 뒤엔 바꾸지 마세요"라는 당부가
 * 필요 없어졌다 — 지킬 방법을 사용자에게 떠넘기는 대신 바꿀 수 없게 만들었다).
 *
 * 저장은 `body_poses`만 실은 머지 PUT이다 — 회원 정보 폼과 서로 덮어쓰지 않는다.
 */
export function PoseSequenceEditor({ member }: { member: Member }) {
  const effective = member.body_poses?.length ? member.body_poses : DEFAULT_BODY_POSES;
  const [poses, setPoses] = useState<PoseSpec[]>(effective);
  const [dirty, setDirty] = useState(false);
  // "기본으로 되돌리기" 2단 확인 — 회원별 순서를 통째로 버리는 파괴적 액션인데 되돌리는
  // 기능이 없다(직전 목록은 어디에도 남지 않는다). 납부 처리·환불과 같은 무게로 다룬다.
  const [resetConfirm, setResetConfirm] = useState(false);
  const update = useUpdateMember();

  /** 기본과 같은 구성인가 — "지금 기본을 쓰는 중"을 알려주기 위한 근사. */
  const isDefault = useMemo(
    () =>
      poses.length === DEFAULT_BODY_POSES.length &&
      poses.every((p, i) => p.key === DEFAULT_BODY_POSES[i].key && p.label === DEFAULT_BODY_POSES[i].label),
    [poses],
  );

  /**
   * 남은 검증은 표시명뿐이다 — key는 화면이 만들어 넣으므로 사용자가 틀릴 수 없고,
   * 중복도 생기지 않는다(mintKey가 목록 전체를 보고 비어 있는 번호를 고른다).
   */
  const errors = useMemo(() => {
    const out: Record<number, string> = {};
    poses.forEach((p, i) => {
      const label = p.label.trim();
      if (!label) out[i] = "표시명을 입력해주세요";
      else if (label.length > POSE_LABEL_MAX) out[i] = `표시명은 ${POSE_LABEL_MAX}자까지예요`;
    });
    return out;
  }, [poses]);

  const countError =
    poses.length === 0
      ? "포즈가 최소 1개는 있어야 해요"
      : poses.length > POSE_MAX_COUNT
        ? `포즈는 최대 ${POSE_MAX_COUNT}개까지예요`
        : null;
  const valid = !countError && Object.keys(errors).length === 0;

  const mutate = (next: PoseSpec[]) => {
    setPoses(next);
    setDirty(true);
  };
  const move = (i: number, d: -1 | 1) => {
    const j = i + d;
    if (j < 0 || j >= poses.length) return;
    const next = [...poses];
    [next[i], next[j]] = [next[j], next[i]];
    mutate(next);
  };

  const save = (body: PoseSpec[] | null) =>
    update.mutate(
      // null = "센터 기본으로 되돌리기"(서버가 []→nil로 정규화해 기본을 따라간다).
      { id: member.id, patch: { body_poses: body } as Partial<Member> },
      {
        onSuccess: (saved) => {
          // **저장 결과를 이 목록에도 되돌려 받는다.** 종전엔 dirty만 껐다 — 되돌리기를 누르면
          // 위 타임라인 칩(회원 목록 재조회분)은 기본 4종으로 바뀌는데 아래 이 목록은 방금 버린
          // 커스텀 포즈를 계속 보여줬다. 한 화면의 두 패널이 서로 다른 말을 하고, 저장 버튼도
          // 잠겨 있어 화면 안에서는 맞출 방법이 없었다(새로고침이 유일한 해소책이었다).
          // 응답에 구체화된 목록이 오면 그게 진실이고, 안 오면 방금 보낸 값(저장) 혹은
          // 센터 기본(되돌리기)으로 접는다 — 위 칩이 쓰는 폴백과 같은 규칙.
          setPoses(saved.body_poses?.length ? saved.body_poses : (body ?? DEFAULT_BODY_POSES));
          setDirty(false);
          setResetConfirm(false);
        },
      },
    );

  return (
    <Card>
      <CardHeader>
        <CardTitle>촬영 포즈 시퀀스</CardTitle>
      </CardHeader>
      <CardContent>
        <p className="mb-2.5 text-[10.5px] text-muted">
          이 회원의 앱 촬영 화면에 뜨는 순서예요{isDefault && " (지금은 센터 기본을 쓰는 중)"}.
          바꿔도 <b>이미 찍은 사진은 그대로 보입니다</b> — 목록에서 뺀 포즈는 뒤쪽에 남아요.
        </p>

        <div className="flex flex-col gap-1.5">
          {poses.map((p, i) => (
            <div key={i} className="rounded-[10px] border border-line bg-panel-2 p-2">
              <div className="flex items-center gap-1.5">
                <span className="w-4 text-center text-[11px] text-muted">{i + 1}</span>
                <Input
                  value={p.label}
                  placeholder="표시명 (예: 정면 이완)"
                  onChange={(e) =>
                    mutate(poses.map((q, j) => (j === i ? { ...q, label: e.target.value } : q)))
                  }
                />
                <button
                  type="button"
                  title="위로"
                  disabled={i === 0}
                  onClick={() => move(i, -1)}
                  className="p-1 text-muted disabled:opacity-30"
                >
                  <ArrowUp className="h-3.5 w-3.5" />
                </button>
                <button
                  type="button"
                  title="아래로"
                  disabled={i === poses.length - 1}
                  onClick={() => move(i, 1)}
                  className="p-1 text-muted disabled:opacity-30"
                >
                  <ArrowDown className="h-3.5 w-3.5" />
                </button>
                <button
                  type="button"
                  title="삭제"
                  onClick={() => mutate(poses.filter((_, j) => j !== i))}
                  className="p-1 text-danger"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </div>
              {errors[i] && <p className="mt-1 pl-6 text-[10.5px] text-danger">{errors[i]}</p>}
            </div>
          ))}
        </div>

        {countError && <p className="mt-1.5 text-[10.5px] text-danger">{countError}</p>}

        <div className="mt-2.5 flex flex-wrap items-center gap-1.5">
          <Button
            variant="outline"
            size="sm"
            disabled={poses.length >= POSE_MAX_COUNT}
            onClick={() => mutate([...poses, { key: mintKey(poses), label: "" }])}
          >
            <Plus className="mr-1 h-3.5 w-3.5" />
            포즈 추가
          </Button>
          <Button
            variant="outline"
            size="sm"
            disabled={update.isPending || resetConfirm}
            onClick={() => {
              setResetConfirm(true);
              update.reset(); // 앞선 저장의 에러 문구가 새 확인 위에 남지 않게
            }}
          >
            <RotateCcw className="mr-1 h-3.5 w-3.5" />
            기본으로 되돌리기
          </Button>
          <Button
            size="sm"
            // 되돌리기 확인 중에는 저장을 잠근다 — 둘 다 같은 update.isPending을 쓰므로,
            // 확인창을 열어둔 채 저장을 누르면 확인창이 "되돌리는 중…"이라고 거짓말한다.
            disabled={!valid || !dirty || update.isPending || resetConfirm}
            onClick={() =>
              save(poses.map((p) => ({ key: p.key, label: p.label.trim() })))
            }
          >
            {update.isPending ? "저장 중…" : "저장"}
          </Button>
        </div>

        {resetConfirm && (
          <div className="mt-2 rounded-[10px] border border-danger/40 bg-danger/[0.08] p-3">
            <p className="text-[11.5px] leading-relaxed text-danger">
              이 회원만의 촬영 순서를 지우고 <b>센터 기본({DEFAULT_BODY_POSES.map((p) => p.label).join(" · ")})</b>으로
              되돌립니다. 지금 만들어 둔 목록은 어디에도 남지 않아 되돌릴 수 없고, 다시 쓰려면
              직접 입력해야 해요. <b>이미 찍은 사진은 그대로 남습니다</b> — 목록에서 빠진 포즈의
              사진은 타임라인 뒤쪽에서 계속 볼 수 있어요.
            </p>
            <div className="mt-2 flex gap-2">
              <Button
                size="sm"
                variant="danger"
                disabled={update.isPending}
                onClick={() => save(null)}
              >
                {update.isPending ? "되돌리는 중…" : "기본으로 되돌리기 확정"}
              </Button>
              <Button
                size="sm"
                variant="ghost"
                disabled={update.isPending}
                onClick={() => setResetConfirm(false)}
              >
                돌아가기
              </Button>
            </div>
          </div>
        )}

        {update.isError && (
          <p className="mt-1.5 text-[10.5px] text-danger">
            저장하지 못했어요: {(update.error as Error).message}
          </p>
        )}
      </CardContent>
    </Card>
  );
}

/**
 * 새 포즈의 key를 제품이 만든다 — 사용자에게 묻지 않는 값이다.
 *
 * `pose_1`, `pose_2` … 중 **지금 목록에 없는 첫 번째 번호**를 쓴다. 형식은 서버 규칙
 * (types.ts `POSE_KEY_RE` = 영소문자·숫자·밑줄 1~24자)을 항상 만족하고, 목록 전체를 보고
 * 고르므로 중복도 나오지 않는다. 삭제 후 다시 추가하면 빈 번호를 재사용하는데, 그 번호로
 * 찍힌 옛 사진이 있으면 같은 포즈로 합쳐진다 — 지운 포즈를 되살리는 흔한 경우엔 이쪽이
 * 사진을 되찾아 주므로 그대로 둔다(체형사진은 삭제 API가 없어 안 보이면 확인할 길이 없다).
 *
 * 후보가 목록 크기보다 항상 많아 반드시 끝난다(비둘기집).
 */
function mintKey(poses: PoseSpec[]): string {
  const taken = new Set(poses.map((p) => p.key));
  let n = 1;
  while (taken.has(`pose_${n}`)) n++;
  return `pose_${n}`;
}
