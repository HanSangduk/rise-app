import { useMemo, useState } from "react";
import { ArrowDown, ArrowUp, Plus, RotateCcw, Trash2 } from "lucide-react";
import { Button, Card, CardContent, CardHeader, CardTitle, Input } from "@/components/ui";
import { useUpdateMember } from "@/lib/queries";
import {
  DEFAULT_BODY_POSES,
  POSE_KEY_RE,
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
 * **검증을 서버와 같은 규칙으로 여기서도 건다.** 서버 400 문구에 의존하면 어느 칸이
 * 틀렸는지 알 수 없고, 특히 key 규칙(하이픈 금지)은 이유가 파일명 구조에 있어 사용자가
 * 스스로 알아낼 방법이 없다.
 *
 * 저장은 `body_poses`만 실은 머지 PUT이다 — 회원 정보 폼과 서로 덮어쓰지 않는다.
 */
export function PoseSequenceEditor({ member }: { member: Member }) {
  const effective = member.body_poses?.length ? member.body_poses : DEFAULT_BODY_POSES;
  const [poses, setPoses] = useState<PoseSpec[]>(effective);
  const [dirty, setDirty] = useState(false);
  const update = useUpdateMember();

  /** 기본과 같은 구성인가 — "지금 기본을 쓰는 중"을 알려주기 위한 근사. */
  const isDefault = useMemo(
    () =>
      poses.length === DEFAULT_BODY_POSES.length &&
      poses.every((p, i) => p.key === DEFAULT_BODY_POSES[i].key && p.label === DEFAULT_BODY_POSES[i].label),
    [poses],
  );

  /** 서버 ValidateBodyPoses 미러. 칸 단위로 이유를 돌려준다. */
  const errors = useMemo(() => {
    const out: Record<number, string> = {};
    const seen = new Set<string>();
    poses.forEach((p, i) => {
      const key = p.key.trim();
      const label = p.label.trim();
      if (!POSE_KEY_RE.test(key)) {
        out[i] = "영소문자·숫자·밑줄 1~24자예요(하이픈은 사진 파일명 구분자라 쓸 수 없어요)";
      } else if (seen.has(key)) {
        out[i] = "같은 key가 이미 있어요";
      } else if (!label) {
        out[i] = "표시명을 입력해주세요";
      } else if (label.length > POSE_LABEL_MAX) {
        out[i] = `표시명은 ${POSE_LABEL_MAX}자까지예요`;
      }
      seen.add(key);
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
      { onSuccess: () => setDirty(false) },
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
                <Input
                  value={p.key}
                  placeholder="key (front_relax)"
                  onChange={(e) =>
                    mutate(poses.map((q, j) => (j === i ? { ...q, key: e.target.value } : q)))
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
            onClick={() => mutate([...poses, { key: "", label: "" }])}
          >
            <Plus className="mr-1 h-3.5 w-3.5" />
            포즈 추가
          </Button>
          <Button
            variant="outline"
            size="sm"
            disabled={update.isPending}
            onClick={() => save(null)}
            title="센터 기본 4종으로 되돌립니다"
          >
            <RotateCcw className="mr-1 h-3.5 w-3.5" />
            기본으로 되돌리기
          </Button>
          <Button
            size="sm"
            disabled={!valid || !dirty || update.isPending}
            onClick={() =>
              save(poses.map((p) => ({ key: p.key.trim(), label: p.label.trim() })))
            }
          >
            {update.isPending ? "저장 중…" : "저장"}
          </Button>
        </div>

        {update.isError && (
          <p className="mt-1.5 text-[10.5px] text-danger">
            저장하지 못했어요: {(update.error as Error).message}
          </p>
        )}
        <p className="mt-2 text-[10.5px] text-muted">
          key는 사진 파일명에 들어가서 저장한 뒤에는 바꾸지 않는 게 좋아요 — 바꾸면 그 key로
          찍힌 사진이 별도 포즈로 남습니다.
        </p>
      </CardContent>
    </Card>
  );
}
