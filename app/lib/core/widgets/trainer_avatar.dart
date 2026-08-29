import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';

/// 코치 아바타(계약 v1.6, P05) — profile.photo_url이 있으면 원형 사진,
/// 없거나 로드에 실패하면 Staff.color 배경 + 이름 첫 글자 이니셜로 폴백.
/// 프로필 시트(대형)·온보딩 매칭 카드(소형)·예약 확정 시트(소형)에서 공용.
class TrainerAvatar extends StatelessWidget {
  const TrainerAvatar({
    super.key,
    required this.name,
    this.photoUrl = '',
    this.colorHex,
    this.size = 40,
    this.inactive = false,
  });

  final String name;

  /// 외부 이미지 URL — 계약상 http(s)만 유효(스킴 주입 차단). 빈 값이면 이니셜.
  final String photoUrl;

  /// Staff.color — "#f43f5e" 형식. 누락/파싱 실패 시 muted 회색 배경.
  final String? colorHex;

  final double size;

  /// 퇴사한 코치(Staff.status=inactive, 계약 v2.0) — 색을 빼서 현직과 구분한다.
  /// 사진은 흑백, 이니셜 배경은 Staff.color 대신 muted 회색. 아바타는 글자를 못
  /// 담으므로 "(퇴사)" 텍스트 표기(CoachLabel)를 대신하는 게 아니라 **보조**한다
  /// — 같은 화면에 표기가 두 번 나오지 않게 하면서 시각 신호는 유지하는 방법.
  final bool inactive;

  // 계약이 서버에서 http(s)만 허용하지만 클라이언트도 한 번 더 거른다(방어적).
  bool get _hasPhoto =>
      photoUrl.startsWith('http://') || photoUrl.startsWith('https://');

  static final _hexPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

  /// 채도 제거 행렬 — 퇴사 코치 사진을 흑백으로(ITU-R BT.601 휘도 가중치).
  static const _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  Color get _background {
    // 퇴사자는 센터가 배정한 개인 색을 쓰지 않는다 — 색 범례상 현직 자리이기 때문.
    if (inactive) return AppColors.muted;
    final hex = colorHex;
    if (hex != null && _hexPattern.hasMatch(hex)) {
      return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
    }
    return AppColors.muted;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPhoto) return _initialCircle();
    final photo = ClipOval(
      child: Image.network(
        photoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // 404/타임아웃 등 로드 실패 → 이니셜 폴백(계약 v1.6).
        errorBuilder: (_, __, ___) => _initialCircle(),
      ),
    );
    return inactive ? ColorFiltered(colorFilter: _grayscale, child: photo) : photo;
  }

  Widget _initialCircle() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _background, shape: BoxShape.circle),
      child: Text(
        // 한글 완성형·이모지에도 안전한 grapheme 단위 첫 글자.
        name.isEmpty ? '?' : name.characters.first,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
