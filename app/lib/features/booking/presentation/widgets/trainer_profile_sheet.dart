import 'package:flutter/material.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_typography.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';
import 'package:rise_member/core/widgets/trainer_avatar.dart';

/// 트레이너 프로필 시트(계약 v1.6, P05) — 예약 탭 코치 칩/태그·온보딩 담당 코치
/// 표시에서 진입. 데이터는 StaffDirectory 캐시(staffMapProvider)에서 이미 받은
/// StaffDto를 그대로 받아 표시만 한다 — 시트 자체 네트워크 호출 0.
///
/// 빈 프로필의 이유가 셋이라 안내도 셋으로 갈린다(계약 v2.0 보완). 이걸 뭉치면
/// 퇴사·미등록까지 전부 "불러오지 못했어요 — 새로고침"으로 안내해 **네트워크 오류로
/// 오인**시키고, 회원은 될 리 없는 새로고침만 반복한다:
///   ① 퇴사(status=inactive) — 계약상 role=member 응답은 inactive 스태프의 profile을
///      빈 객체로 마스킹한다. 즉 "퇴사 + 빈 프로필"은 오류가 아니라 **정상 응답**이다.
///   ② 캐시 미로드([profileUnavailable]) — 이름만 채운 폴백 StaffDto. 재시도가 답.
///   ③ 실제 미등록 — 현직인데 코치가 아직 소개를 안 썼다.
/// 우선순위는 ① > ② > ③. 퇴사는 확정 사실이라 캐시 상태보다 먼저 말해야 한다.
///
/// [profileUnavailable] — 스태프 캐시 미로드(로딩 전/로드 실패)로 이름만 채운
/// 폴백 StaffDto를 넘길 때 true.
Future<void> showTrainerProfileSheet(
  BuildContext context, {
  required StaffDto staff,
  bool profileUnavailable = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // 루트 Navigator에 띄운다 — 기본값(false)이면 셸 내부 Navigator에 올라가
    // **하단 탭바가 시트와 스크림 위에 남는다**(실기기 점검에서 발견, P09).
    // 모달이 뜬 채로 다른 탭을 누를 수 있어 확정 전 화면을 벗어나게 된다.
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _TrainerProfileSheet(staff: staff, profileUnavailable: profileUnavailable),
  );
}

class _TrainerProfileSheet extends StatelessWidget {
  const _TrainerProfileSheet({required this.staff, required this.profileUnavailable});

  final StaffDto staff;
  final bool profileUnavailable;

  @override
  Widget build(BuildContext context) {
    final profile = staff.profile;
    final roleLabel = staff.role == 'owner' ? '관장' : '코치';
    // 직함 · 연차("7년차") 한 줄 — 둘 다 없으면 역할명으로 폴백.
    final subtitle = [
      if (profile.title.isNotEmpty) profile.title,
      if (profile.careerYears > 0) '${profile.careerYears}년차',
    ].join(' · ');

    // 안내 우선순위: 퇴사 > 캐시 미로드 > 실제 미등록(시트 상단 주석 참조).
    // 퇴사 코치는 프로필이 마스킹돼 비어 있는 게 정상이므로, 소개가 비었다는
    // 말 대신 "지금은 볼 수 없다 + 다음에 뭘 하면 되는지"를 안내한다.
    final String? notice;
    if (staff.isInactive) {
      final left = staff.leftOn;
      notice = left == null
          ? '지금은 센터에서 활동하지 않는 코치예요 — 새 담당 코치는 센터에 문의해주세요'
          : '${left.year}년 ${left.month}월에 퇴사한 코치예요 — 새 담당 코치는 센터에 문의해주세요';
    } else if (profile.isEmpty) {
      notice = profileUnavailable
          ? '코치 정보를 불러오지 못했어요 — 새로고침 후 다시 시도해주세요'
          : '아직 소개가 등록되지 않았어요';
    } else {
      notice = null;
    }

    return ConstrainedBox(
      // 소개문이 길어도 시트가 화면 전체를 덮지 않게 상한 — 내부는 스크롤.
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: TrainerAvatar(
                name: staff.name,
                photoUrl: profile.photoUrl,
                colorHex: staff.color,
                size: 72,
                inactive: staff.isInactive,
              ),
            ),
            const SizedBox(height: 10),
            // 이름은 퇴사해도 그대로 둔다(계약 v2.0 — 이름 해석 보존). 상태는 옆
            // 배지 하나로만 말한다: 이름에 "(퇴사)"까지 겹치면 같은 사실을 두 번 읽힌다.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      staff.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (staff.isInactive) ...[
                    const SizedBox(width: 6),
                    const RiseBadge('퇴사', variant: RiseBadgeVariant.muted),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 3),
            Center(
              child: Text(
                subtitle.isEmpty ? roleLabel : subtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            if (notice != null) ...[
              const SizedBox(height: 18),
              Center(
                child: Text(
                  notice,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.6),
                ),
              ),
            ],
            // 퇴사 코치라도 프로필이 남아 있으면(구버전 서버·마스킹 전 응답) 그대로
            // 보여준다 — 안내는 위에 이미 붙었으므로 내용까지 숨길 이유는 없다.
            if (!profile.isEmpty) ...[
              if (profile.specialties.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (final s in profile.specialties) RiseChip(label: s),
                  ],
                ),
              ],
              if (profile.certifications.isNotEmpty) ...[
                const _SectionTitle('자격증'),
                for (final c in profile.certifications) _BulletLine(c),
              ],
              if (profile.awards.isNotEmpty) ...[
                const _SectionTitle('수상 · 선수 경력'),
                for (final a in profile.awards) _BulletLine(a),
              ],
              if (profile.bio.isNotEmpty) ...[
                const _SectionTitle('소개'),
                Text(
                  profile.bio,
                  style: const TextStyle(fontSize: 12, color: AppColors.ink, height: 1.7),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(title, style: AppTypography.cardTitle),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('·  ', style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.ink, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
