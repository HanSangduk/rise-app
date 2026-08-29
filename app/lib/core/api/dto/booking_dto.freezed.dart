// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'booking_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BookingDto {

 String get id;@JsonKey(name: 'slot_key') String get slotKey;@JsonKey(name: 'member_id') String get memberId;@JsonKey(name: 'trainer_id') String get trainerId;@JsonKey(name: 'pass_id') String get passId; String get kind;// pt|group|ot
 String get status;// confirmed|waitlist|cancelled|noshow|completed
@JsonKey(name: 'recurring_id') String? get recurringId;@JsonKey(name: 'created_at') String? get createdAt;
/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BookingDtoCopyWith<BookingDto> get copyWith => _$BookingDtoCopyWithImpl<BookingDto>(this as BookingDto, _$identity);

  /// Serializes this BookingDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BookingDto&&(identical(other.id, id) || other.id == id)&&(identical(other.slotKey, slotKey) || other.slotKey == slotKey)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.passId, passId) || other.passId == passId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&(identical(other.recurringId, recurringId) || other.recurringId == recurringId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,slotKey,memberId,trainerId,passId,kind,status,recurringId,createdAt);

@override
String toString() {
  return 'BookingDto(id: $id, slotKey: $slotKey, memberId: $memberId, trainerId: $trainerId, passId: $passId, kind: $kind, status: $status, recurringId: $recurringId, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $BookingDtoCopyWith<$Res>  {
  factory $BookingDtoCopyWith(BookingDto value, $Res Function(BookingDto) _then) = _$BookingDtoCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'slot_key') String slotKey,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'trainer_id') String trainerId,@JsonKey(name: 'pass_id') String passId, String kind, String status,@JsonKey(name: 'recurring_id') String? recurringId,@JsonKey(name: 'created_at') String? createdAt
});




}
/// @nodoc
class _$BookingDtoCopyWithImpl<$Res>
    implements $BookingDtoCopyWith<$Res> {
  _$BookingDtoCopyWithImpl(this._self, this._then);

  final BookingDto _self;
  final $Res Function(BookingDto) _then;

/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? slotKey = null,Object? memberId = null,Object? trainerId = null,Object? passId = null,Object? kind = null,Object? status = null,Object? recurringId = freezed,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,slotKey: null == slotKey ? _self.slotKey : slotKey // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,passId: null == passId ? _self.passId : passId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,recurringId: freezed == recurringId ? _self.recurringId : recurringId // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BookingDto].
extension BookingDtoPatterns on BookingDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BookingDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BookingDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BookingDto value)  $default,){
final _that = this;
switch (_that) {
case _BookingDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BookingDto value)?  $default,){
final _that = this;
switch (_that) {
case _BookingDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'slot_key')  String slotKey, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'pass_id')  String passId,  String kind,  String status, @JsonKey(name: 'recurring_id')  String? recurringId, @JsonKey(name: 'created_at')  String? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BookingDto() when $default != null:
return $default(_that.id,_that.slotKey,_that.memberId,_that.trainerId,_that.passId,_that.kind,_that.status,_that.recurringId,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'slot_key')  String slotKey, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'pass_id')  String passId,  String kind,  String status, @JsonKey(name: 'recurring_id')  String? recurringId, @JsonKey(name: 'created_at')  String? createdAt)  $default,) {final _that = this;
switch (_that) {
case _BookingDto():
return $default(_that.id,_that.slotKey,_that.memberId,_that.trainerId,_that.passId,_that.kind,_that.status,_that.recurringId,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'slot_key')  String slotKey, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'pass_id')  String passId,  String kind,  String status, @JsonKey(name: 'recurring_id')  String? recurringId, @JsonKey(name: 'created_at')  String? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _BookingDto() when $default != null:
return $default(_that.id,_that.slotKey,_that.memberId,_that.trainerId,_that.passId,_that.kind,_that.status,_that.recurringId,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BookingDto implements BookingDto {
  const _BookingDto({required this.id, @JsonKey(name: 'slot_key') required this.slotKey, @JsonKey(name: 'member_id') required this.memberId, @JsonKey(name: 'trainer_id') required this.trainerId, @JsonKey(name: 'pass_id') required this.passId, required this.kind, this.status = 'confirmed', @JsonKey(name: 'recurring_id') this.recurringId, @JsonKey(name: 'created_at') this.createdAt});
  factory _BookingDto.fromJson(Map<String, dynamic> json) => _$BookingDtoFromJson(json);

@override final  String id;
@override@JsonKey(name: 'slot_key') final  String slotKey;
@override@JsonKey(name: 'member_id') final  String memberId;
@override@JsonKey(name: 'trainer_id') final  String trainerId;
@override@JsonKey(name: 'pass_id') final  String passId;
@override final  String kind;
// pt|group|ot
@override@JsonKey() final  String status;
// confirmed|waitlist|cancelled|noshow|completed
@override@JsonKey(name: 'recurring_id') final  String? recurringId;
@override@JsonKey(name: 'created_at') final  String? createdAt;

/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BookingDtoCopyWith<_BookingDto> get copyWith => __$BookingDtoCopyWithImpl<_BookingDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BookingDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BookingDto&&(identical(other.id, id) || other.id == id)&&(identical(other.slotKey, slotKey) || other.slotKey == slotKey)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.passId, passId) || other.passId == passId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&(identical(other.recurringId, recurringId) || other.recurringId == recurringId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,slotKey,memberId,trainerId,passId,kind,status,recurringId,createdAt);

@override
String toString() {
  return 'BookingDto(id: $id, slotKey: $slotKey, memberId: $memberId, trainerId: $trainerId, passId: $passId, kind: $kind, status: $status, recurringId: $recurringId, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$BookingDtoCopyWith<$Res> implements $BookingDtoCopyWith<$Res> {
  factory _$BookingDtoCopyWith(_BookingDto value, $Res Function(_BookingDto) _then) = __$BookingDtoCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'slot_key') String slotKey,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'trainer_id') String trainerId,@JsonKey(name: 'pass_id') String passId, String kind, String status,@JsonKey(name: 'recurring_id') String? recurringId,@JsonKey(name: 'created_at') String? createdAt
});




}
/// @nodoc
class __$BookingDtoCopyWithImpl<$Res>
    implements _$BookingDtoCopyWith<$Res> {
  __$BookingDtoCopyWithImpl(this._self, this._then);

  final _BookingDto _self;
  final $Res Function(_BookingDto) _then;

/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? slotKey = null,Object? memberId = null,Object? trainerId = null,Object? passId = null,Object? kind = null,Object? status = null,Object? recurringId = freezed,Object? createdAt = freezed,}) {
  return _then(_BookingDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,slotKey: null == slotKey ? _self.slotKey : slotKey // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,passId: null == passId ? _self.passId : passId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,recurringId: freezed == recurringId ? _self.recurringId : recurringId // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
