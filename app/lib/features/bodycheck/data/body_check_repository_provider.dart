import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/network/dio_client.dart';
import 'package:rise_member/features/bodycheck/data/body_check_remote_data_source.dart';
import 'package:rise_member/features/bodycheck/data/body_check_repository_impl.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';
import 'package:rise_member/features/bodycheck/domain/body_check_repository.dart';

part 'body_check_repository_provider.g.dart';

/// 체형 사진 리포지토리 — **두 feature가 함께 쓴다**(촬영 탭이 쓰고, 기록 탭이 읽는다).
///
/// 원래 `presentation/camera_view_model.dart` 안에 있었다. 그래서
/// `records_view_model.dart`가 이 provider 하나 때문에 **촬영 탭의 뷰모델 파일을
/// import**했고, 반대 방향(업로드 성공 → 기록 탭 무효화)이 순환이 되어 막혔다.
/// 소비자가 둘인 provider는 어느 한쪽 화면의 뷰모델 파일이 아니라 data 레이어에 둔다.
@riverpod
BodyCheckRepository bodyCheckRepository(Ref ref) {
  final dio = ref.watch(dioProvider);
  return BodyCheckRepositoryImpl(
    BodyCheckRemoteDataSource(dio),
    ref.watch(bodyPhotoLoaderProvider),
  );
}
