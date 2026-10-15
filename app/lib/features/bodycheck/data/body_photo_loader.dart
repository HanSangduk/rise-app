import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/bodycheck/domain/body_photo_storage_path.dart';

part 'body_photo_loader.g.dart';

/// 저장된 체형 사진 바이트를 받아온다.
///
/// **`getDownloadURL`을 쓰지 않는다.** 그 API가 만드는 토큰 URL은 Storage 규칙을 거치지
/// 않는 **무기한 열쇠**다(`storage.rules` 헤더 주석 · `body_photo_uploader.dart` 주석에서
/// 이미 두 번 배제한 이유). 체형사진은 계약 P8 민감정보이므로 매 접근마다 규칙 평가를
/// 지나는 `getData`가 유일하게 맞다 — 동의를 철회한 순간부터 실제로 막혀야 한다.
abstract class BodyPhotoLoader {
  /// [storagePath]의 바이트. 실패는 사용자향 한국어 [Failure]로 돌려준다.
  Future<Result<Uint8List>> load(String storagePath);

  /// 이미 받아 둔 바이트가 있으면 **동기로** 준다(없으면 null). 네트워크를 타지 않는다.
  ///
  /// [load]는 캐시 히트여도 `async`라 마이크로태스크 한 틱 뒤에 완료되고, 그 사이
  /// `FutureBuilder`는 `connectionState != done`을 보고 **스피너를 한 프레임 그린다**.
  /// 날짜 스크러버는 손잡이를 좌우로 까딱해 두 날짜를 번갈아 보는 게 핵심 사용법인데
  /// (블링크 비교), 그때마다 흰 스피너가 번쩍이면 **비교 자체가 성립하지 않는다** —
  /// 눈이 좇아야 할 차이가 깜빡임에 묻힌다.
  Uint8List? peek(String storagePath);

  /// 이 사진의 바이트를 캐시에서 뺀다 — **삭제와 반드시 짝이 되어야 한다.**
  ///
  /// 인스턴스 메서드인 이유: static이면 삭제 경로가 구현체에 직접 묶여서, "정말
  /// 비웠는가"를 실제 Firebase 없이 확인할 방법이 없다. 실제로 이 자리에서
  /// 뮤테이션 하나가 살아남았다 — evict 호출을 지워도 테스트가 전부 통과했다.
  void evict(String storagePath);

  /// 캐시를 통째로 비운다 — **세션이 끊길 때 부른다.**
  ///
  /// 바이트 캐시는 프로세스 수명을 따라가므로 로그아웃해도 그대로 남는다. 한 기기를
  /// 두 회원이 번갈아 쓰면(센터 태블릿, 가족) 다음 회원 화면에 **이전 회원의 P8
  /// 민감정보**가 그려질 수 있다. 비우는 함수는 처음부터 있었는데 부르는 곳이 0개였다.
  void clear();
}

class FirebaseBodyPhotoLoader implements BodyPhotoLoader {
  FirebaseBodyPhotoLoader([FirebaseStorage? storage]) : _storage = storage;

  /// 지연 획득 — 생성 시점에 [FirebaseStorage.instance]를 건드리면 Firebase를 초기화하지
  /// 않는 위젯 테스트에서 provider를 읽는 것만으로 터진다(업로더와 같은 이유).
  final FirebaseStorage? _storage;
  FirebaseStorage get _ref => _storage ?? FirebaseStorage.instance;

  /// 경로 → 바이트 캐시.
  ///
  /// 경로가 stale이 될 수 없는 근거: 파일명에 촬영 시각(epochMillis)이 박혀 **같은 경로가
  /// 다른 사진을 가리키는 일이 없고**, 규칙이 클라이언트 덮어쓰기를 막는다.
  ///
  /// **단, "영원히 유효"는 아니다.** v2.13부터 서버가 파기를 집행하므로(회원 삭제는 즉시,
  /// 스태프 삭제는 30일 뒤) 지워진 사진의 바이트가 캐시에 남을 수 있다 — 그래서
  /// [evict]가 삭제와 짝을 이룬다.
  ///
  /// **디스크에 쓰지 않는다** — 업로드가 `no-store`로 올린 민감정보를 앱이 디스크에
  /// 남기면 그 의도가 무의미해진다. 프로세스가 죽으면 같이 사라지는 게 맞다.
  ///
  /// **개수 상한이 있다**([maxEntries], P74). 종전엔 로그아웃 전까지 본 사진의 원본 바이트가 전부
  /// 쌓였다 — 타임라인을 오가며 포즈 4종 × 촬영 수십 회를 보면 수십 MB가 세션 내내 남는다. Dart의
  /// `Map`은 삽입 순서를 지키므로 "가장 오래 전에 넣은 것"을 첫 키로 지우는 단순 LRU-ish로 충분하다
  /// (읽기 히트 시 뒤로 옮겨 최근 사용을 살린다 — 비교 화면이 두 장을 번갈아 읽는다).
  static final _cache = <String, Uint8List>{};
  static const maxEntries = 40;

  /// 비운 횟수 — [load]가 받는 **도중에** 세션이 끝나면(로그아웃·401 → [clear]) 그 뒤에 도착한
  /// 바이트를 넣지 않기 위한 표식(P74). 맵만 비우면 느린 망에서 이전 회원의 사진이 다음 회원의
  /// 세션 캐시로 다시 들어온다. 오르는 것은 세션 경계뿐이라 같은 세션 안의 동시 로드끼리는 서로를
  /// 무효화하지 않는다.
  static int _epoch = 0;

  /// 회원이 바뀌면 남의 사진이 캐시에 남아 있으면 안 된다.
  static void clearCache() {
    _epoch++;
    _cache.clear();
  }

  static void _put(String storagePath, Uint8List bytes) {
    _cache.remove(storagePath); // 있던 항목은 뒤로 옮긴다(삽입 순서 = 최근 사용 순서)
    _cache[storagePath] = bytes;
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  static Uint8List? _hit(String storagePath) {
    final bytes = _cache.remove(storagePath);
    if (bytes != null) _cache[storagePath] = bytes; // 최근 사용으로 갱신
    return bytes;
  }

  /// 시험 전용 — Firebase 없이 캐시를 채운다(상한·최근 사용 순서). 읽기 히트·받아 온 바이트의 배선은
  /// 실제 [peek]·[load]로 잰다(시험이 이 static만 부르면 `load`가 캐시를 우회해도 초록이었다).
  @visibleForTesting
  static void debugPut(String storagePath, Uint8List bytes) => _put(storagePath, bytes);

  /// 시험 전용 — 지금 캐시에 든 경로를 오래된 순으로.
  @visibleForTesting
  static List<String> debugCachedPaths() => List.unmodifiable(_cache.keys);

  @override
  void clear() => clearCache();

  /// 종전엔 전체 비우기([clearCache])뿐이었고 그마저 호출자가 0개였다. 삭제는
  /// 성공했는데 목록 갱신이 실패하면(비행기 모드로 들어가는 등) "완전히 지워졌다"고
  /// 들은 사진이 캐시에서 그대로 다시 그려진다. 회원에겐 삭제가 거짓말이 된다.
  @override
  void evict(String storagePath) => _cache.remove(storagePath);

  @override
  Uint8List? peek(String storagePath) => _hit(storagePath);

  @override
  Future<Result<Uint8List>> load(String storagePath) async {
    if (storagePath.trim().isEmpty) {
      // 서버가 v2.10부터 빈 경로를 400으로 막지만, 그 이전에 저장된 레코드가 남아 있다.
      return const Err(RejectedFailure('사진 파일 정보가 없어요 — 다시 촬영해주세요'));
    }
    final hit = _hit(storagePath);
    if (hit != null) return Ok(hit);

    final epoch = _epoch;
    try {
      // maxSize를 명시한다 — 규칙의 10MB 상한과 같은 값. 기본값(10MB)에 기대지 않는 이유는
      // 그 기본이 바뀌면 조용히 동작이 달라지기 때문이고, 무엇보다 **의도를 코드에 남기려는**
      // 것이다(업로더도 같은 상수를 쓴다).
      final bytes = await _ref.ref(storagePath).getData(BodyPhotoStoragePath.maxUploadBytes);
      if (bytes == null || bytes.isEmpty) {
        return const Err(UnknownFailure('사진을 불러오지 못했어요 — 다시 시도해주세요'));
      }
      if (epoch == _epoch) _put(storagePath, bytes); // 받는 사이 세션이 끝났으면 캐시에 남기지 않는다
      return Ok(bytes);
    } on FirebaseException catch (e) {
      return Err(_mapFirebase(e));
    } catch (_) {
      return const Err(UnknownFailure('사진을 불러오지 못했어요 — 다시 시도해주세요'));
    }
  }

  /// 읽기 쪽 실패는 쓰기와 원인이 다르다.
  Failure _mapFirebase(FirebaseException e) {
    return switch (e.code) {
      // **동의를 가리키지 않는다.** `storage.rules`의 회원 분기는
      // `myMemberId() == memberId` 하나뿐이라 **본인 사진 읽기에 동의 검사가 없다**
      // (동의를 거는 건 스태프 분기다). 같은 앱의 동의 시트도 "이미 저장된 기록은
      // 그대로 볼 수 있어요"라고 말한다 — 마이 탭으로 보내면 동의는 켜져 있고
      // 회원이 할 수 있는 일은 없다. 여기 403은 세션·클레임 문제다.
      'unauthorized' || 'unauthenticated' => const AuthFailure(
          '사진을 볼 권한이 없어요 — 로그아웃 후 다시 로그인해주세요',
        ),
      // 서버 메타데이터는 있는데 파일이 없는 경우(업로드 중간 실패의 흔적).
      'object-not-found' => const RejectedFailure('사진 파일을 찾지 못했어요'),
      'canceled' => const NetworkFailure('불러오기가 중단됐어요 — 다시 시도해주세요'),
      _ => const NetworkFailure('사진을 불러오지 못했어요 — 네트워크를 확인해주세요'),
    };
  }
}

@riverpod
BodyPhotoLoader bodyPhotoLoader(Ref ref) => FirebaseBodyPhotoLoader();
