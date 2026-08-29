import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/bodycheck/domain/body_photo_storage_path.dart';

part 'body_photo_uploader.g.dart';

/// 촬영한 원본 바이트를 Firebase Storage에 올린다. 성공하면 **버킷 내부 경로**를
/// 돌려주고, 그 값이 그대로 `POST /v1/body-photos`의 `storage_path`가 된다.
///
/// 다운로드 URL(`getDownloadURL`)은 일부러 쓰지 않는다 — 토큰이 박힌 영구 URL은
/// 회수하려면 토큰을 갈아야 하고, 서버 DB에 남으면 유출 시 그 자체가 열쇠가 된다
/// (P09에서 공개 버킷을 걷어낸 것과 같은 이유). 경로만 저장하고 열람은 백엔드가
/// 그때그때 서명 URL을 발급하는 쪽이 회수 가능하다.
abstract interface class BodyPhotoUploader {
  Future<Result<String>> upload({
    required String storagePath,
    required Uint8List bytes,
  });
}

class FirebaseBodyPhotoUploader implements BodyPhotoUploader {
  FirebaseBodyPhotoUploader([FirebaseStorage? storage]) : _storage = storage;

  /// 지연 획득 — 생성 시점에 [FirebaseStorage.instance]를 건드리면 Firebase를
  /// 초기화하지 않는 위젯 테스트에서 provider를 읽는 것만으로 터진다.
  final FirebaseStorage? _storage;
  FirebaseStorage get _ref => _storage ?? FirebaseStorage.instance;

  @override
  Future<Result<String>> upload({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    // storage.rules의 isImageUnder10MB()를 클라이언트가 먼저 건다 — 규칙에 걸리면
    // 이유가 안 보이는 403만 돌아오고, 회원은 사진이 왜 안 올라가는지 알 수 없다.
    if (bytes.length >= BodyPhotoStoragePath.maxUploadBytes) {
      return const Err(RejectedFailure(
        '사진 용량이 너무 커요(10MB 이상) — 다시 촬영해주세요',
      ));
    }

    try {
      await _ref.ref(storagePath).putData(
            bytes,
            SettableMetadata(
              contentType: 'image/jpeg',
              // 규칙에서 contentType을 강제하므로 명시가 필수(추론에 맡기지 않는다).
              cacheControl: 'private, max-age=0, no-store',
            ),
          );
      return Ok(storagePath);
    } on FirebaseException catch (e) {
      return Err(_mapFirebase(e));
    } catch (_) {
      return const Err(UnknownFailure('사진을 올리지 못했어요 — 잠시 후 다시 시도해주세요'));
    }
  }

  /// Storage 에러코드 → 회원이 **다음에 뭘 해야 하는지**가 보이는 한국어 문구.
  /// (원문 영어 메시지는 그대로 노출하지 않는다 — 계약 v1.2 "에러 = 사용자향 한국어".)
  Failure _mapFirebase(FirebaseException e) {
    return switch (e.code) {
      // storage.rules가 거부하는 경우는 넷이다: 미로그인 · member_id 불일치 ·
      // 민감정보 동의 없음 · 크기/타입 위반. 규칙은 이유를 돌려주지 않으므로
      // (전부 403) 회원이 스스로 확인할 수 있는 순서대로 적는다.
      'unauthorized' || 'unauthenticated' => const AuthFailure(
          '사진을 저장할 권한이 없어요 — 마이 탭에서 체형 사진 동의를 확인하고, '
          '그래도 안 되면 다시 로그인해주세요',
        ),
      'quota-exceeded' => const RejectedFailure(
          '저장 공간이 가득 찼어요 — 데스크에 알려주세요',
        ),
      'canceled' => const NetworkFailure('업로드가 중단됐어요 — 다시 시도해주세요'),
      _ => const NetworkFailure(
          '사진 업로드에 실패했어요 — 네트워크를 확인하고 다시 시도해주세요',
        ),
    };
  }
}

@riverpod
BodyPhotoUploader bodyPhotoUploader(Ref ref) => FirebaseBodyPhotoUploader();
