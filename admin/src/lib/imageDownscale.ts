/**
 * 업로드 직전 사진 축소 — 브라우저 안에서 캔버스로 다시 그려 base64로 만든다.
 *
 * **왜 클라이언트에서 줄이나.** 대표가 올리는 사진은 폰 카메라 원본(3~5MB, 4000px 급)인데
 * 서버는 디코드 후 2MB를 넘기면 거절한다 — 그대로 보내면 "고른 사진마다 거절"이 되고, 대표가
 * 할 수 있는 일이 없다(폰 사진을 리사이즈할 도구를 대표가 갖고 있다고 가정할 수 없다).
 * 아바타는 화면에서 최대 48px로 그려지므로 512px이면 레티나(2x)에도 충분하다.
 *
 * **EXIF 회전을 여기서 처리한다.** 아이폰 세로 사진은 픽셀이 가로로 저장되고 회전 정보만 EXIF에
 * 들어간다 — 캔버스에 그냥 그리면 90° 누운 얼굴이 저장된다. createImageBitmap의
 * `imageOrientation: "from-image"`가 디코드 시점에 그 회전을 적용해 주므로 비용이 사실상 0이다
 * (직접 EXIF를 파싱하면 파서를 하나 들여와야 한다 — 의존성을 늘리지 않는다는 이 프로젝트의 규약과
 * 어긋난다). 이 옵션이 없는 오래된 브라우저에서는 <img> 폴백으로 내려가는데, 최신 브라우저의
 * <img>는 CSS image-orientation 기본값이 from-image라 같은 결과가 나온다.
 *
 * **JPEG vs PNG.** 기본은 JPEG(품질 0.85)다 — 사람 사진에서 PNG는 같은 화질에 5~10배 크다.
 * 다만 투명 배경이 있는 원본(로고형 PNG·WEBP)을 JPEG로 접으면 캔버스의 투명 영역이 **검게**
 * 칠해져 얼굴 대신 검은 사각형이 남는다. 그래서 알파를 가질 수 있는 형식만 축소 후 픽셀을 훑어
 * 실제 투명 픽셀이 있을 때에만 PNG로 남긴다(512px 이하 = 최대 26만 픽셀 1회 스캔, 수 ms).
 */

/** 긴 변 상한. 아바타 최대 표시 48px의 레티나(2x) 여유까지 덮고도 남는다. */
export const PHOTO_MAX_SIDE = 512;

/** JPEG 품질 — 512px 인물 사진에서 0.85 아래로 내리면 피부 톤에 블록이 보이기 시작한다. */
const JPEG_QUALITY = 0.85;

/**
 * 서버 상한 미러(디코드 후 바이트). 서버가 최종 집행자이고 이 값은 "보내기 전에 알아채기" 용도다.
 * base64 문자열이 아니라 **디코드된 바이트**를 센다 — 서버가 그렇게 센다.
 */
export const PHOTO_MAX_BYTES = 2 * 1024 * 1024;

/**
 * 1차 인코딩이 상한을 넘었을 때의 2차 시도. 실제로는 거의 일어나지 않지만(512px JPEG는 보통
 * 40~90KB), 여기서 한 번 더 줄이는 비용이 5줄이라 "막다른 길" 대신 성공으로 바꾼다.
 */
const RETRY_SIDE = 384;
const RETRY_QUALITY = 0.6;

/** 알파 채널을 가질 수 있는 원본 형식 — 이 목록에 없으면 투명 스캔 자체를 건너뛴다. */
const ALPHA_CAPABLE = /^image\/(png|webp|gif|avif|svg\+xml)$/i;

export type PhotoPrepKind =
  /** 이미지가 아닌 파일(문서·동영상 등) */
  | "not_image"
  /** 브라우저가 디코드하지 못함(HEIC·손상 파일) */
  | "decode"
  /** 캔버스 인코딩 실패(메모리 부족 등) */
  | "encode"
  /** 줄인 뒤에도 서버 상한 초과 — 정상 경로에서는 나오지 않는다 */
  | "too_large";

/**
 * 실패 사유를 **종류로** 들고 다니는 에러. 화면이 문자열을 다시 파싱하지 않고 분기하도록
 * (api.ts ApiError.status와 같은 취지) — message는 그대로 화면에 나가는 한국어다.
 */
export class PhotoPrepError extends Error {
  readonly kind: PhotoPrepKind;
  constructor(kind: PhotoPrepKind, message: string) {
    super(message);
    this.name = "PhotoPrepError";
    this.kind = kind;
  }
}

export interface PreparedPhoto {
  /** data: 접두사를 뗀 순수 base64 — 계약이 그 모양을 요구한다. */
  base64: string;
  content_type: "image/jpeg" | "image/png";
  /** 디코드 기준 바이트(= 서버가 세는 값). 화면이 "3.9MB → 71KB"를 말할 때 쓴다. */
  bytes: number;
  width: number;
  height: number;
  source_bytes: number;
}

/** 사람이 읽는 크기 표기 — 실패 문구와 성공 안내가 같은 모양을 쓰게 한 곳에 둔다. */
export function formatBytes(n: number): string {
  if (n >= 1024 * 1024) return `${(n / (1024 * 1024)).toFixed(1)}MB`;
  if (n >= 1024) return `${Math.round(n / 1024)}KB`;
  return `${n}B`;
}

/**
 * 파일 → 서버로 보낼 준비가 끝난 사진. 실패는 전부 PhotoPrepError(한국어 message)다.
 *
 * 파일 확장자가 아니라 **디코드 성공 여부**를 기준으로 삼는다: `accept="image/*"`는 브라우저마다
 * 새는 구멍이 있고, 반대로 확장자가 낯설어도 브라우저가 열 수 있으면 아바타로 쓰는 데 문제가 없다.
 */
export async function preparePhoto(file: File): Promise<PreparedPhoto> {
  // MIME이 image/*가 아닌 건 여기서 끊는다 — 5MB짜리 PDF를 디코더에 넘길 이유가 없다.
  // (드래그앤드롭은 파일 선택창의 accept 필터를 지나지 않으므로 이 검사가 유일한 문지기다.)
  if (file.type && !file.type.startsWith("image/")) {
    throw new PhotoPrepError(
      "not_image",
      "이미지 파일이 아니에요 — JPG · PNG · WEBP 사진 파일을 골라주세요.",
    );
  }

  const source = await decodeImage(file);
  try {
    const first = await encodeAtScale(source, PHOTO_MAX_SIDE, JPEG_QUALITY, file.type);
    if (first.blob.size <= PHOTO_MAX_BYTES) return await toPrepared(first, file.size);

    // 2차 시도(더 작게·더 낮은 품질). 투명 PNG는 품질 인자가 없어 크기 축소만 걸린다.
    const second = await encodeAtScale(source, RETRY_SIDE, RETRY_QUALITY, file.type);
    if (second.blob.size <= PHOTO_MAX_BYTES) return await toPrepared(second, file.size);

    throw new PhotoPrepError(
      "too_large",
      `사진을 줄였는데도 용량이 커요(${formatBytes(second.blob.size)}) — 보통은 생기지 않는 일이에요. 다른 사진으로 올려주시고, 계속 그러면 알려주세요.`,
    );
  } finally {
    // ImageBitmap은 GC를 기다리지 않고 즉시 놓아준다(폰 원본 여러 장을 연속으로 고르는 흐름).
    if ("close" in source) source.close();
  }
}

// ── 내부 ────────────────────────────────────────────────────────────────

type DecodedImage = ImageBitmap | HTMLImageElement;

function sizeOf(img: DecodedImage): { w: number; h: number } {
  return img instanceof HTMLImageElement
    ? { w: img.naturalWidth, h: img.naturalHeight }
    : { w: img.width, h: img.height };
}

/**
 * 디코드 — createImageBitmap 우선(EXIF 회전 적용), 실패하면 <img> 폴백.
 *
 * 폴백을 남기는 이유: createImageBitmap이 없거나(구형) 특정 형식만 거부하는 브라우저가 있는데,
 * 그때 "사진을 못 올린다"로 끝나면 이 기능을 만든 의미가 없다. 두 경로 모두 실패해야 decode 에러다.
 */
async function decodeImage(file: File): Promise<DecodedImage> {
  if (typeof createImageBitmap === "function") {
    try {
      return await createImageBitmap(file, { imageOrientation: "from-image" });
    } catch {
      /* 폴백으로 내려간다 */
    }
  }
  const url = URL.createObjectURL(file);
  try {
    return await new Promise<HTMLImageElement>((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () =>
        reject(
          new PhotoPrepError(
            "decode",
            "이 사진을 열지 못했어요 — 아이폰 HEIC처럼 브라우저가 못 여는 형식일 수 있어요. 사진을 JPG로 저장한 뒤 다시 올려주세요.",
          ),
        );
      img.src = url;
    });
  } finally {
    // <img>는 src를 이미 읽었으므로 즉시 해제해도 안전하다(디코드는 onload 시점에 끝났다).
    URL.revokeObjectURL(url);
  }
}

interface Encoded {
  blob: Blob;
  content_type: "image/jpeg" | "image/png";
  width: number;
  height: number;
}

async function encodeAtScale(
  source: DecodedImage,
  maxSide: number,
  quality: number,
  sourceType: string,
): Promise<Encoded> {
  const { w, h } = sizeOf(source);
  if (!w || !h) {
    throw new PhotoPrepError(
      "decode",
      "사진 크기를 읽지 못했어요 — 파일이 손상됐을 수 있어요. 다른 사진으로 올려주세요.",
    );
  }
  // 원본이 이미 작으면 키우지 않는다(확대는 화질만 버리고 용량을 늘린다).
  const scale = Math.min(1, maxSide / Math.max(w, h));
  const width = Math.max(1, Math.round(w * scale));
  const height = Math.max(1, Math.round(h * scale));

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (!ctx) {
    throw new PhotoPrepError(
      "encode",
      "브라우저가 사진을 처리하지 못했어요 — 탭을 새로고침한 뒤 다시 시도해주세요.",
    );
  }
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(source, 0, 0, width, height);

  const keepAlpha = ALPHA_CAPABLE.test(sourceType) && hasTransparency(ctx, width, height);
  const content_type = keepAlpha ? "image/png" : "image/jpeg";
  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, content_type, content_type === "image/jpeg" ? quality : undefined),
  );
  if (!blob) {
    throw new PhotoPrepError(
      "encode",
      "사진을 저장 형식으로 바꾸지 못했어요 — 탭을 새로고침한 뒤 다시 시도해주세요.",
    );
  }
  return { blob, content_type, width, height };
}

/** 투명 픽셀이 하나라도 있나. 있으면 JPEG(검은 배경)로 접으면 안 된다. */
function hasTransparency(ctx: CanvasRenderingContext2D, width: number, height: number): boolean {
  let data: Uint8ClampedArray;
  try {
    data = ctx.getImageData(0, 0, width, height).data;
  } catch {
    // 캔버스가 오염된 경우(정상 경로에선 로컬 파일이라 발생하지 않는다) — 모른다면 알파를
    // 살리는 쪽(PNG)이 안전하다. 검은 사각형보다 큰 파일이 낫다.
    return true;
  }
  for (let i = 3; i < data.length; i += 4) if (data[i] < 255) return true;
  return false;
}

async function toPrepared(enc: Encoded, sourceBytes: number): Promise<PreparedPhoto> {
  return {
    base64: await blobToBase64(enc.blob),
    content_type: enc.content_type,
    bytes: enc.blob.size,
    width: enc.width,
    height: enc.height,
    source_bytes: sourceBytes,
  };
}

/**
 * Blob → base64(접두사 제외). FileReader.readAsDataURL을 쓰는 이유: 바이트를 직접 돌며
 * btoa용 문자열을 만들면 큰 배열에서 스택을 넘기거나(String.fromCharCode(...arr)) 느려진다.
 */
function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const s = typeof reader.result === "string" ? reader.result : "";
      const comma = s.indexOf(",");
      if (comma < 0) {
        reject(
          new PhotoPrepError(
            "encode",
            "사진을 전송 형식으로 바꾸지 못했어요 — 다시 시도해주세요.",
          ),
        );
        return;
      }
      resolve(s.slice(comma + 1));
    };
    reader.onerror = () =>
      reject(
        new PhotoPrepError("encode", "사진을 읽는 중 문제가 생겼어요 — 다시 시도해주세요."),
      );
    reader.readAsDataURL(blob);
  });
}
