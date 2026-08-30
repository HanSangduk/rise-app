# 데모 체형 사진 얼굴 가림(P46). 이 사진들은 **AI 생성**이라 실존 인물이 아니지만,
# 사람으로 읽히는 이상 스토어에 얼굴을 노출할 이유가 없다 — 픽셀레이트로 가린다.
#
# 자동 얼굴 검출을 쓰지 않는다: OpenCV 5는 Haar를 뺐고, 균일 배경 실루엣 검출은
# 벽 비네팅에 걸린다(실측). 4장뿐이고 촬영이 고정이라 **눈으로 확정한 정규화 좌표**가
# 가장 정확하고 재현 가능하다(좌표 근거: 원본 위 격자 오버레이로 판독).
#
# 재실행: <venv>/bin/python store/demo-photos/blur-faces.py  (원본에서만 1회 — 멱등 아님)
import cv2
import numpy as np
from pathlib import Path

SRC = Path(__file__).resolve().parent

# 파일 → (x0, x1, y0, y1) 정규화 머리 영역. 머리카락·턱까지 여유 포함.
HEADS = {
    "stand-front-before.jpg": (0.415, 0.595, 0.200, 0.330),
    "stand-front-after.jpg":  (0.415, 0.595, 0.050, 0.190),
    "stand-side-before.jpg":  (0.385, 0.570, 0.155, 0.300),
    "stand-side-after.jpg":   (0.415, 0.600, 0.105, 0.270),
}

for name, (fx0, fx1, fy0, fy1) in HEADS.items():
    p = SRC / name
    img = cv2.imread(str(p))
    h, w = img.shape[:2]
    x, y = int(w * fx0), int(h * fy0)
    fw, fh = int(w * (fx1 - fx0)), int(h * (fy1 - fy0))

    roi = img[y:y + fh, x:x + fw]
    # 픽셀레이트 후 가우시안 — 되돌릴 수 없는 수준으로.
    small = cv2.resize(roi, (max(1, fw // 16), max(1, fh // 16)), interpolation=cv2.INTER_LINEAR)
    pix = cv2.resize(small, (fw, fh), interpolation=cv2.INTER_NEAREST)
    pix = cv2.GaussianBlur(pix, (0, 0), sigmaX=fw * 0.05)

    # 타원 페더 합성 — 사각 자국을 남기지 않는다.
    mask = np.zeros((fh, fw), np.uint8)
    cv2.ellipse(mask, (fw // 2, fh // 2), (int(fw * 0.55), int(fh * 0.55)), 0, 0, 360, 255, -1)
    mask = cv2.GaussianBlur(mask, (0, 0), sigmaX=fw * 0.09)
    m3 = cv2.cvtColor(mask, cv2.COLOR_GRAY2BGR).astype(np.float32) / 255.0
    img[y:y + fh, x:x + fw] = (pix.astype(np.float32) * m3 + roi.astype(np.float32) * (1 - m3)).astype(np.uint8)

    cv2.imwrite(str(p), img, [cv2.IMWRITE_JPEG_QUALITY, 92])
    print(f"{name}: box=({x},{y},{fw},{fh})")
