// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbody_sheet_reader.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(inbodySheetReader)
const inbodySheetReaderProvider = InbodySheetReaderProvider._();

final class InbodySheetReaderProvider
    extends
        $FunctionalProvider<
          InbodySheetReader,
          InbodySheetReader,
          InbodySheetReader
        >
    with $Provider<InbodySheetReader> {
  const InbodySheetReaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inbodySheetReaderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inbodySheetReaderHash();

  @$internal
  @override
  $ProviderElement<InbodySheetReader> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  InbodySheetReader create(Ref ref) {
    return inbodySheetReader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(InbodySheetReader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<InbodySheetReader>(value),
    );
  }
}

String _$inbodySheetReaderHash() => r'c183bfb4533ac6066d43e185d51bc3f0cc7b221f';
