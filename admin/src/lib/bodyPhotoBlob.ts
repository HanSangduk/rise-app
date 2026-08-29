import { getBlob, ref } from "firebase/storage";
import { storage } from "./firebase";

/**
 * 체형사진 원본을 blob URL로 가져온다(P21).
 *
 * **그리드에서 자동 로드하지 않는다** — 업로드가 `no-store`로 올린 파일이라 브라우저 캐시가
 * 듣지 않고, 포즈 하나에 수십 장이 쌓이면 매번 수십 MB를 다시 받는다. 클릭한 한 장만
 * 라이트박스에서 받는 것이 v1의 상한이다(섬네일 파이프라인은 범위 밖).
 *
 * 세션 캐시가 안전한 근거: 파일명에 촬영 시각(epochMillis)이 박혀 **같은 경로가 다른 사진을
 * 가리키지 않고**, 규칙이 삭제·덮어쓰기를 막는다. 즉 stale이 될 수 없다.
 */
const cache = new Map<string, string>();

export type BodyPhotoBlobError = "forbidden" | "notfound" | "network";

export class BodyPhotoLoadError extends Error {
  constructor(readonly kind: BodyPhotoBlobError, message: string) {
    super(message);
  }
}

export async function loadBodyPhotoUrl(storagePath: string): Promise<string> {
  if (!storagePath) {
    throw new BodyPhotoLoadError("notfound", "사진 파일 정보가 없어요");
  }
  const hit = cache.get(storagePath);
  if (hit) return hit;

  try {
    const blob = await getBlob(ref(storage, storagePath));
    const url = URL.createObjectURL(blob);
    cache.set(storagePath, url);
    return url;
  } catch (e) {
    // 규칙이 거부하는 대표적 이유는 **회원이 민감정보 동의를 철회한 것**이다.
    // 목록(서버 API)은 동의를 안 보고 내려주는데 규칙은 본다 — 그래서 "목록은 200,
    // 바이트는 403"이 비정상이 아니라 정상 경로다. UI가 이걸 구분해 말해야 한다.
    const code = (e as { code?: string })?.code ?? "";
    if (code.includes("unauthorized") || code.includes("unauthenticated")) {
      throw new BodyPhotoLoadError(
        "forbidden",
        "이 사진을 볼 권한이 없어요 — 회원의 민감정보 동의가 철회됐을 수 있어요",
      );
    }
    if (code.includes("object-not-found")) {
      throw new BodyPhotoLoadError("notfound", "사진 파일을 찾지 못했어요");
    }
    throw new BodyPhotoLoadError("network", "사진을 불러오지 못했어요 — 잠시 후 다시 시도해주세요");
  }
}

/** 로그아웃·회원 전환 시. 남의 사진 blob이 남아 있으면 안 된다. */
export function clearBodyPhotoBlobs() {
  for (const url of cache.values()) URL.revokeObjectURL(url);
  cache.clear();
}
