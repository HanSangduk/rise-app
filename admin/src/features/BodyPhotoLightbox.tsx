import { useEffect, useState } from "react";
import { X } from "lucide-react";
import { BodyPhotoLoadError, loadBodyPhotoUrl } from "@/lib/bodyPhotoBlob";
import { formatMonthDay } from "@/lib/format";
import type { BodyPhoto } from "@/lib/types";

/**
 * 체형사진 원본 뷰어(P21).
 *
 * 그리드가 아니라 **여기서만** 원본을 받는다 — 업로드가 `no-store`라 브라우저 캐시가 듣지
 * 않아 자동 로드는 포즈당 수십 MB를 매번 다시 받는다.
 *
 * 실패는 세 갈래로 갈라 말한다. 특히 403은 **회원이 동의를 철회한 것**이 대표적 원인이고,
 * 이건 장애가 아니라 정상 동작이다 — 목록 API는 동의를 안 보고 내려주는데 Storage 규칙은
 * 보기 때문에 "목록은 뜨는데 사진만 안 열리는" 상태가 설계상 존재한다.
 */
export function BodyPhotoLightbox({
  photo,
  label,
  onClose,
}: {
  photo: BodyPhoto;
  label: string;
  onClose: () => void;
}) {
  const [url, setUrl] = useState<string | null>(null);
  const [error, setError] = useState<BodyPhotoLoadError | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let alive = true;
    setUrl(null);
    setError(null);
    loadBodyPhotoUrl(photo.storage_path)
      .then((u) => alive && setUrl(u))
      .catch((e) => {
        if (!alive) return;
        setError(
          e instanceof BodyPhotoLoadError
            ? e
            : new BodyPhotoLoadError("network", "사진을 불러오지 못했어요"),
        );
      });
    return () => {
      alive = false;
    };
  }, [photo.storage_path, attempt]);

  // Esc로 닫기 — 사진을 띄운 채 다른 회원 정보를 보려는 흐름을 막지 않는다.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-6"
      onClick={onClose}
    >
      <div
        className="max-h-full w-full max-w-[560px] overflow-hidden rounded-[14px] border border-line bg-panel"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-line px-4 py-2.5">
          <div className="text-[13px] font-bold">
            {label} · {formatMonthDay(photo.date)}
            {photo.blurred && (
              <span className="ml-2 text-[10.5px] font-normal text-muted">배경 블러됨</span>
            )}
          </div>
          <button type="button" onClick={onClose} className="text-muted hover:text-ink">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="flex min-h-[280px] items-center justify-center p-3">
          {url ? (
            <img
              src={url}
              alt={`${label} ${photo.date}`}
              className="max-h-[70vh] w-auto rounded-[10px]"
            />
          ) : error ? (
            <div className="px-6 text-center">
              <p
                className={`text-[12px] ${
                  error.kind === "forbidden" ? "text-warn" : "text-danger"
                }`}
              >
                {error.message}
              </p>
              {error.kind === "network" && (
                <button
                  type="button"
                  onClick={() => setAttempt((n) => n + 1)}
                  className="mt-2 text-[11.5px] font-bold text-accent underline"
                >
                  다시 시도
                </button>
              )}
            </div>
          ) : (
            <p className="text-[11.5px] text-muted">사진을 불러오는 중…</p>
          )}
        </div>

        <p className="border-t border-line px-4 py-2 text-[10.5px] text-muted">
          민감정보(P8)입니다 — 화면을 공유하거나 내려받아 보관하지 마세요.
        </p>
      </div>
    </div>
  );
}
