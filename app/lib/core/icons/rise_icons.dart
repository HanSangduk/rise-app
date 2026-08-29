/// 커스텀 SVG 아이콘 세트 — 이모지 전면 금지, lucide 스타일(24x24, stroke 2, round cap)
/// 로 직접 그린 벡터. `currentColor`로 stroke/fill을 지정해 [RiseIcon]에서
/// SvgTheme.currentColor로 색을 주입한다.
///
/// 모든 필드는 `static const`(컴파일 타임 상수)여야 `const RiseIcon(RiseIcons.x)`처럼
/// const 위젯 트리 안에서 쓸 수 있다 — 헬퍼 함수 호출 대신 인접 문자열 리터럴
/// 결합(`'$_header' '...' '$_footer'`)으로 감싼다.
abstract final class RiseIcons {
  static const _header =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
      'fill="none" stroke="currentColor" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round">';
  static const _footer = '</svg>';

  /// 홈 탭.
  static const home =
      '$_header'
      '<path d="M3 11.5 12 4l9 7.5"/>'
      '<path d="M5 10v9a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1v-9"/>'
      '$_footer';

  /// 예약 탭 (달력).
  static const calendar =
      '$_header'
      '<rect x="3" y="5" width="18" height="16" rx="2"/>'
      '<line x1="3" y1="9.5" x2="21" y2="9.5"/>'
      '<line x1="8" y1="3" x2="8" y2="7"/>'
      '<line x1="16" y1="3" x2="16" y2="7"/>'
      '$_footer';

  /// 촬영 탭 (체형 분석 카메라).
  static const camera =
      '$_header'
      '<path d="M4 8h3l1.6-2.2h6.8L17 8h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z"/>'
      '<circle cx="12" cy="14" r="3.6"/>'
      '$_footer';

  /// 기록 탭 (막대 차트).
  static const chart =
      '$_header'
      '<line x1="4" y1="21" x2="21" y2="21"/>'
      '<rect x="6" y="13" width="3" height="8" rx="0.5"/>'
      '<rect x="11" y="9" width="3" height="12" rx="0.5"/>'
      '<rect x="16" y="5" width="3" height="16" rx="0.5"/>'
      '$_footer';

  /// 마이 탭 (사람).
  static const person =
      '$_header'
      '<circle cx="12" cy="8" r="4"/>'
      '<path d="M4 20c0-4.2 3.6-6.5 8-6.5s8 2.3 8 6.5"/>'
      '$_footer';

  /// 체크(홈워크 완료, 확정 배지).
  static const check =
      '$_header'
      '<polyline points="4,13 9,18 20,6"/>'
      '$_footer';

  /// 일시정지.
  static const pause =
      '$_header'
      '<rect x="6" y="4" width="4" height="16" rx="1"/>'
      '<rect x="14" y="4" width="4" height="16" rx="1"/>'
      '$_footer';

  /// 셀프 체크인 QR 스캔.
  static const qrScan =
      '$_header'
      '<path d="M4 8V6a2 2 0 0 1 2-2h2"/>'
      '<path d="M16 4h2a2 2 0 0 1 2 2v2"/>'
      '<path d="M20 16v2a2 2 0 0 1-2 2h-2"/>'
      '<path d="M8 20H6a2 2 0 0 1-2-2v-2"/>'
      '<rect x="9" y="9" width="6" height="6" rx="1"/>'
      '$_footer';

  /// 화살표형 셰브런(우/하/좌).
  static const chevronRight =
      '$_header'
      '<polyline points="9,4 17,12 9,20"/>'
      '$_footer';
  static const chevronLeft =
      '$_header'
      '<polyline points="15,4 7,12 15,20"/>'
      '$_footer';
  static const chevronDown =
      '$_header'
      '<polyline points="4,9 12,17 20,9"/>'
      '$_footer';

  /// 알림.
  static const bell =
      '$_header'
      '<path d="M6 10a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6Z"/>'
      '<path d="M10 20a2 2 0 0 0 4 0"/>'
      '$_footer';

  /// 레벨/그리드 — 체형 분석 그리드 오버레이 · 정렬 표시.
  static const grid =
      '$_header'
      '<rect x="3" y="3" width="18" height="18" rx="2"/>'
      '<line x1="9" y1="3" x2="9" y2="21"/>'
      '<line x1="15" y1="3" x2="15" y2="21"/>'
      '<line x1="3" y1="9" x2="21" y2="9"/>'
      '<line x1="3" y1="15" x2="21" y2="15"/>'
      '$_footer';

  /// 뒤로가기.
  static const arrowLeft =
      '$_header'
      '<line x1="20" y1="12" x2="4" y2="12"/>'
      '<polyline points="10,6 4,12 10,18"/>'
      '$_footer';

  /// 닫기.
  static const close =
      '$_header'
      '<line x1="5" y1="5" x2="19" y2="19"/>'
      '<line x1="19" y1="5" x2="5" y2="19"/>'
      '$_footer';

  /// 경고(배경 인물 감지 등).
  static const alertTriangle =
      '$_header'
      '<path d="M12 3 22 20H2Z"/>'
      '<line x1="12" y1="9.5" x2="12" y2="14"/>'
      '<line x1="12" y1="17" x2="12" y2="17.2"/>'
      '$_footer';

  /// 사람 여러 명(배경 인물 경고 아이콘).
  static const users =
      '$_header'
      '<circle cx="8.5" cy="9" r="3"/>'
      '<path d="M2 20c0-3.6 3-6 6.5-6s6.5 2.4 6.5 6"/>'
      '<circle cx="17" cy="8" r="2.2"/>'
      '<path d="M14.8 14.2c3 .2 5.7 2.4 5.7 5.8"/>'
      '$_footer';

  /// 새로고침 / 재개(일시정지 해제).
  static const refresh =
      '$_header'
      '<path d="M20 11A8 8 0 0 0 6.3 6.3L4 8.5"/>'
      '<polyline points="4,4 4,8.5 8.5,8.5"/>'
      '<path d="M4 13a8 8 0 0 0 13.7 4.7L20 15.5"/>'
      '<polyline points="20,20 20,15.5 15.5,15.5"/>'
      '$_footer';

  /// 동의(민감정보 동의).
  static const shield =
      '$_header'
      '<path d="M12 3 19 6v6c0 5-3.2 7.5-7 9-3.8-1.5-7-4-7-9V6Z"/>'
      '<polyline points="9,12 11,14 15,9.5"/>'
      '$_footer';

  /// 계약서.
  static const fileText =
      '$_header'
      '<path d="M7 3h7l4 4v14a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Z"/>'
      '<polyline points="14,3 14,7 18,7"/>'
      '<line x1="8.5" y1="12.5" x2="15.5" y2="12.5"/>'
      '<line x1="8.5" y1="16" x2="15.5" y2="16"/>'
      '$_footer';

  /// 유령(고스트 오버레이).
  static const ghost =
      '$_header'
      '<path d="M6 21V11a6 6 0 0 1 12 0v10l-2.3-1.8-2 1.8-1.7-1.8L10 21l-2-1.8Z"/>'
      '<line x1="9.5" y1="11" x2="9.6" y2="11"/>'
      '<line x1="14.5" y1="11" x2="14.6" y2="11"/>'
      '$_footer';

  /// 점 찍힌 원 (잔여 표시 등 범용).
  static const circleDot =
      '$_header'
      '<circle cx="12" cy="12" r="8.5"/>'
      '<circle cx="12" cy="12" r="2.2" fill="currentColor" stroke="none"/>'
      '$_footer';

  /// 잠금(비활성/마감 표시).
  static const lock =
      '$_header'
      '<rect x="5" y="11" width="14" height="9" rx="2"/>'
      '<path d="M8 11V7a4 4 0 0 1 8 0v4"/>'
      '$_footer';

  /// 로그아웃(세션 종료).
  static const logout =
      '$_header'
      '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/>'
      '<polyline points="16,17 21,12 16,7"/>'
      '<line x1="21" y1="12" x2="9" y2="12"/>'
      '$_footer';

  /// 플러스(추가).
  static const plus =
      '$_header'
      '<line x1="12" y1="5" x2="12" y2="19"/>'
      '<line x1="5" y1="12" x2="19" y2="12"/>'
      '$_footer';

  /// 전체화면 확대(체형 사진 "크게 보기" 힌트) — lucide maximize-2 대각 화살표.
  /// 4방향 화살표는 13px 렌더에서 화살촉 8개가 뭉개져 눈송이로 오독된다 —
  /// 대각 2방향이 소형에서 살아남고, 사진 문맥에서 "커짐"으로 읽힌다.
  static const expand =
      '$_header'
      '<polyline points="15,3 21,3 21,9"/>'
      '<polyline points="9,21 3,21 3,15"/>'
      '<line x1="21" y1="3" x2="14" y2="10"/>'
      '<line x1="3" y1="21" x2="10" y2="14"/>'
      '$_footer';
}
