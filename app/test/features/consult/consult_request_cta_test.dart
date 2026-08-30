import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/consult_request_dto.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/consult/data/consult_api.dart';
import 'package:rise_member/features/consult/presentation/consult_providers.dart';
import 'package:rise_member/features/consult/presentation/widgets/consult_request_cta.dart';

// P42 — 재등록 요청 CTA: 데드엔드에 놓는 손잡이의 세 상태(요청 가능 / 보냄 / 조회 실패)와
// 시트 제출 흐름. 중복 방어의 최종선은 서버 409라 CTA는 fail-open이 규약이다.
class _FakeConsultApi extends ConsultApi {
  _FakeConsultApi({this.mine = const [], this.createError}) : super(Dio());

  List<ConsultRequestDto> mine;
  final DioException? createError;
  final created = <String>[]; // 보낸 note 기록

  @override
  Future<List<ConsultRequestDto>> fetchMine() async => mine;

  @override
  Future<ConsultRequestDto> create({
    required String kind,
    String note = '',
  }) async {
    if (createError != null) throw createError!;
    created.add(note);
    final dto = ConsultRequestDto(
      id: 'c${created.length}',
      kind: kind,
      note: note,
    );
    mine = [...mine, dto];
    return dto;
  }
}

DioException _conflict(String message) => DioException(
  requestOptions: RequestOptions(path: '/v1/consult-requests'),
  response: Response(
    requestOptions: RequestOptions(path: '/v1/consult-requests'),
    statusCode: 409,
    data: {'error': message},
  ),
  type: DioExceptionType.badResponse,
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    _FakeConsultApi api, {
    bool compact = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [consultApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(child: ConsultRequestCta(compact: compact)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('요청 없음 — 버튼이 뜨고, 시트에서 보내면 "요청 보냈어요" 상태로 바뀐다', (tester) async {
    final api = _FakeConsultApi();
    await pump(tester, api);

    await tester.tap(find.text('재등록 요청하기'));
    await tester.pumpAndSettle();

    // 시트 — 결제가 아니라 연락이라는 기대 설정 문구.
    expect(find.textContaining('결제·등록은 센터에서 상담 후 진행돼요'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '주 2회로 다시 하고 싶어요');
    await tester.tap(find.text('요청 보내기'));
    await tester.pumpAndSettle();

    expect(api.created, ['주 2회로 다시 하고 싶어요']);
    // 시트가 닫히고 CTA가 상태 문구로 교체 — 손잡이가 이중 제출 표면으로 남지 않는다.
    expect(find.text('요청 보내기'), findsNothing);
    expect(find.textContaining('재등록 요청을 보냈어요'), findsWidgets);
    expect(find.text('재등록 요청하기'), findsNothing);
  });

  testWidgets('pending이 이미 있으면 버튼 대신 상태 문구 — 눌러서 409 받는 흐름을 만들지 않는다', (
    tester,
  ) async {
    final api = _FakeConsultApi(mine: [const ConsultRequestDto(id: 'c1')]);
    await pump(tester, api);

    expect(find.text('재등록 요청하기'), findsNothing);
    expect(find.textContaining('재등록 요청을 보냈어요'), findsOneWidget);
  });

  testWidgets('done뿐이면 다시 요청할 수 있다 — 재등록은 반복되는 일', (tester) async {
    final api = _FakeConsultApi(
      mine: [const ConsultRequestDto(id: 'c1', status: 'done')],
    );
    await pump(tester, api);

    expect(find.text('재등록 요청하기'), findsOneWidget);
  });

  testWidgets('409(다른 기기에서 이미 보냄) — 서버 문구를 시트에 그대로, CTA는 재조회로 상태 복원', (
    tester,
  ) async {
    final api = _FakeConsultApi(
      createError: _conflict('이미 보낸 요청이 있어요 — 센터에서 곧 연락드릴 거예요'),
    );
    await pump(tester, api);

    await tester.tap(find.text('재등록 요청하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('요청 보내기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('이미 보낸 요청이 있어요'), findsOneWidget);
  });

  testWidgets('compact — 배지 줄용 소형 링크도 같은 시트를 연다', (tester) async {
    final api = _FakeConsultApi();
    await pump(tester, api, compact: true);

    await tester.tap(find.text('재등록 요청하기 ›'));
    await tester.pumpAndSettle();

    expect(find.text('요청 보내기'), findsOneWidget);
  });
}
