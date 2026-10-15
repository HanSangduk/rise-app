import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/api/passes_api.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/network/dio_client.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/features/my/data/my_remote_data_source.dart';
import 'package:rise_member/features/my/data/my_repository_impl.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/domain/my_repository.dart';

part 'my_view_model.g.dart';

@riverpod
MyRepository myRepository(Ref ref) {
  final dio = ref.watch(dioProvider);
  return MyRepositoryImpl(
    ref.watch(passesApiProvider),
    // StaffDirectory 직접 주입 금지 — 캐시(staffMapProvider)를 우회하게 된다.
    ref.watch(staffMapReaderProvider),
    MyRemoteDataSource(dio),
    ref.watch(memberApiProvider),
  );
}

@riverpod
class MyViewModel extends _$MyViewModel {
  @override
  Future<MySummary> build() async {
    final memberId = ref.watch(sessionProvider)?.memberId;
    if (memberId == null) {
      // 셸이 떠 있는 채 세션이 비었다 — 리스너가 이동 중이라 문구가 아닌 타입만 낸다(P64).
      throw const SessionGoneFailure();
    }
    final repo = ref.watch(myRepositoryProvider);
    return _unwrap(await repo.load(memberId));
  }

  T _unwrap<T>(Result<T> r) => switch (r) {
        Ok<T>(:final value) => value,
        Err<T>(:final failure) => throw failure,
      };

  void refresh() => ref.invalidateSelf();

  Future<Result<void>> requestHold({
    required String passId,
    required DateTime from,
    required DateTime to,
    String? reason,
  }) async {
    final repo = ref.read(myRepositoryProvider);
    final result = await repo.requestHold(passId: passId, from: from, to: to, reason: reason);
    if (result case Ok()) {
      // 홈의 "일시정지 중" 배지·예약 탭 홀드 차단이 같은 holds를 보므로 동반 갱신
      // (booking은 homeViewModelProvider watch 연쇄로 자동 재빌드 — 크로스탭 stale 방지).
      ref.invalidate(homeViewModelProvider);
      refresh();
    }
    return result;
  }

  Future<Result<void>> resumeHold(String passId) async {
    final repo = ref.read(myRepositoryProvider);
    final result = await repo.resumeHold(passId);
    if (result case Ok()) {
      // 재개 직후 홈 배지가 "일시정지 중"으로 남지 않게 동반 갱신.
      ref.invalidate(homeViewModelProvider);
      refresh();
    }
    return result;
  }

  Future<Result<void>> updateConsent({required bool general, required bool sensitive}) async {
    final memberId = ref.read(sessionProvider)?.memberId;
    if (memberId == null) return const Err(SessionGoneFailure());
    final repo = ref.read(myRepositoryProvider);
    final result = await repo.updateConsent(memberId: memberId, general: general, sensitive: sensitive);
    if (result case Ok()) {
      // 동의 상태의 출처가 둘이다: 이 뷰모델의 MySummary.consent(마이 탭 토글)와
      // [myProfileProvider](체형 촬영 셔터의 동의 게이트·기록 탭 포즈 칩). 종전엔 자기 것만
      // 새로고침해서, 기록 탭이 그 provider를 붙들고 있으면(indexedStack이라 떠나도 산다)
      // 마이 탭에서 동의를 켜도 셔터가 **앱을 껐다 켜기 전까지** "마이 탭에서 동의해주세요"를
      // 냈다 — 안내대로 했는데 풀리지 않는 문(P73). 두 출처를 같은 사건에 함께 비운다.
      ref.invalidate(myProfileProvider);
      refresh();
    }
    return result;
  }

  /// 계약 자체서명(POST /v1/contracts/{id}/sign, v1.4 · P44 서명 이미지 동봉) —
  /// 성공 시 마이 탭 새로고침(서명 완료 단계의 [계약서 보기]가 이 재조회 결과를 기다린다).
  Future<Result<void>> signContract(String contractId, {String? signaturePng}) async {
    final repo = ref.read(myRepositoryProvider);
    final result = await repo.signContract(contractId, signaturePng: signaturePng);
    if (result case Ok()) refresh();
    return result;
  }

  /// 회원탈퇴(DELETE /v1/me, v2.11). **되돌릴 수 없다.**
  ///
  /// 다른 뮤테이션과 달리 성공해도 `refresh()`를 부르지 않는다 — 재조회는 이제 403으로만
  /// 끝나고(UserIndex가 사라졌다), 그 실패가 화면에 뜨면 방금 성공한 탈퇴가 에러로 보인다.
  /// 화면 정리는 호출측이 로그아웃 + `/login` 이동으로 한다.
  Future<Result<AccountDeletionSummary>> deleteAccount() {
    return ref.read(myRepositoryProvider).deleteAccount();
  }
}

/// 마이 탭 원장 카드에서 선택된 패스 id(null = 대표 패스) —
/// 패스가 2개 이상일 때 칩으로 원장을 전환한다.
@riverpod
class SelectedLedgerPassId extends _$SelectedLedgerPassId {
  @override
  String? build() => null;

  void select(String passId) => state = passId;
}
