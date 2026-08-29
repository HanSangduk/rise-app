"""P20 파서 이식 검증 픽스처 생성기.

design/inbody-ocr/README.md의 함정 표 각 행을 합성 토큰 TSV로 만들어
app/test/.../fixtures/inbody/ 에 쓰고, 같은 TSV를 참조 구현(parse.py)에 돌려
기대 출력을 찍는다. Dart 테스트는 같은 TSV를 로드해 같은 출력을 단언한다
("참조 구현과 같은 입력 → 같은 출력").
"""
import os

REF = '/Users/straram/development/2026-06-workout-app/ptdesk/design/inbody-ocr/parse.py'
OUT = '/Users/straram/development/2026-06-workout-app/ptdesk/app/test/features/records/domain/fixtures/inbody'

# parse.py는 모듈 하단에서 sheet*.tsv를 즉시 읽는다 — 그 앞까지만 exec.
src = open(REF).read()
src = src[:src.index('total_ok =')]
ref = {}
exec(src, ref)

H = 0.02


def tok(text, x, y, w=None, h=H):
    if w is None:
        w = 0.013 * max(len(text), 1)
    return [0.9, x, y, w, h, text]


def arow(label, y, val, rng, val_x=0.30, rng_x=0.36):
    """요약행(A형): 라벨 | (kg) | 값 | (L~H)."""
    lw = 0.013 * len(label)
    return [
        tok(label, 0.06, y, w=lw),
        tok('(kg)', 0.06 + lw + 0.006, y, w=0.03, h=0.015),
        tok(val, val_x, y, w=0.05),
        tok(rng, rng_x, y, w=0.09, h=0.016),
    ]


def slant_row(label, y0, val, rng, m):
    """기울기 m의 행 — 각 토큰 중심이 라벨 중심을 지나는 기울기 m 직선 위.

    값을 라벨에서 멀리(x 0.42) 두는 이유: 기울기 보정이 실제로 판가름 나게 —
    전단 변위(m×dx)가 A 겹침(0.45)과 B 밴드(1.5h)를 **둘 다** 벗어나야
    보정 없인 값을 못 찾는다(보정을 죽인 뮤테이션이 이 픽스처에서 잡히게).
    """
    lw = 0.013 * len(label)
    lcx = 0.06 + lw / 2
    lcy = y0 + H / 2
    out = [tok(label, 0.06, y0, w=lw)]
    for text, x, w, h in [
        ('(kg)', 0.06 + lw + 0.006, 0.03, 0.015),
        (val, 0.42, 0.05, H),
        (rng, 0.472, 0.08, 0.016),
    ]:
        cx = x + w / 2
        cy = lcy + m * (cx - lcx)
        out.append(tok(text, x, cy - h / 2, w=w, h=h))
    return out


def standard():
    T = []
    T += [tok('인바디', 0.35, 0.95), tok('결과지', 0.44, 0.95)]
    T += [tok('2026.05.26. 14:23', 0.60, 0.92, w=0.14, h=0.015)]
    T += [tok('체형점수', 0.55, 0.86), tok('100점', 0.68, 0.86)]
    T += [tok('체성분분석', 0.06, 0.86, h=0.018)]
    T += arow('체중', 0.80, '72.5', '(55.8~75.4)')
    T += arow('골격근량', 0.74, '35.6', '(26.5~32.5)')
    T += arow('체지방량', 0.68, '10.0', '(10.8~17.3)')
    T += [tok('비만분석', 0.06, 0.60, h=0.018)]
    T += arow('BMI', 0.56, '23.1', '(18.5~24.9)')
    T += arow('체지방률', 0.52, '13.7', '(10.0~20.0)')
    T += arow('비만도', 0.48, '117', '(90~110)')
    T += [tok('연구항목', 0.06, 0.40, h=0.018)]
    T += arow('제지방량', 0.36, '62.5', '(53.1~64.9)')
    T += arow('기초대사량', 0.32, '1721', '(1573~1869)')
    T += [tok('내장지방레벨', 0.06, 0.28), tok('3', 0.17, 0.28, w=0.012)]
    T += [tok('권장섭취열량', 0.06, 0.24), tok('2166', 0.30, 0.24, w=0.05)]
    T += [tok('체중조절', 0.06, 0.18)]
    T += [tok('적정체중', 0.06, 0.155), tok('67.6', 0.30, 0.155, w=0.05),
          tok('kg', 0.36, 0.155, w=0.025)]
    T += [tok('신체변화', 0.05, 0.12)]
    T += [tok('체중', 0.06, 0.08), tok('69.9', 0.15, 0.08, w=0.05),
          tok('71.3', 0.22, 0.08, w=0.05)]
    T += [tok('골격근량', 0.06, 0.05), tok('33.1', 0.15, 0.05, w=0.05),
          tok('34.9', 0.22, 0.05, w=0.05)]
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def slant():
    m = -0.10
    T = [tok('체성분분석', 0.06, 0.90, h=0.018)]
    T += slant_row('체중', 0.80, '72.5', '(55.8~75.4)', m)
    T += slant_row('골격근량', 0.765, '35.2', '(26.5~32.5)', m)
    T += slant_row('체지방량', 0.73, '15.3', '(10.8~17.3)', m)
    T += slant_row('체지방률', 0.695, '21.0', '(10.0~20.0)', m)
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def gauge():
    T = [tok('체성분', 0.30, 0.92)]
    T += [tok('체중', 0.06, 0.80), tok('73.3', 0.10, 0.775, w=0.05)]
    for i, s in enumerate(('55', '70', '85', '100')):
        T += [tok(s, 0.30 + 0.08 * i, 0.80, w=0.013 * len(s), h=0.014)]
    T += [tok('골격근량', 0.06, 0.70), tok('32.7', 0.10, 0.678, w=0.05),
          tok('55', 0.16, 0.685, w=0.026)]
    T += [tok('체지방량', 0.06, 0.60), tok('15.7', 0.10, 0.575, w=0.05)]
    T += [tok('체지방률', 0.06, 0.50), tok('21.5', 0.10, 0.475, w=0.05)]
    T += [tok('기초대사량', 0.06, 0.40), tok('1614', 0.10, 0.375, w=0.05)]
    T += [tok('내장지방', 0.06, 0.30), tok('6', 0.07, 0.27, w=0.012),
          tok('10', 0.27, 0.30, w=0.026, h=0.014)]
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def bar_glyph():
    T = [tok('체성분분석', 0.06, 0.90, h=0.018)]
    T += [tok('체중', 0.06, 0.80), tok('172.5', 0.10, 0.775, w=0.06)]
    T += arow('골격근량', 0.74, '135.2', '(26.5~32.5)')
    T += arow('체지방량', 0.68, '9.8', '(7.1~14.2)')
    T += arow('체지방률', 0.62, '13.7', '(10.0~20.0)')
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def split_decimal():
    T = [tok('체성분분석', 0.06, 0.90, h=0.018)]
    T += [tok('2026. 5. 18', 0.60, 0.92, w=0.10, h=0.015)]
    lw = 0.013 * 4
    T += [tok('골격근량', 0.06, 0.74, w=lw),
          tok('35.', 0.30, 0.74, w=0.038),
          tok('2', 0.3395, 0.74, w=0.012),
          tok('( 26. 5~32. 5 )', 0.36, 0.74, w=0.11, h=0.016)]
    T += [tok('내장지방레벨', 0.06, 0.30), tok('4레벨', 0.17, 0.30, w=0.04)]
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def ideal_weight():
    # 체중 앵커는 범위 부정합으로 죽고(R8), 체중조절 섹션의 적정체중 행이
    # 남는다. 적정체중은 값이 라벨 아래(B 위치)에 오는 배치 — R1이 완전일치가
    # 아니면(포함매칭) '적정체중'이 체중 앵커가 되어 67.6을 줍는다(실측 함정).
    T = [tok('체성분분석', 0.06, 0.90, h=0.018)]
    T += [tok('체중', 0.06, 0.80), tok('72.5 (155.8~175.4)', 0.30, 0.80, w=0.16)]
    T += [tok('체중조절', 0.06, 0.30)]
    T += [tok('적정체중', 0.06, 0.25), tok('67.6', 0.065, 0.225, w=0.05)]
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def monitor():
    # LookInBody 모니터류: 같은 줄에 값만 있고 표준범위가 없다 — R6의
    # "범위 없는 같은 줄 숫자는 절대 채택 안 함"(눈금 줄 방어)이 홀로 판정한다.
    T = [tok('체성분분석', 0.06, 0.90, h=0.018)]
    T += [tok('체중', 0.06, 0.80), tok('68.6', 0.30, 0.80, w=0.05)]
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def no_label_b_leak():
    T = [tok('체성분분석', 0.06, 0.90, h=0.018)]
    T += [tok('체중', 0.06, 0.80), tok('72.5 (155.8~175.4)', 0.30, 0.80, w=0.16)]
    T += [tok('67.6', 0.30, 0.775, w=0.05)]
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def ambiguous_b():
    T = [tok('체성분분석', 0.06, 0.90, h=0.018)]
    T += [tok('체중', 0.06, 0.80), tok('72.5', 0.10, 0.775, w=0.05),
          tok('68.3', 0.17, 0.775, w=0.05)]
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def ambiguous_a():
    T = [tok('체성분분석', 0.06, 0.90, h=0.018)]
    T += [tok('체중', 0.06, 0.80), tok('72.5', 0.30, 0.80, w=0.05),
          tok('(55.8~75.4)', 0.36, 0.80, w=0.09, h=0.016),
          tok('68.3 (55.8~75.4)', 0.46, 0.802, w=0.16)]
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def ffm():
    T = [tok('체성분분석', 0.06, 0.90, h=0.018)]
    T += [tok('체지방량', 0.06, 0.68)]
    T += [tok('제지방량', 0.06, 0.655), tok('62.5', 0.30, 0.655, w=0.05)]
    T += [tok('체지방률', 0.06, 0.55)]
    T += [tok('117', 0.30, 0.5275, w=0.04)]
    T += [tok('기초대사량', 0.06, 0.40)]
    T += [tok('권장섭취열량', 0.06, 0.375), tok('2166', 0.35, 0.375, w=0.05)]
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def cross():
    T = [tok('체성분분석', 0.06, 0.90, h=0.018)]
    T += arow('체중', 0.80, '70.2', '(55.8~75.4)')
    T += arow('골격근량', 0.74, '30.1', '(26.5~32.5)')
    T += [tok('체지방량', 0.06, 0.68), tok('51.2', 0.10, 0.655, w=0.05)]
    T += arow('체지방률', 0.60, '26.8', '(18.0~28.0)')
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def identity():
    T = [tok('체성분분석', 0.06, 0.90, h=0.018)]
    T += arow('체중', 0.80, '70.2', '(55.8~75.4)')
    T += [tok('체지방량', 0.06, 0.68), tok('51.2', 0.10, 0.655, w=0.05)]
    T += arow('체지방률', 0.60, '26.8', '(18.0~28.0)')
    T += arow('기초대사량', 0.50, '1421', '(1350~1500)')
    T += [tok('내장지방레벨', 0.06, 0.44), tok('8', 0.17, 0.44, w=0.012)]
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def history_only():
    T = [tok('인바디', 0.35, 0.92), tok('측정안내문구', 0.06, 0.85)]
    T += [tok('신체변화', 0.05, 0.30)]
    T += [tok('체중', 0.06, 0.26), tok('69.9', 0.065, 0.235, w=0.05)]
    T += [tok('골격근량', 0.06, 0.20), tok('33.1', 0.065, 0.175, w=0.05)]
    T += [tok('www.inbody.co.kr', 0.40, 0.02, w=0.12, h=0.012)]
    return T


def r2b_bottom():
    T = [tok('인바디', 0.35, 0.92), tok('측정안내문구', 0.06, 0.85),
         tok('안내문', 0.06, 0.60)]
    T += [tok('체중', 0.06, 0.10), tok('69.9', 0.065, 0.075, w=0.05)]
    return T


FIXTURES = {
    'standard': standard,
    'slant': slant,
    'gauge': gauge,
    'bar_glyph': bar_glyph,
    'split_decimal': split_decimal,
    'ideal_weight': ideal_weight,
    'monitor': monitor,
    'no_label_b_leak': no_label_b_leak,
    'ambiguous_b': ambiguous_b,
    'ambiguous_a': ambiguous_a,
    'ffm': ffm,
    'cross': cross,
    'identity': identity,
    'history_only': history_only,
    'r2b_bottom': r2b_bottom,
}

os.makedirs(OUT, exist_ok=True)
for name, build in FIXTURES.items():
    rows = build()
    path = os.path.join(OUT, f'{name}.tsv')
    with open(path, 'w') as f:
        for r in rows:
            f.write('\t'.join(str(v) for v in r) + '\n')
    toks = ref['load'](path)
    raw = ref['extract'](toks)
    got, dropped = ref['validate'](dict(raw))
    print(f'=== {name}')
    for k in ('weight', 'smm', 'bfm', 'pbf', 'vfl', 'bmr', 'date'):
        print(f'  {k:7} {got.get(k)}')
    for d in dropped:
        print(f'  [drop] {d}')
