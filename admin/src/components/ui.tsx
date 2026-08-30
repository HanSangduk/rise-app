// 경량 shadcn 스타일 프리미티브 — wodshot web(src/components/ui.tsx)에서 포팅 + 다크·레드 리테마.
// 색 토큰은 목업(목업_어드민_라이즈_2026-08-14.html)의 :root 변수와 1:1 매핑(src/index.css 참고).
import {
  type ButtonHTMLAttributes,
  type CSSProperties,
  type HTMLAttributes,
  type InputHTMLAttributes,
  type LabelHTMLAttributes,
  type ReactNode,
  type SelectHTMLAttributes,
  type TdHTMLAttributes,
  type TextareaHTMLAttributes,
  type ThHTMLAttributes,
  useEffect,
} from "react";
import { Loader2, RotateCw, X } from "lucide-react";
import { cn } from "@/lib/cn";

type Variant = "default" | "outline" | "ghost" | "danger";
type Size = "sm" | "md";

const variants: Record<Variant, string> = {
  default: "bg-brand text-white hover:bg-brand-2",
  outline: "border border-line bg-panel-2 text-ink hover:border-muted",
  ghost: "bg-transparent text-muted hover:bg-panel-2 hover:text-ink",
  danger: "bg-danger text-white hover:opacity-90",
};
const sizes: Record<Size, string> = {
  sm: "h-7 px-2.5 text-[11px] gap-1",
  md: "h-9 px-3.5 text-[12.5px] gap-1.5",
};

export function Button({
  variant = "default",
  size = "md",
  className,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; size?: Size }) {
  return (
    <button
      className={cn(
        "inline-flex items-center justify-center rounded-[9px] font-extrabold transition disabled:opacity-50 disabled:pointer-events-none",
        variants[variant],
        sizes[size],
        className,
      )}
      {...props}
    />
  );
}

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cn("rounded-[13px] border border-line bg-panel shadow-sm", className)} {...props} />
  );
}
export function CardHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("flex flex-wrap items-center justify-between gap-2 px-4 pt-3.5 pb-2", className)} {...props} />;
}
export function CardTitle({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("text-[13px] font-bold tracking-tight", className)} {...props} />;
}
export function CardContent({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("px-4 pb-4", className)} {...props} />;
}

type BadgeTone = "muted" | "ok" | "warn" | "danger" | "brand" | "blue";

export function Badge({
  tone = "muted",
  className,
  style,
  children,
}: {
  tone?: BadgeTone;
  className?: string;
  style?: CSSProperties;
  children: ReactNode;
}) {
  const tones: Record<BadgeTone, string> = {
    muted: "bg-panel-2 text-muted",
    ok: "bg-ok/15 text-ok",
    warn: "bg-warn/15 text-warn",
    danger: "bg-danger/15 text-danger",
    brand: "bg-brand/15 text-brand",
    blue: "bg-blue/15 text-blue",
  };
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2 py-0.5 text-[10.5px] font-extrabold",
        // style로 트레이너별 커스텀 색(hex)을 줄 때는 토큰 톤 클래스를 배경/글자색 모두 비워 충돌을 막는다.
        !style && tones[tone],
        className,
      )}
      style={style}
    >
      {children}
    </span>
  );
}

export function Table({ className, ...props }: HTMLAttributes<HTMLTableElement>) {
  return (
    <div className="overflow-x-auto">
      <table className={cn("w-full text-[12.5px]", className)} {...props} />
    </div>
  );
}
export function THead({ className, ...props }: HTMLAttributes<HTMLTableSectionElement>) {
  return <thead className={cn("text-left text-[10.5px] text-muted", className)} {...props} />;
}
export function TR({ className, ...props }: HTMLAttributes<HTMLTableRowElement>) {
  return <tr className={cn("border-b border-line/60", className)} {...props} />;
}
// 셀 props는 Th/TdHTMLAttributes로 받는다 — HTMLAttributes에는 colSpan이 없어 그룹 구분행
// (설정 화면의 "퇴사" 그룹 헤더)처럼 열을 합치는 정상 사용이 타입에서 막힌다.
export function TH({ className, ...props }: ThHTMLAttributes<HTMLTableCellElement>) {
  return <th className={cn("py-1.5 pr-3 font-bold", className)} {...props} />;
}
export function TD({ className, ...props }: TdHTMLAttributes<HTMLTableCellElement>) {
  return <td className={cn("py-1.5 pr-3 align-middle", className)} {...props} />;
}

export function Spinner({ label }: { label?: string }) {
  return (
    <div className="flex items-center justify-center gap-2 py-8 text-sm text-muted">
      <Loader2 className="h-4 w-4 animate-spin" /> {label ?? "불러오는 중…"}
    </div>
  );
}

export function EmptyState({ children }: { children: ReactNode }) {
  return (
    <div className="rounded-xl border border-dashed border-line py-10 text-center text-sm text-muted">
      {children}
    </div>
  );
}

// 조회 실패 패널. onRetry를 주면 "다시 시도" 버튼이 함께 뜬다.
//
// 버튼이 필요한 이유: 문구는 여러 곳에서 "새로고침 후 다시 시도"라고 말하는데 정작 누를 것이
// 하나도 없었다. 대표는 F5나 브라우저 새로고침 아이콘을 안내 없이 떠올리지 못하고, 설령
// 새로고침해도 화면 전체가 다시 그려져 보고 있던 자리를 잃는다 — 실패한 조회 하나만 다시
// 부르는 게 맞다. 같은 판단을 이미 BodyPhotoLightbox가 하고 있어(network 실패에만 재시도
// 버튼) 그 패턴을 공용 컴포넌트로 올린 것이다.
//
// onRetry는 선택값이다: 되돌릴 방법이 정말 없는 자리(권한 없음 등)에 죽은 버튼을 만들지 않는다.
export function ErrorState({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const msg = error instanceof Error ? error.message : String(error);
  return (
    <div className="rounded-xl border border-dashed border-danger/40 px-4 py-10 text-center text-sm text-danger">
      <p className="leading-relaxed">{msg}</p>
      {onRetry && (
        <Button variant="outline" size="sm" className="mt-3" onClick={onRetry}>
          <RotateCw className="h-3 w-3" /> 다시 시도
        </Button>
      )}
    </div>
  );
}

// 필터 · 스코프 선택용 알약 버튼(목업 .chip)
export function Chip({
  active,
  className,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { active?: boolean }) {
  return (
    <button
      type="button"
      className={cn(
        "m-0.5 inline-flex items-center rounded-full border px-2.5 py-1 text-[11px] transition",
        active
          ? "border-brand/40 bg-brand/15 font-extrabold text-brand"
          : "border-line bg-panel-2 text-muted hover:text-ink",
        className,
      )}
      {...props}
    />
  );
}

export function ProgressBar({
  value,
  className,
  barClassName,
}: {
  value: number;
  className?: string;
  barClassName?: string;
}) {
  const pct = Math.max(0, Math.min(100, value));
  return (
    <div className={cn("h-1.5 overflow-hidden rounded-full bg-panel-2", className)}>
      <div className={cn("h-full rounded-full bg-brand", barClassName)} style={{ width: `${pct}%` }} />
    </div>
  );
}

// 폼 요소 — 목업 input/select 스타일(10px 라운드, panel-2 배경)
export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        "w-full rounded-[10px] border border-line bg-panel-2 px-3 py-2 text-[13px] text-ink placeholder:text-muted",
        className,
      )}
      {...props}
    />
  );
}
export function Select({ className, ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cn("w-full rounded-[10px] border border-line bg-panel-2 px-3 py-2 text-[13px] text-ink", className)}
      {...props}
    />
  );
}
export function Textarea({ className, ...props }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      className={cn(
        "w-full rounded-[10px] border border-line bg-panel-2 px-3 py-2 text-[13px] text-ink placeholder:text-muted",
        className,
      )}
      {...props}
    />
  );
}
export function Label({ className, ...props }: LabelHTMLAttributes<HTMLLabelElement>) {
  return <label className={cn("mb-1 block text-[11px] text-muted", className)} {...props} />;
}

// 오버레이 다이얼로그 — 예약 생성 · 환불 계산기 · 회원 등록 등에서 재사용.
export function Modal({
  open,
  onClose,
  title,
  children,
  wide,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  wide?: boolean;
}) {
  // ESC로 닫기(접근성) — 훅은 조건부 return보다 앞에 있어야 하므로 open 가드는 리스너 안에서.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
      onClick={onClose}
      role="presentation"
    >
      <div
        className={cn(
          "max-h-[88vh] w-full overflow-y-auto rounded-2xl border border-line bg-panel p-5 shadow-xl",
          wide ? "max-w-2xl" : "max-w-md",
        )}
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <div className="mb-4 flex items-center justify-between gap-3">
          <h3 className="text-sm font-bold">{title}</h3>
          <button
            onClick={onClose}
            className="rounded-lg p-1 text-muted transition hover:bg-panel-2 hover:text-ink"
            aria-label="닫기"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}
