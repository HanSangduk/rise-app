import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/rise_error_view.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';
import 'package:rise_member/features/records/presentation/widgets/body_photo_timeline.dart';
import 'package:rise_member/features/records/presentation/widgets/inbody_add_sheet.dart';
import 'package:rise_member/features/records/presentation/widgets/inbody_chart.dart';
import 'package:rise_member/features/records/presentation/widgets/inbody_metric_rows.dart';
import 'package:rise_member/features/records/presentation/widgets/inbody_recent_list.dart';
import 'package:rise_member/features/records/presentation/widgets/workout_log_list.dart';

/// 기록 탭 — 운동/인바디/체형 분석 세그먼트(목업 t-log).
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recordsViewModelProvider);
    final tab = ref.watch(selectedRecordsTabProvider);

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(title: const Text('기록')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: _Segmented(
              selected: tab,
              onSelect: (t) => ref.read(selectedRecordsTabProvider.notifier).select(t),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.red)),
              error: (e, _) => RiseErrorView(
                message: e is Failure ? e.message : null,
                // 탭 공통 재시도 규약: 정책도 동반 재조회 — 실패 폴백이 세션 내내
                // 고착되지 않게(center_policy_provider 주석 참조).
                onRetry: () {
                  ref.invalidate(centerPolicyProvider);
                  ref.invalidate(recordsViewModelProvider);
                },
              ),
              data: (data) => RefreshIndicator(
                color: AppColors.red,
                onRefresh: () async => ref.read(recordsViewModelProvider.notifier).refresh(),
                child: ListView(
                  // 콘텐츠가 화면보다 짧아도 pull-to-refresh 당김이 동작하게.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                  children: [
                    switch (tab) {
                      RecordsTab.workout => WorkoutLogList(
                          logs: data.workoutLogs,
                          homeworkWeeks: data.homeworkWeeks,
                          homeworkWeeksFailed: data.homeworkWeeksFailed,
                        ),
                      RecordsTab.inbody => _InbodyTab(records: data.inbodyRecords),
                      RecordsTab.bodycheck => BodyPhotoTimelineCard(
                          album: data.bodyPhotos,
                          // 포즈 칩 라벨·순서는 회원 시퀀스를 따른다(계약 v2.10).
                          // 못 받으면 폴백 4종 — 사진이 사라지지는 않는다(합집합 규칙).
                          poses: ref.watch(myProfileProvider).asData?.value.bodyPoses
                                  ?.map((p) => PoseSpec(p.key, p.label))
                                  .toList(growable: false) ??
                              PoseSpec.fallbackSequence,
                          failed: data.bodyPhotosFailed,
                          // 뷰어에서 지우면 목록을 다시 받는다. 서버는 회원 삭제를
                          // **즉시 완전 파기**하므로 갱신하지 않으면 방금 없앤 사진이
                          // 그대로 남아 삭제가 거짓말이 된다.
                          onPhotoDeleted: () =>
                              ref.read(recordsViewModelProvider.notifier).refresh(),
                        ),
                    },
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.selected, required this.onSelect});
  final RecordsTab selected;
  final ValueChanged<RecordsTab> onSelect;

  static const _labels = {
    RecordsTab.workout: '운동',
    RecordsTab.inbody: '인바디',
    RecordsTab.bodycheck: '체형 분석',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      // 목업은 여기만 #eee로 예외를 뒀지만, 같은 화면에 회색 두 종이 공존할 이유가
      // 없어 팔레트의 chipBg(#f3f4f6)로 흡수했다 — 유일한 실제 색 변경(H2).
      decoration: BoxDecoration(color: AppColors.chipBg, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Row(
        children: [
          for (final t in RecordsTab.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(t),
                child: Container(
                  // 세그먼트 3칸이 기록 탭의 유일한 전환 수단 — 44dp까지 올린다.
                  // 알약 배경이 함께 커지지만 세그먼트는 배경이 곧 타깃이라 의도대로다.
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t == selected ? AppColors.red : Colors.transparent,
                    // 8은 바깥 알약(10) 안쪽에 끼는 목업 값 — 토큰으로 올리지 않는다.
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _labels[t]!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: t == selected ? Colors.white : AppColors.chipFg,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InbodyTab extends StatelessWidget {
  const _InbodyTab({required this.records});
  final List<InbodyRecord> records;

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseCardHeader(
            title: '인바디 추이',
            // FAB도 촬영 탭도 아니라 이 카드의 헤더 슬롯이다: 같은 탭의 체형
            // 카드가 이미 같은 자리를 쓰고 있고(body_photo_timeline), 기록 탭
            // Scaffold에 FAB를 달면 운동·체형 서브탭에서도 떠서 맥락이 깨진다
            // (앱 전체에 FloatingActionButton이 0개인 것도 그 이유다).
            trailing: RiseButton(
              label: '기록 추가',
              small: true,
              style: RiseButtonStyleKind.outline,
              onPressed: () => showInbodyAddSheet(context),
            ),
          ),
          InbodyChart(records: records),
          if (records.isNotEmpty) ...[
            // 6지표 전부 + 방향 인식 델타. 종전엔 SMM/PBF 2행만 하드코딩돼 있어
            // 나머지 4개는 서버에서 도메인까지 다 와서 여기서 버려졌다.
            InbodyMetricRows(
              latest: records.last,
              // 오래된 순 정렬(RecordsData 규약)이므로 직전 측정은 끝에서 두 번째.
              previous: records.length >= 2 ? records[records.length - 2] : null,
            ),
            // 정정 경로 — 이게 없으면 회원의 오입력이 차트에 영구히 남는다.
            InbodyRecentList(records: records),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '아직 인바디 기록이 없어요 — 위 "기록 추가"로 결과지 숫자를 남겨보세요',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}
