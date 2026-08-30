# 스토어용 캡션 프레임 이미지 생성(P46, ASO 2팀 교차검증 확정안).
# raw 스크린샷 → 크림 배경 + 상단 캡션 + 라운드 디바이스 목업 → final/{n}_{name}.png
#
# 사용: <scratchpad-venv>/bin/python store/screenshots/frame.py ios
#       <scratchpad-venv>/bin/python store/screenshots/frame.py android
# (pillow 필요 — venv는 세션 스크래치패드에 있음. 재현 시: python3 -m venv .venv && pip install pillow)
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
CREAM, NAVY, BEIGE = "#F6F4EF", "#3B4C60", "#CEBBAA"
FONT = str(ROOT / "app/assets/fonts/PretendardVariable.ttf")

# ASO 확정 순서·캡션 (metadata/play.md 표와 단일 진실 — 수정 시 양쪽 함께).
PLAN = [
    ("01_home",      "내 PT, 한 화면에",   "담당 코치·회원권·오늘 일정·홈워크까지"),
    ("02_booking",   "예약은 10초면 끝",   "코치 시간표 보고 원하는 시간 바로 예약"),
    ("04_inbody",    "몸의 변화가 그래프로", "체중·골격근량·체지방률 추이를 한눈에"),
    ("05_bodycheck", "같은 각도, 다른 몸",  "격자·수평계 가이드로 날짜별 비교"),
    ("03_records",   "오늘 수업, 다시 보기", "운동·중량·코치 메모까지 그대로"),
    ("06_my",        "회원권도 투명하게",   "잔여 회차·결제 내역·전자계약서 확인"),
    ("07_coaches",   "담당 코치와 함께",    "코치 프로필과 전문 분야 확인"),
]


def font(size, weight=800):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *img.size], radius=radius, fill=255)
    out = Image.new("RGBA", img.size)
    out.paste(img, (0, 0), mask)
    return out


def frame_one(raw: Image.Image, headline: str, sub: str, size: tuple[int, int]) -> Image.Image:
    W, H = size
    canvas = Image.new("RGB", (W, H), CREAM)
    d = ImageDraw.Draw(canvas)

    # 상단 캡션 밴드 — 헤드라인은 캔버스 폭 기준으로 크게(스토어 썸네일에서도 읽히게).
    hs = int(W * 0.075)   # 1320 → ≈99px
    ss = int(W * 0.032)
    hf, sf = font(hs, 800), font(ss, 500)
    hw = d.textlength(headline, font=hf)
    d.text(((W - hw) / 2, int(H * 0.045)), headline, font=hf, fill=NAVY)
    sw = d.textlength(sub, font=sf)
    d.text(((W - sw) / 2, int(H * 0.045) + hs + int(hs * 0.35)), sub, font=sf, fill=NAVY)

    # 디바이스 목업 — 스크린샷을 라운드+네이비 베젤로. 하단은 캔버스 밖으로 흘려
    # (풀 화면 느낌, 흔한 스토어 관행) 상단 캡션과 균형.
    shot_w = int(W * 0.86)
    scale = shot_w / raw.width
    shot = raw.resize((shot_w, int(raw.height * scale)), Image.LANCZOS)
    shot = rounded(shot, radius=int(W * 0.055))
    bezel = int(W * 0.012)
    dev = ImageOps.expand(shot.convert("RGB"), border=bezel, fill=NAVY)
    dev = rounded(dev, radius=int(W * 0.055) + bezel)
    x = (W - dev.width) // 2
    y = int(H * 0.045) + hs + int(hs * 0.35) + ss + int(H * 0.03)
    canvas.paste(dev, (x, y), dev)
    return canvas


def main(platform: str) -> None:
    raw_dir = ROOT / "store/screenshots" / platform / "raw"
    out_dir = ROOT / "store/screenshots" / platform / "final"
    out_dir.mkdir(parents=True, exist_ok=True)
    # 출력 크기 = 원본 스크린샷 크기 그대로(iOS 1320x2868 = 6.9" 요건 유지,
    # Android는 캡처 해상도 유지 — Play는 크기 자유).
    made = 0
    for i, (name, head, sub) in enumerate(PLAN, start=1):
        src = raw_dir / f"{name}.png"
        if not src.exists():
            print(f"skip(원본 없음): {src.name}")
            continue
        raw = Image.open(src).convert("RGB")
        img = frame_one(raw, head, sub, raw.size)
        out = out_dir / f"{i:02d}_{name[3:]}.png"
        img.save(out, optimize=True)
        made += 1
        print(f"ok: {out.relative_to(ROOT)}")
    print(f"done: {made}/{len(PLAN)}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "ios")
