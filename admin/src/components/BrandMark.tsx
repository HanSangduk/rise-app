// 라이즈 R 마크(P19) — design/brand/rise-mark.svg(소스 오브 트루스)의 지오메트리를 그대로
// 옮긴 컴포넌트. 화면·인쇄물에 얹는 "배경 없는 마크"는 전부 여기서 그린다.
// 파비콘(public/favicon.svg)과 파일을 공유하지 않는 이유: 파비콘은 크림 타일(둥근 사각형)
// 위 아이콘이라 배경·배치 파라미터가 다르다 — 용도가 갈리면 파일도 가른다(brand README의
// 마크/아이콘 분리와 같은 구도). 마크를 고치면 rise-mark.svg를 먼저 고치고 여기 path를
// 다시 복사할 것. 세 획과 점의 상대 위치가 마크의 정체성이므로 개별 요소를 옮기지 말 것.
//
// tone — 획 색만 다르고 베이지 점(#CEBBAA)은 공통이다(어느 바탕에서든 읽힌다):
//   brand  네이비 #3B4C60. 밝은 바탕용(인쇄물·크림 타일).
//   ivory  크림 #F6F4EF. 어드민 다크 패널용 — 네이비는 패널(#15161d)과 명도가 붙어 획이
//          가라앉는다(대비 ≈ 2:1). 크림은 브랜드 팔레트 안의 색이라 "마크를 앱 색으로 다시
//          칠하지 말 것"(brand README — 앱 레드 팔레트 금지) 규칙과 충돌하지 않는다.
export function BrandMark({
  size = 48,
  tone = "brand",
  className,
}: {
  /** 렌더 크기(px). viewBox가 마크에 밀착이라 여백 없이 이 크기로 그려진다. */
  size?: number;
  tone?: "brand" | "ivory";
  className?: string;
}) {
  return (
    <svg
      viewBox="112 106 196 202"
      width={size}
      height={size}
      className={className}
      // 항상 옆의 텍스트(RISE …)가 이름을 말하는 자리에 쓰인다 — 장식으로 선언해
      // 스크린리더가 "이미지"를 한 번 더 읽지 않게 한다.
      aria-hidden="true"
      focusable="false"
    >
      <g fill="none" stroke={tone === "ivory" ? "#F6F4EF" : "#3B4C60"} strokeWidth={21.5} strokeLinecap="round">
        <path
          d="M 127,164 C 137,143 158,124 182,121 C 190,120 202,120 210,122
             C 232,127 249,138 257,155 C 263,167 265,180 262,196
             C 259,214 251,228 240,238 C 231,245 221,249 206,249"
        />
        <path d="M 208,252 C 217,263 224,272 232,280 C 240,288 245,291 250,293" />
        <path d="M 159.5,290 L 159.5,214 Q 159.5,195.5 178,195.5 L 190,195.5 Q 197,196 201,198.5" />
      </g>
      <circle cx="287" cy="284.5" r="17" fill="#CEBBAA" />
    </svg>
  );
}
