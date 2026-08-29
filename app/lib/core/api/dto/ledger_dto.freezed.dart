// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ledger_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LedgerDto {

 String get id;@JsonKey(name: 'pass_id') String get passId;@JsonKey(name: 'member_id') String get memberId; int get delta; String get reason;// issue|complete|noshow|noshow_waived|revert|refund|hold|resume|transfer
@JsonKey(name: 'ref_booking_id') String? get refBookingId; String? get by; String get at;
/// Create a copy of LedgerDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LedgerDtoCopyWith<LedgerDto> get copyWith => _$LedgerDtoCopyWithImpl<LedgerDto>(this as LedgerDto, _$identity);

  /// Serializes this LedgerDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LedgerDto&&(identical(other.id, id) || other.id == id)&&(identical(other.passId, passId) || other.passId == passId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.delta, delta) || other.delta == delta)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.refBookingId, refBookingId) || other.refBookingId == refBookingId)&&(identical(other.by, by) || other.by == by)&&(identical(other.at, at) || other.at == at));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,passId,memberId,delta,reason,refBookingId,by,at);

@override
String toString() {
  return 'LedgerDto(id: $id, passId: $passId, memberId: $memberId, delta: $delta, reason: $reason, refBookingId: $refBookingId, by: $by, at: $at)';
}


}

/// @nodoc
abstract mixin class $LedgerDtoCopyWith<$Res>  {
  factory $LedgerDtoCopyWith(LedgerDto value, $Res Function(LedgerDto) _then) = _$LedgerDtoCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'pass_id') String passId,@JsonKey(name: 'member_id') String memberId, int delta, String reason,@JsonKey(name: 'ref_booking_id') String? refBookingId, String? by, String at
});




}
/// @nodoc
class _$LedgerDtoCopyWithImpl<$Res>
    implements $LedgerDtoCopyWith<$Res> {
  _$LedgerDtoCopyWithImpl(this._self, this._then);

  final LedgerDto _self;
  final $Res Function(LedgerDto) _then;

/// Create a copy of LedgerDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? passId = null,Object? memberId = null,Object? delta = null,Object? reason = null,Object? refBookingId = freezed,Object? by = freezed,Object? at = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,passId: null == passId ? _self.passId : passId // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,delta: null == delta ? _self.delta : delta // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,refBookingId: freezed == refBookingId ? _self.refBookingId : refBookingId // ignore: cast_nullable_to_non_nullable
as String?,by: freezed == by ? _self.by : by // ignore: cast_nullable_to_non_nullable
as String?,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [LedgerDto].
extension LedgerDtoPatterns on LedgerDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LedgerDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LedgerDto() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LedgerDto value)  $default,){
final _that = this;
switch (_that) {
case _LedgerDto():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LedgerDto value)?  $default,){
final _that = this;
switch (_that) {
case _LedgerDto() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'pass_id')  String passId, @JsonKey(name: 'member_id')  String memberId,  int delta,  String reason, @JsonKey(name: 'ref_booking_id')  String? refBookingId,  String? by,  String at)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LedgerDto() when $default != null:
return $default(_that.id,_that.passId,_that.memberId,_that.delta,_that.reason,_that.refBookingId,_that.by,_that.at);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'pass_id')  String passId, @JsonKey(name: 'member_id')  String memberId,  int delta,  String reason, @JsonKey(name: 'ref_booking_id')  String? refBookingId,  String? by,  String at)  $default,) {final _that = this;
switch (_that) {
case _LedgerDto():
return $default(_that.id,_that.passId,_that.memberId,_that.delta,_that.reason,_that.refBookingId,_that.by,_that.at);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'pass_id')  String passId, @JsonKey(name: 'member_id')  String memberId,  int delta,  String reason, @JsonKey(name: 'ref_booking_id')  String? refBookingId,  String? by,  String at)?  $default,) {final _that = this;
switch (_that) {
case _LedgerDto() when $default != null:
return $default(_that.id,_that.passId,_that.memberId,_that.delta,_that.reason,_that.refBookingId,_that.by,_that.at);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LedgerDto implements LedgerDto {
  const _LedgerDto({required this.id, @JsonKey(name: 'pass_id') required this.passId, @JsonKey(name: 'member_id') required this.memberId, required this.delta, required this.reason, @JsonKey(name: 'ref_booking_id') this.refBookingId, this.by, required this.at});
  factory _LedgerDto.fromJson(Map<String, dynamic> json) => _$LedgerDtoFromJson(json);

@override final  String id;
@override@JsonKey(name: 'pass_id') final  String passId;
@override@JsonKey(name: 'member_id') final  String memberId;
@override final  int delta;
@override final  String reason;
// issue|complete|noshow|noshow_waived|revert|refund|hold|resume|transfer
@override@JsonKey(name: 'ref_booking_id') final  String? refBookingId;
@override final  String? by;
@override final  String at;

/// Create a copy of LedgerDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LedgerDtoCopyWith<_LedgerDto> get copyWith => __$LedgerDtoCopyWithImpl<_LedgerDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LedgerDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LedgerDto&&(identical(other.id, id) || other.id == id)&&(identical(other.passId, passId) || other.passId == passId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.delta, delta) || other.delta == delta)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.refBookingId, refBookingId) || other.refBookingId == refBookingId)&&(identical(other.by, by) || other.by == by)&&(identical(other.at, at) || other.at == at));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,passId,memberId,delta,reason,refBookingId,by,at);

@override
String toString() {
  return 'LedgerDto(id: $id, passId: $passId, memberId: $memberId, delta: $delta, reason: $reason, refBookingId: $refBookingId, by: $by, at: $at)';
}


}

/// @nodoc
abstract mixin class _$LedgerDtoCopyWith<$Res> implements $LedgerDtoCopyWith<$Res> {
  factory _$LedgerDtoCopyWith(_LedgerDto value, $Res Function(_LedgerDto) _then) = __$LedgerDtoCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'pass_id') String passId,@JsonKey(name: 'member_id') String memberId, int delta, String reason,@JsonKey(name: 'ref_booking_id') String? refBookingId, String? by, String at
});




}
/// @nodoc
class __$LedgerDtoCopyWithImpl<$Res>
    implements _$LedgerDtoCopyWith<$Res> {
  __$LedgerDtoCopyWithImpl(this._self, this._then);

  final _LedgerDto _self;
  final $Res Function(_LedgerDto) _then;

/// Create a copy of LedgerDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? passId = null,Object? memberId = null,Object? delta = null,Object? reason = null,Object? refBookingId = freezed,Object? by = freezed,Object? at = null,}) {
  return _then(_LedgerDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,passId: null == passId ? _self.passId : passId // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,delta: null == delta ? _self.delta : delta // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,refBookingId: freezed == refBookingId ? _self.refBookingId : refBookingId // ignore: cast_nullable_to_non_nullable
as String?,by: freezed == by ? _self.by : by // ignore: cast_nullable_to_non_nullable
as String?,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
