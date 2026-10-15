import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/trainer_avatar.dart';
import 'package:rise_member/features/booking/presentation/widgets/trainer_profile_sheet.dart';
import 'package:rise_member/features/my/presentation/widgets/center_coaches_sheet.dart';

/// 홈의 담당 코치 카드.
///
/// **왜 만들었나** — 대표 요청("홈에서 트레이너 찾고 예약도 편하게")이 출발점이지만,
/// 경쟁 제품 12종을 조사한 결과 **홈에 담당 코치를 세운 곳이 하나도 없었다**
/// (Trainerize·TrueCoach·Everfit·PT Distinction·Mindbody·ClassPass·Momence·Walla·
/// Mariana Tek·Glofox·Zen Planner·WellnessLiving). 국내 앱 리뷰에서는 그 공백이
/// 그대로 불만으로 나온다 — 하이파이브 회원은 "어떤 코치님이 참여하시는지 적혀있으면
/// 좋겠어요", "담당 코치/트레이너와 앱 내에서 소통할 수 있으면 좋겠습니다(개인카톡은
/// 양쪽 다 불편)"라고 쓴다. 즉 코치와의 연결이 앱 밖(카톡·밴드)으로 새고 있다.
///
/// **공짜에 가깝다** — `GET /v1/staff`는 홈 로드의 첫 호출이고(home_repository_impl),
/// 서버는 회원에게 사진·직함·연차·전문분야·자격·수상·소개를 **전부** 내려준다.
/// 그런데 홈은 여태 `name` 하나만 썼다. 프로필 시트도 이미 있고 네트워크 0이다.
/// 새 요청도, 새 서버 작업도 없다.
///
/// **광고·게임화는 넣지 않는다.** 같은 조사에서 국내 회원들이 칭찬한 건 정확히
/// 그 반대였다 — "불필요한게 없어서 좋아요", "쓸데없는 광고가 없어서 좋으네요".
/// 이 카드는 회원이 이미 맺은 관계 하나를 보여줄 뿐이다.
class HomeCoachCard extends ConsumerWidget {
  const HomeCoachCard({
    super.key,
    required this.trainerId,
    this.trainerName,
    this.trainerInactive = false,
  });

  final String trainerId;

  /// 패스가 들고 있는 이름 — 스태프 캐시가 아직 없을 때의 폴백.
  final String? trainerName;

  /// 담당 코치 퇴사(계약 v2.0). 정상 흐름에선 미래 예약이 남아 있으면 퇴사가 409로
  /// 막히지만, 서버가 규칙을 어겼을 때 이름만 멀쩡히 보여주지 않도록 들고 있는다.
  final bool trainerInactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 홈이 이미 watch하는 캐시다 — 이 카드 때문에 왕복이 늘지 않는다.
    // 로딩 여부까지 보는 이유는 아래 재시도 탭 주석 참조.
    final staffAsync = ref.watch(staffMapProvider);
    final staffMap = staffAsync.value;
    final cached = staffMap?[trainerId];

    // 캐시 미로드/실패면 이름만 채운 폴백을 만든다. 예약 탭이 프로필 시트를 여는
    // 방식과 같다 — 모르는 걸 "퇴사"로 단정하는 쪽이 훨씬 나쁘다(계약 v2.0 승격 규약).
    final staff =
        cached ??
        StaffDto(
          uid: trainerId,
          name: CoachLabel.resolve(trainerName, fallback: '담당 코치'),
        );
    final unavailable = cached == null;
    final profile = staff.profile;
    final inactive = staff.isInactive || trainerInactive;

    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseCardHeader(title: '담당 코치'),
          InkWell(
            // **"탭해서 다시 시도"는 진짜로 다시 읽는다.** 종전엔 캐시가 없어도
            // 프로필 시트를 열었는데, 그 시트는 같은 실패 캐시로 만들어져 "새로고침
            // 후 다시 시도해주세요"라며 회원을 홈으로 되돌렸다 — 카드가 약속한
            // 행동(재시도)과 실제 동작(같은 실패를 한 겹 더 보여주기)이 갈렸다.
            // 이제 캐시가 없을 때만 무효화하고, 결과는 이 카드가 그 자리에서 보여준다
            // (아래 [_subtitle]이 로딩·실패를 나눠 말한다).
            onTap: () {
              if (unavailable) {
                ref.invalidate(staffMapProvider);
                return;
              }
              showTrainerProfileSheet(context, staff: staff);
            },
            child: RiseRow(
              showDivider: false,
              minHeight: 44,
              child: Row(
                children: [
                  TrainerAvatar(
                    name: staff.name,
                    photoUrl: profile.photoUrl,
                    colorHex: staff.color,
                    size: 44,
                    inactive: inactive,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                staff.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (inactive) ...[
                              const SizedBox(width: 5),
                              const RiseBadge(
                                '퇴사',
                                variant: RiseBadgeVariant.muted,
                              ),
                            ],
                          ],
                        ),
                        // 한 줄 요약이 없으면(미등록·퇴사 마스킹) 줄 자체를 만들지
                        // 않는다 — 빈 줄이 남으면 "불러오다 만" 것처럼 보인다.
                        if (_subtitle(profile, unavailable, staffAsync.isLoading)
                            case final sub?)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              sub,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const RiseIcon(
                    RiseIcons.chevronRight,
                    size: 14,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
          // 전문분야는 회원이 "내 코치가 뭘 하는 사람인지"를 한눈에 읽는 자리다.
          // 최대 3개 — 그 이상은 카드가 프로필 시트를 대신하려 든다.
          if (profile.specialties.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final s in profile.specialties.take(3)) _SpecialtyTag(s),
              ],
            ),
          ],
          // 센터 코치 전체 보기(P41) — "이 코치 말고 다른 분은?"이 드는 순간이
          // 정확히 이 카드 앞이다. 데이터는 같은 staffMap 캐시라 비용 0이고,
          // 마이 탭 센터 카드의 같은 진입점과 같은 시트를 연다.
          InkWell(
            onTap: () => showCenterCoachesSheet(context),
            child: const RiseRow(
              showDivider: false,
              minHeight: 44,
              child: Text(
                '센터의 다른 코치 보기',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
              trailing: RiseIcon(
                RiseIcons.chevronRight,
                size: 13,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 이름 아래 한 줄 — 직함과 연차 중 있는 것만 잇는다.
  ///
  /// 캐시가 없으면 "불러오지 못했어요"라고 말한다. 그 상태로 조용히 이름만 보여주면
  /// 회원은 코치가 소개를 안 쓴 줄 안다(프로필 시트가 세 갈래로 나눠 말하는 것과 같은 이유).
  ///
  /// [loading]이 참이면 다시 읽는 중이다 — 탭한 회원이 **아무 변화도 못 보면** 그
  /// 탭이 먹혔는지 알 수 없어 같은 자리를 계속 누르게 된다. 재시도의 유일한 피드백이라
  /// 문구를 나눈다.
  String? _subtitle(StaffProfileDto p, bool unavailable, bool loading) {
    if (unavailable) {
      return loading ? '프로필을 불러오는 중이에요' : '프로필을 불러오지 못했어요 — 탭해서 다시 시도';
    }
    final parts = <String>[
      if (p.title.isNotEmpty) p.title,
      if (p.careerYears > 0) '${p.careerYears}년차',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _SpecialtyTag extends StatelessWidget {
  const _SpecialtyTag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.line.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
      ),
    );
  }
}
