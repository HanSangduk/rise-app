"""인바디 결과지 앵커 파싱 프로토타입 v2 — Dart(ML Kit) 이식 전 규칙 검증.

입력: ocr.swift가 뽑은 TSV(conf, x, y, w, h, text — 좌표 0~1, y는 아래가 0).

규칙(전부 "인바디 결과지의 구조적 속성"으로 정당화 — 특정 장 좌표 하드코딩 금지):
  R1  라벨 앵커는 한글만 남긴 문자열의 **완전일치**(체중/골격근량/체지방량/체지방률).
      기초대사·내장지방은 접두일치(량/랑 오독 허용). 포함매칭 금지 —
      체중조절·적정체중·체지방률ㅁ표준 같은 파생 라벨이 전부 함정이다.
  R2  신체변화(히스토리) 섹션 헤더 아래·오른쪽의 앵커는 버린다 — 과거 측정값 열이다.
  R3  기울기 보정: 앵커 주변(세로 ±0.13)에서 세로로 겹치는 토큰쌍의 기울기 중앙값 =
      지역 기울기. 사진은 원근 때문에 페이지 좌/우 기울기가 다르므로 전역값은 폴백만.
  R4  값 후보의 타입 강제: kg·% 지표는 소수 1자리 인쇄(눈금·비만도117%·"100점" 문장 배제),
      BMR은 정수(제지방량 62.5 배제). 후보 단계에서 필드 범위도 즉시 적용.
  R5  값 후보의 순수성: 한글 포함 토큰은 값이 아니다(라벨/체크박스/문장).
      단위(kg·kcal·cm·%) 제거 후 라틴 문자 2개 초과도 배제. 날짜/시각 패턴 배제.
  R6  기하 A(같은 줄 + 표준범위): 기울기 보정 후 앵커 박스와 세로 겹침 ≥ 0.35·min(h),
      토큰 자체나 바로 오른쪽 토큰에 (L~H)가 붙은 값. 실측 같은 줄 겹침은 61~89%,
      이웃 행은 0 이하 — 겹침이 중심거리보다 노이즈에 2배 강하다. 겹침 최대를 취하되
      값이 다른 2위가 0.15 이내로 붙으면 모호 — 빈칸. 범위 정합 0.5L ≤ V ≤ 1.6H
      실패 시 폐기(오독 검출). 범위 없는 같은 줄 숫자는 **절대 채택 안 함** — 눈금 줄이다.
  R7  기하 B(게이지 바 끝 값): 라벨 중심선 **아래** 0.10~1.5 라벨높이, 중심 x거리 ≤0.45.
      다섯 장 전 형식 공통: 값은 라벨선 아래 0.25~1.05h, 눈금은 라벨선 위·근처,
      다음 행 값은 -2.3h 밖 — 1.5h가 양쪽 모두에 마진을 준다.
  R7b 행 소유권: 후보 토큰의 줄(±0.9·max h) 왼쪽에 앵커가 아닌 다른 한글 라벨이 있으면
      그 라벨의 행에 속한 값이다 — 배제. (이웃 행 값이 B밴드에 미끄러지는 사고의 방어:
      스트레스 테스트에서 smm←bfm 15.3, bmr←권장섭취열량 2166 실측.)
  R8  같은 앵커에 범위형(A) 후보가 하나라도 있으면 B 금지 — 그 줄은 요약/연구 행이고
      B밴드에 걸리는 건 이웃 행(적정체중 67.7kg 실측)이다. A 실패 시 다음 앵커로 폴백.
      토큰에 범위가 붙어 있는데 정합 실패면 **모든 기하에서** 그 토큰 배제(오독 확정).
  R9  소수점 복원: 토큰 내 "32. 5"→32.5, 인접 토큰 "32."+"5" 병합(세로 겹침+간격<0.025).
      게이지 바 글리프가 '1'로 붙은 "135.2" 는 범위 초과 시 선행 1 제거(35.2) 시도.
  R10 B 후보가 2개 이상이고 높이가 비등(12% 이내)한데 값이 다르면 **빈칸** — 모호성은 버린다.
  R11 검증: 서버 v2.9 범위 + 교차(smm<w, bfm<w, smm+bfm≤w) + 항등(|bfm−w·pbf/100| 허용오차).
      항등 실패 시 w가 100~200이면 선행 1 제거 재시도(바 글리프 붙은 체중), 그래도 실패면
      w·bfm·pbf 셋 다 버린다 — 셋 중 누가 틀렸는지 모른다.
"""
import re
import statistics

RANGES = {  # 서버 measurement.go와 동일
    'weight': (20, 300), 'smm': (5, 120), 'bfm': (1, 200),
    'pbf': (1, 70), 'vfl': (1, 30), 'bmr': (500, 5000),
}
TRUTH = {
    'sheet1': dict(weight=72.5, smm=35.6, bfm=10.0, pbf=13.7, vfl=3, bmr=1721, date='2026-05-26'),
    'sheet2': dict(weight=71.3, smm=35.2, bfm=9.8, pbf=13.7, vfl=4, bmr=1699, date='2026-05-18'),
    'sheet3': dict(weight=68.6, smm=33.8, bfm=9.3, pbf=13.5, vfl=None, bmr=None, date=None),
    'sheet4': dict(weight=72.7, smm=32.5, bfm=15.3, pbf=21.0, vfl=6, bmr=1610, date='2022-10-21'),
    'sheet5': dict(weight=73.3, smm=32.7, bfm=15.7, pbf=21.5, vfl=6, bmr=1614, date=None),
}

HANGUL = re.compile(r'[가-힣ㄱ-ㅎㅏ-ㅣ]')
DEC = re.compile(r'\d{1,4}\.\d{1,2}')          # 소수 1~2자리 (kg/% 지표)
INT = re.compile(r'(?<![\d.])\d{3,4}(?![\d.])')  # 정수 3~4자리 (BMR)
RG = re.compile(r'(\d{1,4}(?:\.\d{1,2})?)\s*~\s*(\d{1,4}(?:\.\d{1,2})?)')
DATE_LIKE = re.compile(r'\d{2,4}\.\s?\d{1,2}\.\s?\d{1,2}|\d{1,2}:\d{2}')


def load(path):
    toks = []
    for line in open(path):
        p = line.rstrip('\n').split('\t')
        if len(p) < 6:
            continue
        toks.append(dict(conf=float(p[0]), x=float(p[1]), y=float(p[2]),
                         w=float(p[3]), h=float(p[4]), text=p[5]))
    return toks


def cx(t): return t['x'] + t['w'] / 2
def cy(t): return t['y'] + t['h'] / 2


def yoverlap(a, b):
    return min(a['y'] + a['h'], b['y'] + b['h']) - max(a['y'], b['y'])


def fix_spaces(s):
    """R9: Vision이 소수점 뒤에 공백을 끼운다("32. 5", "( 26. 5~32. 5 )")."""
    s = s.replace(',', '.')
    prev = None
    while prev != s:
        prev = s
        s = re.sub(r'(\d)\.\s+(\d)', r'\1.\2', s)
    return s


def merge_split_decimals(toks):
    """R9: "32." + "5" 두 토큰으로 쪼개진 소수 복원(세로 겹침 + x간격 < 0.025)."""
    toks = sorted(toks, key=lambda t: (t['x']))
    used = set()
    out = []
    for i, a in enumerate(toks):
        if id(a) in used:
            continue
        ta = a['text'].strip()
        m = re.fullmatch(r'.*?(\d{1,4})[.,]', ta)
        if m:
            for b in toks[i + 1:]:
                if id(b) in used:
                    continue
                gap = b['x'] - (a['x'] + a['w'])
                if gap > 0.025:
                    break
                if gap < -0.01:
                    continue
                if not re.fullmatch(r'\d{1,2}', b['text'].strip()):
                    continue
                if yoverlap(a, b) < 0.5 * min(a['h'], b['h']):
                    continue
                y0 = min(a['y'], b['y'])
                y1 = max(a['y'] + a['h'], b['y'] + b['h'])
                out.append(dict(conf=min(a['conf'], b['conf']),
                                x=a['x'], y=y0, w=b['x'] + b['w'] - a['x'], h=y1 - y0,
                                text=ta + b['text'].strip()))
                used.add(id(a)); used.add(id(b))
                break
        if id(a) not in used:
            out.append(a)
    return out


def norm_hangul(s):
    return ''.join(re.findall(r'[가-힣]', s))


def estimate_slope(toks, cy0=None, cx0=None, fallback=0.0):
    """R3: 같은 인쇄 줄 토큰쌍 기울기의 중앙값, 2-패스.
    1차: 근거리(dx 0.015~0.07)만 — 전단 변위가 줄 간격(≥1.5h)을 못 넘어 겹침 판정이
         아직 유효한 구간. (원거리 겹침 판정은 강한 기울기에서 남의 줄과 겹쳐 오염된다.)
    2차: 1차 값으로 deskew한 뒤 원거리(dx 0.03~0.35) 페어로 정밀화."""
    if cy0 is not None:
        sel = [t for t in toks if abs(cy(t) - cy0) < 0.13 and abs(cx(t) - cx0) < 0.60]
    else:
        sel = toks

    def collect(lo, hi, skew, minov):
        out = []
        for i, a in enumerate(sel):
            for b in sel[i + 1:]:
                dx = cx(b) - cx(a)
                if not (lo < abs(dx) < hi):
                    continue
                bb = dict(b, y=b['y'] - skew * dx)
                if yoverlap(a, bb) < minov * min(a['h'], b['h']):
                    continue
                out.append((cy(bb) - cy(a)) / dx + skew)
        return out
    s1 = collect(0.015, 0.07, 0.0, 0.25)
    if len(s1) < 6:
        return fallback
    m1 = statistics.median(s1)
    s2 = collect(0.03, 0.35, m1, 0.45)
    m = statistics.median(s2) if len(s2) >= 6 else m1
    if cy0 is not None:
        # 지역 추정은 표본이 적어 노이즈에 튄다 — 전역 ±0.04로 클램프
        # (원근에 의한 페이지 내 기울기 변화 실측: sheet5에서 -0.034 ~ +0.014)
        m = max(fallback - 0.04, min(fallback + 0.04, m))
    else:
        m = max(-0.12, min(0.12, m))   # 물리 한계(~7°) — 그 이상은 재촬영 영역
    return m


def find_anchors(toks, label, prefix=False):
    """R1 + R2 + R2b."""
    hist = [t for t in toks if norm_hangul(t['text']).startswith('신체변화')]
    out = []
    for t in toks:
        n = norm_hangul(t['text'])
        ok = (n.startswith(label) and len(n) <= len(label) + 1) if prefix else (n == label)
        if not ok:
            continue
        # R2: 신체변화 헤더 아래+같은 패널(헤더 왼쪽끝-0.05 오른쪽)이면 과거값 열
        if any(cy(t) < cy(h) and t['x'] > h['x'] - 0.05 for h in hist):
            continue
        out.append(t)
    out.sort(key=lambda t: -t['y'])   # 위(주 섹션) 우선
    # R2b: 페이지(토큰 구름) 하단 15%의 앵커는 무조건 배제 — 전 형식에서 신체변화
    #      히스토리 표가 페이지 바닥에 온다. 신체변화 헤더가 OCR에서 누락돼 R2가
    #      못 걸러도 이걸로 걸린다. 주 섹션 앵커는 실측 전부 스팬 42% 위였다.
    ys = [cy(t) for t in toks]
    cut = min(ys) + 0.15 * (max(ys) - min(ys))
    return [t for t in out if cy(t) >= cut]


def token_pure(text):
    """R5: 값 토큰의 순수성."""
    if HANGUL.search(text):
        return False
    if DATE_LIKE.search(text):
        return False
    s = re.sub(r'kcal|kg|cm|mm|%', '', text, flags=re.I)
    if len(re.findall(r'[A-Za-z]', s)) > 2:
        return False
    return True


def parse_value_token(text, field):
    """토큰 → (값, 범위(L,H) 또는 None, 복원여부). 값이 못 되면 (None, ...)."""
    s = fix_spaces(text)
    head = s.split('(')[0]
    rng = None
    m = RG.search(s[len(head):]) if '(' in s else None
    if m:
        rng = (float(m.group(1)), float(m.group(2)))
    if '~' in head:          # 표준범위 단독 토큰 — 값 아님
        return None, (RG.search(s) and (float(RG.search(s).group(1)),
                                        float(RG.search(s).group(2)))), False
    lo, hi = RANGES[field]
    repaired = False
    if field == 'bmr':
        vals = [float(v) for v in INT.findall(head) if not DEC.search(head)]
        vals = [v for v in vals if lo <= v <= hi]
    else:
        vals = []
        for ds in DEC.findall(head):
            v = float(ds)
            if lo <= v <= hi:
                vals.append(v)
            elif v > hi and ds[0] == '1' and lo <= float(ds[1:]) <= hi:
                vals.append(float(ds[1:]))   # R9: 게이지 바 '|'→'1' 접착 복원
                repaired = True
    vals = sorted(set(vals))
    if len(vals) != 1:       # 값 0개 또는 모호(2개 이상) — 버린다
        return None, rng, False
    return vals[0], rng, repaired


def bare_range(text):
    """"( 26. 5~32. 5 )" / "52.8~71.4" 같은 범위 단독 토큰."""
    s = fix_spaces(text)
    if '~' not in s or HANGUL.search(s):
        return None
    m = RG.search(s)
    if not m:
        return None
    if re.sub(r'[\d.,~()\s%]|kg|kcal|cm', '', s, flags=re.I):
        return None
    return float(m.group(1)), float(m.group(2))


def range_consistent(v, rng):
    """R6: 값-표준범위 정합. 인바디 표준범위는 인구 통계라 실측이 크게 못 벗어난다."""
    lo, hi = rng
    return 0 < lo < hi and 0.5 * lo <= v <= 1.6 * hi


def hangul_labels(toks):
    """행 소유권 판정용 라벨 토큰: 한글 2자 이상이면 라벨/체크박스/문장 — 값이 아니다."""
    return [t for t in toks if len(norm_hangul(t['text'])) >= 2]


def owned_by_other(t, anchor, labels, slope):
    """R7b: 후보 t의 줄에서 **가장 가까운 왼쪽** 한글 라벨이 앵커가 아니면 남의 행 값.
    최근접 규칙인 이유: 설명문("체수분...합하면", "남은 에너지를...")은 라벨보다
    항상 왼쪽에 있다 — 라벨은 자기 값 바로 옆에 인쇄된다(인바디 조판 속성)."""
    owner, ox = None, -1.0
    for L in labels:
        if L['x'] >= t['x']:
            continue
        dxc = cx(t) - cx(L)
        if dxc > 0.55:
            continue
        dy = (cy(t) - cy(L)) - slope * dxc
        if abs(dy) <= 0.75 * max(L['h'], t['h']) and L['x'] > ox:
            owner, ox = L, L['x']
    return owner is not None and owner is not anchor


def anchor_value(toks, anchor, field, gslope, labels):
    """R6~R8, R10: 한 앵커에서 값 시도. 실패면 None(다음 앵커로)."""
    slope = estimate_slope(toks, cy(anchor), cx(anchor), gslope)
    acands, bcands, saw_arange = [], [], False
    for t in toks:
        if t is anchor or t['x'] < anchor['x'] or cx(t) <= cx(anchor):
            continue
        dxc = cx(t) - cx(anchor)
        if dxc > 0.55:
            continue
        dy = (cy(t) - cy(anchor)) - slope * dxc          # 보정된 중심 y 차
        # R6: 기울기 보정 후 박스 세로 겹침 비율
        ov = (min(anchor['y'] + anchor['h'], t['y'] + t['h'] - slope * dxc)
              - max(anchor['y'], t['y'] - slope * dxc)) / min(anchor['h'], t['h'])
        in_a = ov >= 0.45
        in_b = -1.5 * anchor['h'] <= dy <= -0.10 * anchor['h']
        if not (in_a or in_b) or not token_pure(t['text']):
            continue
        if owned_by_other(t, anchor, labels, slope):
            continue            # R7b: 남의 행 값 (A·B 공통)
        v, rng, repaired = parse_value_token(t['text'], field)
        if v is None:
            continue
        if rng and not range_consistent(v, rng):
            if in_a:
                saw_arange = True   # 범위형 줄 증거는 남긴다(B 금지용)
            continue                # R8: 붙은 범위와 안 맞으면 오독 확정 — 전면 배제
        if rng is None and in_a:
            # 같은 줄 + 바로 옆 범위 토큰(간격 -0.04~0.10, 세로 겹침)이면 범위형
            for r in toks:
                rr = bare_range(r['text'])
                if not rr:
                    continue
                gap = r['x'] - (t['x'] + t['w'])
                if -0.04 < gap < 0.10 and yoverlap(t, r) >= 0.4 * min(t['h'], r['h']):
                    rng = rr
                    break
            if rng and not range_consistent(v, rng):
                saw_arange = True
                continue
        if in_a and rng:
            saw_arange = True
            acands.append((ov, v))
        elif in_b and dxc <= 0.45:
            bcands.append((t['h'], v))
    if acands:
        acands.sort(reverse=True)
        ov0, v0 = acands[0]
        for ov, v in acands[1:]:
            if ov >= ov0 - 0.15 and abs(v - v0) > 0.05:
                return None   # R6: 겹침 비등한 다른 값 — 모호, 버린다
        return v0
    if saw_arange:       # R8: 범위형 줄인데 정합 실패 — 이 앵커 포기(B 금지)
        return None
    if bcands:
        bcands.sort(reverse=True)
        h0, v0 = bcands[0]
        for h, v in bcands[1:]:
            if h > 0.88 * h0 and abs(v - v0) > 0.05:
                return None   # R10: 비등한 후보 2개 — 모호, 버린다
        return v0
    return None


def below_value(toks, anchor, gslope):
    """VFL. 값의 자리는 셋 중 하나(전 형식 실측):
      (1) 'N레벨' 결합 토큰 — 최우선.
      (2) 앵커 같은 줄 오른쪽, x오프셋 ≤ 0.18 (연구항목 행 형식).
      (3) 앵커 아래 0.4~2.2h, x오프셋 ≤ 0.12 (게이지 왼쪽 열 형식).
    게이지 눈금 '10'은 x오프셋 0.21+ — x오프셋 캡이 구조적 방어다."""
    slope = estimate_slope(toks, cy(anchor), cx(anchor), gslope)
    ay = anchor['y']
    region = [t for t in toks if t is not anchor
              and ay - 0.075 < t['y'] < ay + anchor['h']
              and -0.02 < t['x'] - anchor['x'] < 0.25]
    for t in region:
        s = t['text'].replace(' ', '')
        m = re.search(r'(\d{1,2})레벨', s)
        if m and 1 <= int(m.group(1)) <= 30:
            return float(m.group(1))
    cands = []
    for t in region:
        s = fix_spaces(t['text'])
        if '~' in s or HANGUL.search(s):
            continue
        xoff = t['x'] - anchor['x']
        dy = (cy(t) - cy(anchor)) - slope * (cx(t) - cx(anchor))
        on_line = abs(dy) <= 0.6 * max(anchor['h'], t['h']) and xoff <= 0.18
        below = -2.2 * anchor['h'] <= dy <= -0.4 * anchor['h'] and xoff <= 0.12
        if not (on_line or below):
            continue
        for m in re.findall(r'(?<![\d.])(\d{1,2})(?![\d.])', s):
            v = float(m)
            if 1 <= v <= 30:
                cands.append((abs(xoff), v))
    return sorted(cands)[0][1] if cands else None


def extract(toks):
    toks = merge_split_decimals(toks)
    gslope = estimate_slope(toks)
    labels = hangul_labels(toks)
    got = {}
    specs = [
        ('weight', '체중', False),
        ('smm', '골격근량', False),
        ('bfm', '체지방량', False),
        ('pbf', '체지방률', False),
        ('bmr', '기초대사', True),   # 량/랑 오독 허용(접두)
    ]
    for key, label, prefix in specs:
        for a in find_anchors(toks, label, prefix):
            v = anchor_value(toks, a, key, gslope, labels)
            if v is not None:
                got[key] = v
                break
    for a in find_anchors(toks, '내장지방', True) or find_anchors(toks, '내장지방레벨', True):
        v = below_value(toks, a, gslope)
        if v is not None:
            got['vfl'] = v
            break
    for t in toks:
        m = re.search(r'(20\d{2})[.\s]+(\d{1,2})[.\s]+(\d{1,2})', t['text'])
        if m:
            got['date'] = f"{m.group(1)}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
            break
    return got


def validate(got):
    """R11: 검증 실패 필드는 버린다 — 틀린 프리필은 빈 칸보다 나쁘다."""
    dropped = []
    for k, (lo, hi) in RANGES.items():
        if k in got and not (lo <= got[k] <= hi):
            dropped.append((k, got.pop(k), '범위'))
    w = got.get('weight')
    if w:
        if 'smm' in got and got['smm'] >= w:
            dropped.append(('smm', got.pop('smm'), 'smm>=w'))
        if 'bfm' in got and got['bfm'] >= w:
            dropped.append(('bfm', got.pop('bfm'), 'bfm>=w'))
        if 'smm' in got and 'bfm' in got and got['smm'] + got['bfm'] > w:
            dropped.append(('smm+bfm', (got['smm'], got['bfm']), '합>w — 양쪽 모두 보류'))
            got.pop('smm'); got.pop('bfm')
        if 'bfm' in got and 'pbf' in got:
            def iderr(wv):
                return abs(got['bfm'] - wv * got['pbf'] / 100)
            tol = max(0.8, 0.08 * w * got['pbf'] / 100)
            if iderr(w) > tol:
                # 바 글리프 '1' 접착 체중(1xx.x) 복원 시도 — 항등이 검증자
                if 100 < w < 200 and iderr(w - 100) <= max(0.8, 0.08 * (w - 100) * got['pbf'] / 100):
                    dropped.append(('weight', w, f'항등 복원 {w}→{w - 100}'))
                    got['weight'] = w - 100
                else:
                    dropped.append(('w·bfm·pbf', (w, got['bfm'], got['pbf']),
                                    '항등 불일치 — 셋 다 보류'))
                    got.pop('weight'); got.pop('bfm'); got.pop('pbf')
    return got, dropped


total_ok = total_wrong = total_blank = 0
for name in ('sheet1', 'sheet2', 'sheet3', 'sheet4', 'sheet5'):
    toks = load(f'{name}.tsv')
    raw = extract(toks)
    got, dropped = validate(dict(raw))
    truth = TRUTH[name]
    print(f'\n=== {name}')
    for k in ('weight', 'smm', 'bfm', 'pbf', 'vfl', 'bmr', 'date'):
        t, g = truth.get(k), got.get(k)
        if t is None:
            mark = '·장에 없음' + (f' (오추출! {g})' if g is not None and k != 'date' else '')
            if g is not None and k != 'date':
                total_wrong += 1
        elif g is None:
            mark = f'빈칸 (정답 {t})'
            total_blank += 1
        elif (k == 'date' and g == t) or (k != 'date' and abs(g - t) < 0.05):
            mark = f'✓ {g}'
            total_ok += 1
        else:
            mark = f'✗ {g} (정답 {t})  ← 틀린 프리필!'
            total_wrong += 1
        print(f'  {k:7} {mark}')
    for d in dropped:
        print(f'  [검증이 버림] {d}')

print(f'\n총계: 정확 {total_ok} · 빈칸(안전) {total_blank} · 틀린 프리필(위험) {total_wrong}')
