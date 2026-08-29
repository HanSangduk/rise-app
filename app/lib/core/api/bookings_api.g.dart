// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookings_api.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(bookingsApi)
const bookingsApiProvider = BookingsApiProvider._();

final class BookingsApiProvider
    extends $FunctionalProvider<BookingsApi, BookingsApi, BookingsApi>
    with $Provider<BookingsApi> {
  const BookingsApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookingsApiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookingsApiHash();

  @$internal
  @override
  $ProviderElement<BookingsApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BookingsApi create(Ref ref) {
    return bookingsApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BookingsApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BookingsApi>(value),
    );
  }
}

String _$bookingsApiHash() => r'7b88f9b9a4b849a1c8b1758f40e07b40033d754e';
