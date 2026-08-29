/// 인바디 결과지 OCR 토큰 → 6지표+측정일 파서 — 순수 도메인(Flutter/ML Kit 의존 0).
///
/// `design/inbody-ocr/parse.py`(헤더 독스트링 R1~R11이 사양서)의 Dart 이식이다.
/// **모든 규칙은 "인바디 결과지의 구조적 속성"으로 정당화된다 — 특정 장(sheet)의
/// 좌표 하드코딩 금지.** 규칙을 고치려면 참조 구현과 실물 실측(README.md의 5장)을
/// 먼저 고쳐야 한다.
///
/// 핵심 속성: **확신 없으면 빈칸.** 틀린 값이 채워지면 회원이 그대로 저장하지만,
/// 빈칸은 결과지를 보고 채운다. 그래서 모호성(R6·R10)·검증 실패(R11)는 전부
/// 빈칸으로 떨어진다.
///
/// 규칙 요약(각 함수 주석에 상세):
/// - R1  라벨 앵커는 한글만 남긴 문자열의 완전일치(기초대사·내장지방만 접두).
/// - R2  신체변화(히스토리) 섹션의 앵커는 버린다. R2b 페이지 하단 15%도.
/// - R3  기울기 보정 — 지역 기울기 우선, 전역은 폴백.
/// - R4  값 타입 강제: kg·%는 소수, BMR은 정수. 필드 범위 즉시 적용.
/// - R5  값 토큰 순수성: 한글/날짜/라틴 과다 배제.
/// - R6  기하 A: 같은 줄 + 표준범위 정합. 범위 없는 같은 줄 숫자는 절대 불채택.
/// - R7  기하 B: 게이지 바 형식(라벨 아래 값). R7b 행 소유권.
/// - R8  범위형(A) 줄이면 B 금지. 범위 부정합 토큰은 전면 배제.
/// - R9  소수점 복원(공백·분할·바 글리프 '1' 접착).
/// - R10 비등한 B 후보 2개 = 모호 — 빈칸.
/// - R11 검증(범위·교차·항등) — **식은 [InbodyInputRules]를 재사용**(서버 v2.9 미러
///       한 곳만 존재해야 한다. 중복 정의 금지).
library;

import 'dart:math' as math;

import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/inbody_metrics.dart';

/// OCR 토큰 하나 — 텍스트 + 정규화 바운딩박스.
///
/// 좌표 규약은 참조 구현(macOS Vision)과 같다: **0~1 정규화, y는 위로 증가(페이지
/// 아래가 0), (x, y)는 박스의 왼쪽-아래 모서리.** ML Kit은 픽셀 좌표에 y가 아래로
/// 증가하므로 data 계층 어댑터(`inbody_sheet_reader.dart`)가 이 규약으로 뒤집어서
/// 넣는다 — 파서 안의 부등호는 참조 구현과 문자 그대로 같게 유지한다.
class InbodyOcrToken {
  const InbodyOcrToken({
    required this.text,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final String text;
  final double x;
  final double y;
  final double w;
  final double h;
}

/// 파싱 결과 — 확신한 필드만 들어 있다(없는 키 = 빈칸으로 두라는 뜻).
class InbodySheetParseResult {
  const InbodySheetParseResult({required this.values, this.measuredDate});

  const InbodySheetParseResult.empty() : this(values: const {});

  final Map<InbodyMetric, double> values;

  /// 결과지에 인쇄된 측정일. 확신 없으면 null — 폼의 기본값(오늘)이 그대로 남는다.
  final DateTime? measuredDate;
}

abstract final class InbodySheetParser {
  /// 토큰 목록 → 필드별 값 + 측정일. 실패는 예외가 아니라 **빈 결과**다 —
  /// 수기 입력이 곧 실패 경로라(제품 결정), 호출부는 채워진 것만 프리필한다.
  static InbodySheetParseResult parse(List<InbodyOcrToken> tokens) {
    final toks = _mergeSplitDecimals(tokens);
    final gslope = _estimateSlope(toks);
    final labels = _hangulLabels(toks);
    final values = <InbodyMetric, double>{};

    const specs = [
      (InbodyMetric.weight, '체중', false),
      (InbodyMetric.smm, '골격근량', false),
      (InbodyMetric.bfm, '체지방량', false),
      (InbodyMetric.pbf, '체지방률', false),
      // 량/랑 오독 허용(접두) — R1.
      (InbodyMetric.bmr, '기초대사', true),
    ];
    for (final (field, label, prefix) in specs) {
      for (final a in _findAnchors(toks, label, prefix: prefix)) {
        final v = _anchorValue(toks, a, field, gslope, labels);
        if (v != null) {
          values[field] = v;
          break; // R8: A 실패 시 다음 앵커로 폴백 — 성공한 첫 앵커에서 멈춘다.
        }
      }
    }

    var vflAnchors = _findAnchors(toks, '내장지방', prefix: true);
    if (vflAnchors.isEmpty) {
      // 접두 매칭의 길이 한도(라벨+1)에 '내장지방레벨'(6자)이 걸리므로 별도 시도.
      vflAnchors = _findAnchors(toks, '내장지방레벨', prefix: true);
    }
    for (final a in vflAnchors) {
      final v = _belowValue(toks, a, gslope);
      if (v != null) {
        values[InbodyMetric.vfl] = v;
        break;
      }
    }

    DateTime? date;
    for (final t in toks) {
      final m = _datePattern.firstMatch(t.text);
      if (m != null) {
        // 참조 구현과 같이 첫 매치에서 멈춘다(토큰은 x 정렬 상태 — 더 왼쪽 우선).
        // 참조는 문자열이라 "2026-13-45"도 내보내지만 여기선 DateTime을 만들어야
        // 하므로 실존 달력 날짜만 통과시킨다(롤오버는 오독 — null). [이식 차이 ①]
        date = _validDate(
          int.parse(m[1]!),
          int.parse(m[2]!),
          int.parse(m[3]!),
        );
        break;
      }
    }

    _validate(values);
    return InbodySheetParseResult(values: values, measuredDate: date);
  }
}

// ── 정규식(참조 구현과 동일) ───────────────────────────────────────────────

final _hangul = RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]');

/// 소수 1~2자리 (kg/% 지표).
final _dec = RegExp(r'\d{1,4}\.\d{1,2}');

/// 정수 3~4자리 (BMR).
final _int = RegExp(r'(?<![\d.])\d{3,4}(?![\d.])');

/// 표준범위 "(L~H)".
final _rg = RegExp(r'(\d{1,4}(?:\.\d{1,2})?)\s*~\s*(\d{1,4}(?:\.\d{1,2})?)');

/// 날짜/시각 패턴 — 값 후보에서 배제(R5).
final _dateLike = RegExp(r'\d{2,4}\.\s?\d{1,2}\.\s?\d{1,2}|\d{1,2}:\d{2}');

final _datePattern = RegExp(r'(20\d{2})[.\s]+(\d{1,2})[.\s]+(\d{1,2})');

// ── 기하 유틸 ────────────────────────────────────────────────────────────

double _cx(InbodyOcrToken t) => t.x + t.w / 2;
double _cy(InbodyOcrToken t) => t.y + t.h / 2;

double _yOverlap(InbodyOcrToken a, InbodyOcrToken b) =>
    math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y);

/// 파이썬 statistics.median과 같은 정의(짝수면 가운데 두 값 평균).
double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

// ── R9: 소수점 복원 ──────────────────────────────────────────────────────

/// OCR이 소수점 뒤에 공백을 끼운다("32. 5", "( 26. 5~32. 5 )"). 쉼표 오독도 흡수.
String _fixSpaces(String input) {
  var s = input.replaceAll(',', '.');
  String? prev;
  final gap = RegExp(r'(\d)\.\s+(\d)');
  while (prev != s) {
    prev = s;
    s = s.replaceAllMapped(gap, (m) => '${m[1]}.${m[2]}');
  }
  return s;
}

final _trailingDot = RegExp(r'^.*?(\d{1,4})[.,]$');
final _shortDigits = RegExp(r'^\d{1,2}$');

/// "32." + "5" 두 토큰으로 쪼개진 소수 복원(세로 겹침 + x간격 < 0.025).
/// 반환 목록은 x 정렬 상태다 — 날짜 탐색의 "첫 매치" 우선순위가 여기에 기댄다.
List<InbodyOcrToken> _mergeSplitDecimals(List<InbodyOcrToken> input) {
  final toks = [...input]..sort((a, b) => a.x.compareTo(b.x));
  final used = <int>{};
  final out = <InbodyOcrToken>[];
  for (var i = 0; i < toks.length; i++) {
    if (used.contains(i)) continue;
    final a = toks[i];
    final ta = a.text.trim();
    if (_trailingDot.hasMatch(ta)) {
      for (var j = i + 1; j < toks.length; j++) {
        if (used.contains(j)) continue;
        final b = toks[j];
        final gap = b.x - (a.x + a.w);
        if (gap > 0.025) break;
        if (gap < -0.01) continue;
        if (!_shortDigits.hasMatch(b.text.trim())) continue;
        if (_yOverlap(a, b) < 0.5 * math.min(a.h, b.h)) continue;
        final y0 = math.min(a.y, b.y);
        final y1 = math.max(a.y + a.h, b.y + b.h);
        out.add(InbodyOcrToken(
          text: ta + b.text.trim(),
          x: a.x,
          y: y0,
          w: b.x + b.w - a.x,
          h: y1 - y0,
        ));
        used
          ..add(i)
          ..add(j);
        break;
      }
    }
    if (!used.contains(i)) out.add(a);
  }
  return out;
}

String _normHangul(String s) =>
    RegExp(r'[가-힣]').allMatches(s).map((m) => m[0]!).join();

// ── R3: 기울기 보정 ──────────────────────────────────────────────────────

/// 같은 인쇄 줄 토큰쌍 기울기의 중앙값, 2-패스.
/// 1차: 근거리(dx 0.015~0.07)만 — 전단 변위가 줄 간격을 못 넘어 겹침 판정이
///      아직 유효한 구간. 2차: 1차 값으로 deskew한 뒤 원거리(dx 0.03~0.35) 정밀화.
/// 지역 추정([cy0] 지정)은 표본이 적어 전역값 ±0.04로 클램프, 전역은 물리 한계
/// ±0.12(~7°) — 그 이상은 재촬영 영역.
double _estimateSlope(
  List<InbodyOcrToken> toks, {
  double? cy0,
  double? cx0,
  double fallback = 0.0,
}) {
  final List<InbodyOcrToken> sel;
  if (cy0 != null) {
    sel = [
      for (final t in toks)
        if ((_cy(t) - cy0).abs() < 0.13 && (_cx(t) - cx0!).abs() < 0.60) t,
    ];
  } else {
    sel = toks;
  }

  List<double> collect(double lo, double hi, double skew, double minov) {
    final out = <double>[];
    for (var i = 0; i < sel.length; i++) {
      final a = sel[i];
      for (var j = i + 1; j < sel.length; j++) {
        final b = sel[j];
        final dx = _cx(b) - _cx(a);
        if (!(lo < dx.abs() && dx.abs() < hi)) continue;
        final bbY = b.y - skew * dx;
        final ov = math.min(a.y + a.h, bbY + b.h) - math.max(a.y, bbY);
        if (ov < minov * math.min(a.h, b.h)) continue;
        out.add(((bbY + b.h / 2) - _cy(a)) / dx + skew);
      }
    }
    return out;
  }

  final s1 = collect(0.015, 0.07, 0.0, 0.25);
  if (s1.length < 6) return fallback;
  final m1 = _median(s1);
  final s2 = collect(0.03, 0.35, m1, 0.45);
  var m = s2.length >= 6 ? _median(s2) : m1;
  if (cy0 != null) {
    m = m.clamp(fallback - 0.04, fallback + 0.04);
  } else {
    m = m.clamp(-0.12, 0.12);
  }
  return m;
}

// ── R1 + R2 + R2b: 앵커 탐색 ─────────────────────────────────────────────

/// 라벨 앵커는 한글만 남긴 문자열의 **완전일치**([prefix]면 접두, 라벨+1자까지).
/// 포함매칭 금지 — 체중조절·적정체중·체지방률표준 같은 파생 라벨이 전부 함정이다.
List<InbodyOcrToken> _findAnchors(
  List<InbodyOcrToken> toks,
  String label, {
  bool prefix = false,
}) {
  final hist = [
    for (final t in toks)
      if (_normHangul(t.text).startsWith('신체변화')) t,
  ];
  final out = <InbodyOcrToken>[];
  for (final t in toks) {
    final n = _normHangul(t.text);
    final ok = prefix
        ? (n.startsWith(label) && n.length <= label.length + 1)
        : n == label;
    if (!ok) continue;
    // R2: 신체변화 헤더 아래+같은 패널(헤더 왼쪽끝-0.05 오른쪽)이면 과거값 열.
    if (hist.any((h) => _cy(t) < _cy(h) && t.x > h.x - 0.05)) continue;
    out.add(t);
  }
  // 위(주 섹션) 우선 — 동률은 입력 순서 유지(안정 정렬).
  final indexed = out.asMap().entries.toList()
    ..sort((a, b) {
      final c = b.value.y.compareTo(a.value.y);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  final sorted = [for (final e in indexed) e.value];
  if (toks.isEmpty) return sorted;
  // R2b: 페이지(토큰 구름) 하단 15%의 앵커는 무조건 배제 — 전 형식에서 신체변화
  //      히스토리 표가 페이지 바닥에 온다. 헤더가 OCR에서 누락돼 R2가 못 걸러도
  //      이걸로 걸린다. 주 섹션 앵커는 실측 전부 스팬 42% 위였다.
  var minY = double.infinity, maxY = double.negativeInfinity;
  for (final t in toks) {
    final c = _cy(t);
    minY = math.min(minY, c);
    maxY = math.max(maxY, c);
  }
  final cut = minY + 0.15 * (maxY - minY);
  return [
    for (final t in sorted)
      if (_cy(t) >= cut) t,
  ];
}

// ── R5: 값 토큰 순수성 ────────────────────────────────────────────────────

final _units = RegExp('kcal|kg|cm|mm|%', caseSensitive: false);
final _latin = RegExp('[A-Za-z]');

bool _tokenPure(String text) {
  if (_hangul.hasMatch(text)) return false;
  if (_dateLike.hasMatch(text)) return false;
  final s = text.replaceAll(_units, '');
  if (_latin.allMatches(s).length > 2) return false;
  return true;
}

// ── R4 + R9: 토큰 → 값 ───────────────────────────────────────────────────

/// 토큰 → (값, 붙은 표준범위). 값이 못 되면 값 null. kg·%는 소수 강제(눈금·
/// 비만도117% 배제), BMR은 정수(제지방량 62.5 배제). 필드 범위 즉시 적용.
/// 게이지 바 글리프가 '1'로 붙은 "135.2"는 범위 초과 시 선행 1 제거(35.2) 시도.
(double?, (double, double)?) _parseValueToken(String text, InbodyMetric field) {
  final s = _fixSpaces(text);
  final head = s.split('(').first;
  (double, double)? rng;
  if (s.contains('(')) {
    final m = _rg.firstMatch(s.substring(head.length));
    if (m != null) rng = (double.parse(m[1]!), double.parse(m[2]!));
  }
  if (head.contains('~')) {
    // 표준범위 단독 토큰 — 값 아님.
    final m = _rg.firstMatch(s);
    return (null, m == null ? null : (double.parse(m[1]!), double.parse(m[2]!)));
  }
  final lo = field.min, hi = field.max;
  final vals = <double>{};
  if (field == InbodyMetric.bmr) {
    // 소수가 섞인 토큰은 BMR 후보가 아니다(제지방량 62.5류).
    if (!_dec.hasMatch(head)) {
      for (final m in _int.allMatches(head)) {
        final v = double.parse(m[0]!);
        if (lo <= v && v <= hi) vals.add(v);
      }
    }
  } else {
    for (final m in _dec.allMatches(head)) {
      final ds = m[0]!;
      final v = double.parse(ds);
      if (lo <= v && v <= hi) {
        vals.add(v);
      } else if (v > hi && ds.startsWith('1')) {
        final repaired = double.parse(ds.substring(1));
        if (lo <= repaired && repaired <= hi) vals.add(repaired);
      }
    }
  }
  if (vals.length != 1) return (null, rng); // 값 0개 또는 모호(2개 이상) — 버린다.
  return (vals.first, rng);
}

final _rangeResidue = RegExp(r'[\d.,~()\s%]|kg|kcal|cm', caseSensitive: false);

/// "( 26. 5~32. 5 )" / "52.8~71.4" 같은 범위 단독 토큰.
(double, double)? _bareRange(String text) {
  final s = _fixSpaces(text);
  if (!s.contains('~') || _hangul.hasMatch(s)) return null;
  final m = _rg.firstMatch(s);
  if (m == null) return null;
  if (s.replaceAll(_rangeResidue, '').isNotEmpty) return null;
  return (double.parse(m[1]!), double.parse(m[2]!));
}

/// R6: 값-표준범위 정합. 인바디 표준범위는 인구 통계라 실측이 크게 못 벗어난다.
bool _rangeConsistent(double v, (double, double) rng) {
  final (lo, hi) = rng;
  return 0 < lo && lo < hi && 0.5 * lo <= v && v <= 1.6 * hi;
}

/// 행 소유권 판정용 라벨 토큰: 한글 2자 이상이면 라벨/체크박스/문장 — 값이 아니다.
List<InbodyOcrToken> _hangulLabels(List<InbodyOcrToken> toks) => [
      for (final t in toks)
        if (_normHangul(t.text).length >= 2) t,
    ];

// ── R7b: 행 소유권 ───────────────────────────────────────────────────────

/// 후보 t의 줄에서 **가장 가까운 왼쪽** 한글 라벨이 앵커가 아니면 남의 행 값.
/// 최근접 규칙인 이유: 설명문은 라벨보다 항상 왼쪽에 있다 — 라벨은 자기 값
/// 바로 옆에 인쇄된다(인바디 조판 속성).
bool _ownedByOther(
  InbodyOcrToken t,
  InbodyOcrToken anchor,
  List<InbodyOcrToken> labels,
  double slope,
) {
  InbodyOcrToken? owner;
  var ox = -1.0;
  for (final label in labels) {
    if (label.x >= t.x) continue;
    final dxc = _cx(t) - _cx(label);
    if (dxc > 0.55) continue;
    final dy = (_cy(t) - _cy(label)) - slope * dxc;
    if (dy.abs() <= 0.75 * math.max(label.h, t.h) && label.x > ox) {
      owner = label;
      ox = label.x;
    }
  }
  return owner != null && !identical(owner, anchor);
}

// ── R6~R8, R10: 한 앵커에서 값 시도 ──────────────────────────────────────

double? _anchorValue(
  List<InbodyOcrToken> toks,
  InbodyOcrToken anchor,
  InbodyMetric field,
  double gslope,
  List<InbodyOcrToken> labels,
) {
  final slope =
      _estimateSlope(toks, cy0: _cy(anchor), cx0: _cx(anchor), fallback: gslope);
  final acands = <(double, double)>[]; // (세로 겹침 비율, 값)
  final bcands = <(double, double)>[]; // (토큰 높이, 값)
  var sawARange = false;
  for (final t in toks) {
    if (identical(t, anchor) || t.x < anchor.x || _cx(t) <= _cx(anchor)) {
      continue;
    }
    final dxc = _cx(t) - _cx(anchor);
    if (dxc > 0.55) continue;
    final dy = (_cy(t) - _cy(anchor)) - slope * dxc; // 보정된 중심 y 차
    // R6: 기울기 보정 후 박스 세로 겹침 비율.
    final ov = (math.min(anchor.y + anchor.h, t.y + t.h - slope * dxc) -
            math.max(anchor.y, t.y - slope * dxc)) /
        math.min(anchor.h, t.h);
    final inA = ov >= 0.45;
    final inB = -1.5 * anchor.h <= dy && dy <= -0.10 * anchor.h;
    if (!(inA || inB) || !_tokenPure(t.text)) continue;
    if (_ownedByOther(t, anchor, labels, slope)) continue; // R7b (A·B 공통)
    var (v, rng) = _parseValueToken(t.text, field);
    if (v == null) continue;
    if (rng != null && !_rangeConsistent(v, rng)) {
      if (inA) sawARange = true; // 범위형 줄 증거는 남긴다(B 금지용).
      continue; // R8: 붙은 범위와 안 맞으면 오독 확정 — 전면 배제.
    }
    if (rng == null && inA) {
      // 같은 줄 + 바로 옆 범위 토큰(간격 -0.04~0.10, 세로 겹침)이면 범위형.
      for (final r in toks) {
        final rr = _bareRange(r.text);
        if (rr == null) continue;
        final gap = r.x - (t.x + t.w);
        if (-0.04 < gap &&
            gap < 0.10 &&
            _yOverlap(t, r) >= 0.4 * math.min(t.h, r.h)) {
          rng = rr;
          break;
        }
      }
      if (rng != null && !_rangeConsistent(v, rng)) {
        sawARange = true;
        continue;
      }
    }
    if (inA && rng != null) {
      sawARange = true;
      acands.add((ov, v));
    } else if (inB && dxc <= 0.45) {
      bcands.add((t.h, v));
    }
  }
  if (acands.isNotEmpty) {
    acands.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      return c != 0 ? c : b.$2.compareTo(a.$2);
    });
    final (ov0, v0) = acands.first;
    for (final (ov, v) in acands.skip(1)) {
      if (ov >= ov0 - 0.15 && (v - v0).abs() > 0.05) {
        return null; // R6: 겹침 비등한 다른 값 — 모호, 버린다.
      }
    }
    return v0;
  }
  if (sawARange) return null; // R8: 범위형 줄인데 정합 실패 — 이 앵커 포기(B 금지).
  if (bcands.isNotEmpty) {
    bcands.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      return c != 0 ? c : b.$2.compareTo(a.$2);
    });
    final (h0, v0) = bcands.first;
    for (final (h, v) in bcands.skip(1)) {
      if (h > 0.88 * h0 && (v - v0).abs() > 0.05) {
        return null; // R10: 비등한 후보 2개 — 모호, 버린다.
      }
    }
    return v0;
  }
  return null;
}

// ── VFL ──────────────────────────────────────────────────────────────────

final _levelPattern = RegExp(r'(\d{1,2})레벨');
final _smallInt = RegExp(r'(?<![\d.])(\d{1,2})(?![\d.])');

/// VFL. 값의 자리는 셋 중 하나(전 형식 실측):
///   (1) 'N레벨' 결합 토큰 — 최우선.
///   (2) 앵커 같은 줄 오른쪽, x오프셋 ≤ 0.18 (연구항목 행 형식).
///   (3) 앵커 아래 0.4~2.2h, x오프셋 ≤ 0.12 (게이지 왼쪽 열 형식).
/// 게이지 눈금 '10'은 x오프셋 0.21+ — x오프셋 캡이 구조적 방어다.
double? _belowValue(
  List<InbodyOcrToken> toks,
  InbodyOcrToken anchor,
  double gslope,
) {
  final slope =
      _estimateSlope(toks, cy0: _cy(anchor), cx0: _cx(anchor), fallback: gslope);
  final ay = anchor.y;
  final lo = InbodyMetric.vfl.min, hi = InbodyMetric.vfl.max;
  final region = [
    for (final t in toks)
      if (!identical(t, anchor) &&
          ay - 0.075 < t.y &&
          t.y < ay + anchor.h &&
          -0.02 < t.x - anchor.x &&
          t.x - anchor.x < 0.25)
        t,
  ];
  for (final t in region) {
    final s = t.text.replaceAll(' ', '');
    final m = _levelPattern.firstMatch(s);
    if (m != null) {
      final v = int.parse(m[1]!);
      if (lo <= v && v <= hi) return v.toDouble();
    }
  }
  final cands = <(double, double)>[];
  for (final t in region) {
    final s = _fixSpaces(t.text);
    if (s.contains('~') || _hangul.hasMatch(s)) continue;
    final xoff = t.x - anchor.x;
    final dy = (_cy(t) - _cy(anchor)) - slope * (_cx(t) - _cx(anchor));
    final onLine = dy.abs() <= 0.6 * math.max(anchor.h, t.h) && xoff <= 0.18;
    final below =
        -2.2 * anchor.h <= dy && dy <= -0.4 * anchor.h && xoff <= 0.12;
    if (!(onLine || below)) continue;
    for (final m in _smallInt.allMatches(s)) {
      final v = double.parse(m[1]!);
      if (lo <= v && v <= hi) cands.add((xoff.abs(), v));
    }
  }
  if (cands.isEmpty) return null;
  cands.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  return cands.first.$2;
}

// ── R11: 검증 ────────────────────────────────────────────────────────────

/// 검증 실패 필드는 버린다 — 틀린 프리필은 빈 칸보다 나쁘다.
///
/// **식은 전부 [InbodyInputRules] 재사용이다**(범위는 [InbodyMetric.min]/[max],
/// 교차는 [InbodyInputRules.crossFieldError], 항등은
/// [InbodyInputRules.consistencyWarning]) — 서버 v2.9 미러가 앱에 두 벌 생기면
/// 폼은 받는데 파서만 버리는(또는 그 반대) 어긋남이 생긴다. 교차 검증은 부분
/// 맵으로 한 제약씩 물어 "어느 필드를 버릴지"만 여기서 정한다.
///
/// [이식 차이 ②] 항등 허용오차: 참조 구현은 BFM 기준 max(0.8kg, 8%)를 쓰지만
/// 여기는 폼과 같은 PBF 기준 5.0%p([InbodyInputRules.pbfTolerance])를 쓴다 —
/// 파서가 폼보다 엄격하면 폼은 경고 없이 받아 줄 값을 파서만 빈칸으로 만들고,
/// 반대면 프리필 직후 폼에 경고가 떠 회원이 어리둥절해진다. 방향은 같고(수십 %p
/// 벌어지는 FFM 오기·바 글리프 체중은 양쪽 다 잡는다) 경계만 폼에 맞췄다.
void _validate(Map<InbodyMetric, double> got) {
  // 범위 — 값 후보 단계(R4)에서 이미 걸렀지만 사양(R11)대로 최종 관문을 한 번 더.
  for (final m in InbodyMetric.values) {
    final v = got[m];
    if (v != null && (v < m.min || v > m.max)) got.remove(m);
  }
  final w = got[InbodyMetric.weight];
  if (w == null) return;
  String raw(double v) => v.toString();

  String? cross(Map<InbodyMetric, double> fields) =>
      InbodyInputRules.crossFieldError(
          {for (final e in fields.entries) e.key: raw(e.value)});

  if (got[InbodyMetric.smm] case final smm?
      when cross({InbodyMetric.weight: w, InbodyMetric.smm: smm}) != null) {
    got.remove(InbodyMetric.smm); // smm ≥ w
  }
  if (got[InbodyMetric.bfm] case final bfm?
      when cross({InbodyMetric.weight: w, InbodyMetric.bfm: bfm}) != null) {
    got.remove(InbodyMetric.bfm); // bfm ≥ w
  }
  if (got[InbodyMetric.smm] != null &&
      got[InbodyMetric.bfm] != null &&
      cross({
            InbodyMetric.weight: w,
            InbodyMetric.smm: got[InbodyMetric.smm]!,
            InbodyMetric.bfm: got[InbodyMetric.bfm]!,
          }) !=
          null) {
    // smm+bfm > w — 셋 중 누가 틀렸는지 모르니 양쪽 모두 보류.
    got
      ..remove(InbodyMetric.smm)
      ..remove(InbodyMetric.bfm);
  }

  final bfm = got[InbodyMetric.bfm], pbf = got[InbodyMetric.pbf];
  if (bfm == null || pbf == null) return;
  String? warnAt(double wv) => InbodyInputRules.consistencyWarning(
        weightRaw: raw(wv),
        bfmRaw: raw(bfm),
        pbfRaw: raw(pbf),
      );
  if (warnAt(w) == null) return;
  // 바 글리프 '1' 접착 체중(1xx.x) 복원 시도 — 항등이 검증자다.
  // [이식 차이 ③] 복원값에도 체중 하한을 요구한다 — 참조 구현은 문자열 출력이라
  // 안 봤지만, 여기서 통과시키면 프리필 직후 폼이 그 칸을 붉게 판정한다.
  final repaired = w - 100;
  if (100 < w &&
      w < 200 &&
      repaired >= InbodyMetric.weight.min &&
      warnAt(repaired) == null) {
    got[InbodyMetric.weight] = repaired;
  } else {
    // 항등 불일치 — w·bfm·pbf 셋 다 보류(셋 중 누가 틀렸는지 모른다).
    got
      ..remove(InbodyMetric.weight)
      ..remove(InbodyMetric.bfm)
      ..remove(InbodyMetric.pbf);
  }
}

DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final d = DateTime(year, month, day);
  // DateTime은 2026-06-31을 07-01로 굴려버린다 — 굴러갔다면 실존하지 않는
  // 날짜를 읽은 것이므로(오독) 버린다.
  if (d.year != year || d.month != month || d.day != day) return null;
  return d;
}
