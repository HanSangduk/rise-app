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
 *
 * **개수 상한이 있다**(P74 — 앱 body_photo_loader의 40장과 같은 이유). 데스크 PC는 하루 종일
 * 열려 있어 클릭한 사진 원본(장당 수 MB)이 로그아웃 전까지 전부 탭 메모리에 쌓였다. `Map`은 삽입
 * 순서를 지키므로 히트 때 뒤로 옮기고 앞에서 지우면 최근 사용 순이 된다. 라이트박스는 한 번에
 * 한 장만 띄우고 그 장이 가장 최근이라, 보고 있는 사진의 URL이 밀려나 깨지는 일은 없다.
 */
const cache = new Map<string, string>();
export const MAX_BODY_PHOTO_BLOBS = 30;

/** 비운 횟수 — 받는 **도중에** 세션이 끝나면(로그아웃·계정 전환) 그 뒤 도착한 사진을 다음 세션
 *  캐시에 넣지 않기 위한 표식(P74). 맵만 비우면 느린 망에서 이전 사람이 연 민감 사진이 다음 사람
 *  세션의 캐시로 다시 들어온다. 오르는 것은 세션 경계뿐이라 같은 세션 안의 로드끼리는 무효화하지 않는다. */
let epoch = 0;

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
  if (hit) {
    cache.delete(storagePath); // 최근 사용으로 갱신(뒤로 옮긴다)
    cache.set(storagePath, hit);
    return hit;
  }

  const started = epoch;
  let blob: Blob;
  try {
    blob = await getBlob(ref(storage, storagePath));
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
  if (started !== epoch) {
    // 받는 사이 세션이 끝났다 — blob URL을 만들지 않는다(만들면 다음 세션 캐시에 남거나, 아무도
    // revoke하지 않아 탭이 닫힐 때까지 메모리에 남는다). 요청한 화면은 이미 사라진 세션의 것이다.
    throw new BodyPhotoLoadError("network", "세션이 바뀌어 사진을 다시 불러와야 해요");
  }
  // 같은 사진을 동시에 두 번 받은 경우(다시 시도 연타) — 먼저 넣은 URL을 쓴다. 새로 만들어 덮으면
  // 앞의 URL은 맵에서 빠진 채 revoke되지 않고 남는다.
  const raced = cache.get(storagePath);
  if (raced) return raced;
  const url = URL.createObjectURL(blob);
  cache.set(storagePath, url);
  while (cache.size > MAX_BODY_PHOTO_BLOBS) {
    const oldest = cache.keys().next().value as string;
    URL.revokeObjectURL(cache.get(oldest)!);
    cache.delete(oldest);
  }
  return url;
}

/** 삭제 성공 직후(v2.14) — 한 장만 비운다. 복원되면 라이트박스가 같은 경로를 다시 받는다(파일은
 *  유예 동안 그대로라 stale일 수 없다). 없는 키는 조용히 무시. */
export function evictBodyPhotoBlob(storagePath: string) {
  const url = cache.get(storagePath);
  if (!url) return;
  URL.revokeObjectURL(url);
  cache.delete(storagePath);
}

/** 로그아웃·계정 전환 시. 남의 사진 blob이 남아 있으면 안 된다. */
export function clearBodyPhotoBlobs() {
  epoch++;
  for (const url of cache.values()) URL.revokeObjectURL(url);
  cache.clear();
}

/** 시험·진단용 — 지금 캐시에 든 경로를 오래된 순으로. */
export function cachedBodyPhotoPaths(): string[] {
  return [...cache.keys()];
}
