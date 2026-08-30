import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/trainer_avatar.dart';
import 'package:rise_member/features/booking/presentation/widgets/trainer_profile_sheet.dart';

/// 센터 코치 소개 목록(P40) — 담당 코치만 보이던 앱에 "우리 센터에 어떤 코치들이
/// 있는지"를 열어 준다. 데이터는 [staffMapProvider] 캐시(GET /v1/staff — 서버가
/// 회원에게 이미 센터 전체 스태프를 내려준다)라 이 시트의 추가 네트워크는 0이고,
/// 행을 탭하면 기존 프로필 시트([showTrainerProfileSheet])가 그 위로 열린다.
///
/// **현직만 보여준다.** 목록은 "지금 이 센터에서 수업하는 사람"을 묻는 자리다 —
/// 퇴사자는 이름 해석(담당 코치 표시)에는 남지만 소개 목록에 올리면 회원이
/// 문의하고서야 없는 사람인 걸 알게 된다(staff_directory.dart의 필터링 규약).
Future<void> showCenterCoachesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // 루트 Navigator — 셸 내부에 띄우면 하단 탭바가 시트 위에 남는다(P09).
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => const _CenterCoachesSheet(),
  );
}

class _CenterCoachesSheet extends ConsumerWidget {
  const _CenterCoachesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(staffMapProvider);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '센터 코치 소개',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            switch (async) {
              // 이전 값이 있으면 **항상 목록을 유지한다** — staffMap은 15분 TTL로
              // invalidateSelf가 도는 캐시라(staff_directory.dart), 시트를 연 채
              // 만료되면 "이전 값을 품은 AsyncLoading/AsyncError"가 온다. 그때
              // 스피너·에러로 통째로 교체하면 잘 보던 목록이 깜빡이거나, 백그라운드
              // 재조회 실패가 멀쩡한 목록을 "불러오지 못했어요"로 덮는다.
              AsyncValue(:final value?) => _CoachList(
                coaches: _activeCoaches(value),
              ),
              AsyncError() => _RetryBody(
                onRetry: () => ref.invalidate(staffMapProvider),
              ),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.red,
                    ),
                  ),
                ),
              ),
            },
          ],
        ),
      ),
    );
  }

  /// 현직만, 관장 먼저 → 이름순. 정렬이 흔들리면 열 때마다 순서가 바뀌어
  /// "아까 그 코치"를 다시 찾기 어렵다.
  ///
  /// 정수 랭크로 비교한다 — `a.role != b.role`식 분기는 미지 role(제3값)이 오면
  /// compare(x,y)와 compare(y,x)가 둘 다 1이 되는 모순 comparator라 정렬 결과가
  /// 미정의가 된다(StaffDto가 미지값을 승격 방어하는 앱 규약과 같은 방어).
  static List<StaffDto> _activeCoaches(Map<String, StaffDto> map) {
    int rank(StaffDto s) => s.role == 'owner' ? 0 : 1;
    final list = map.values.where((s) => !s.isInactive).toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.name.compareTo(b.name);
      });
    return list;
  }
}

class _CoachList extends StatelessWidget {
  const _CoachList({required this.coaches});
  final List<StaffDto> coaches;

  @override
  Widget build(BuildContext context) {
    if (coaches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '등록된 코치가 없어요',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ),
      );
    }
    return Column(
      children: [for (final coach in coaches) _CoachRow(coach: coach)],
    );
  }
}

class _CoachRow extends StatelessWidget {
  const _CoachRow({required this.coach});
  final StaffDto coach;

  @override
  Widget build(BuildContext context) {
    final profile = coach.profile;
    // 직함 · 연차 한 줄 — 프로필 시트의 subtitle과 같은 조립 규칙(둘 다 없으면 역할명).
    final subtitle = [
      if (profile.title.isNotEmpty) profile.title,
      if (profile.careerYears > 0) '${profile.careerYears}년차',
    ].join(' · ');
    return InkWell(
      onTap: () => showTrainerProfileSheet(context, staff: coach),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            TrainerAvatar(
              name: coach.name,
              photoUrl: profile.photoUrl,
              colorHex: coach.color,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coach.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle.isEmpty
                        ? (coach.role == 'owner' ? '관장' : '코치')
                        : subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                  if (profile.specialties.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      profile.specialties.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.chipFg,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const RiseIcon(
              RiseIcons.chevronRight,
              size: 14,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryBody extends StatelessWidget {
  const _RetryBody({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const Text(
            '코치 목록을 불러오지 못했어요',
            style: TextStyle(fontSize: 11.5, color: AppColors.danger),
          ),
          const SizedBox(height: 8),
          // 앱 표준 재시도 버튼(rise_error_view와 동일) — 자작 텍스트 링크는
          // 터치 타깃이 ~28dp라 44dp 규약 미달이었다.
          RiseButton(label: '다시 시도', small: true, onPressed: onRetry),
        ],
      ),
    );
  }
}
