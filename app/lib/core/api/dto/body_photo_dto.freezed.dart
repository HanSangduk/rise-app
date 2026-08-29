// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'body_photo_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BodyPhotoDto {

 String get id;@JsonKey(name: 'member_id') String get memberId; String get pose;// stand|tpose|fold|ohsquat
 String get direction;// front|side|back
 String get date;@JsonKey(name: 'storage_path') String? get storagePath; bool get blurred;
/// Create a copy of BodyPhotoDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BodyPhotoDtoCopyWith<BodyPhotoDto> get copyWith => _$BodyPhotoDtoCopyWithImpl<BodyPhotoDto>(this as BodyPhotoDto, _$identity);

  /// Serializes this BodyPhotoDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BodyPhotoDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.pose, pose) || other.pose == pose)&&(identical(other.direction, direction) || other.direction == direction)&&(identical(other.date, date) || other.date == date)&&(identical(other.storagePath, storagePath) || other.storagePath == storagePath)&&(identical(other.blurred, blurred) || other.blurred == blurred));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,pose,direction,date,storagePath,blurred);

@override
String toString() {
  return 'BodyPhotoDto(id: $id, memberId: $memberId, pose: $pose, direction: $direction, date: $date, storagePath: $storagePath, blurred: $blurred)';
}


}

/// @nodoc
abstract mixin class $BodyPhotoDtoCopyWith<$Res>  {
  factory $BodyPhotoDtoCopyWith(BodyPhotoDto value, $Res Function(BodyPhotoDto) _then) = _$BodyPhotoDtoCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId, String pose, String direction, String date,@JsonKey(name: 'storage_path') String? storagePath, bool blurred
});




}
/// @nodoc
class _$BodyPhotoDtoCopyWithImpl<$Res>
    implements $BodyPhotoDtoCopyWith<$Res> {
  _$BodyPhotoDtoCopyWithImpl(this._self, this._then);

  final BodyPhotoDto _self;
  final $Res Function(BodyPhotoDto) _then;

/// Create a copy of BodyPhotoDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? memberId = null,Object? pose = null,Object? direction = null,Object? date = null,Object? storagePath = freezed,Object? blurred = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,pose: null == pose ? _self.pose : pose // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,storagePath: freezed == storagePath ? _self.storagePath : storagePath // ignore: cast_nullable_to_non_nullable
as String?,blurred: null == blurred ? _self.blurred : blurred // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [BodyPhotoDto].
extension BodyPhotoDtoPatterns on BodyPhotoDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BodyPhotoDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BodyPhotoDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BodyPhotoDto value)  $default,){
final _that = this;
switch (_that) {
case _BodyPhotoDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BodyPhotoDto value)?  $default,){
final _that = this;
switch (_that) {
case _BodyPhotoDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId,  String pose,  String direction,  String date, @JsonKey(name: 'storage_path')  String? storagePath,  bool blurred)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BodyPhotoDto() when $default != null:
return $default(_that.id,_that.memberId,_that.pose,_that.direction,_that.date,_that.storagePath,_that.blurred);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId,  String pose,  String direction,  String date, @JsonKey(name: 'storage_path')  String? storagePath,  bool blurred)  $default,) {final _that = this;
switch (_that) {
case _BodyPhotoDto():
return $default(_that.id,_that.memberId,_that.pose,_that.direction,_that.date,_that.storagePath,_that.blurred);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'member_id')  String memberId,  String pose,  String direction,  String date, @JsonKey(name: 'storage_path')  String? storagePath,  bool blurred)?  $default,) {final _that = this;
switch (_that) {
case _BodyPhotoDto() when $default != null:
return $default(_that.id,_that.memberId,_that.pose,_that.direction,_that.date,_that.storagePath,_that.blurred);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BodyPhotoDto implements BodyPhotoDto {
  const _BodyPhotoDto({required this.id, @JsonKey(name: 'member_id') required this.memberId, required this.pose, this.direction = 'front', required this.date, @JsonKey(name: 'storage_path') this.storagePath, this.blurred = false});
  factory _BodyPhotoDto.fromJson(Map<String, dynamic> json) => _$BodyPhotoDtoFromJson(json);

@override final  String id;
@override@JsonKey(name: 'member_id') final  String memberId;
@override final  String pose;
// stand|tpose|fold|ohsquat
@override@JsonKey() final  String direction;
// front|side|back
@override final  String date;
@override@JsonKey(name: 'storage_path') final  String? storagePath;
@override@JsonKey() final  bool blurred;

/// Create a copy of BodyPhotoDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BodyPhotoDtoCopyWith<_BodyPhotoDto> get copyWith => __$BodyPhotoDtoCopyWithImpl<_BodyPhotoDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BodyPhotoDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BodyPhotoDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.pose, pose) || other.pose == pose)&&(identical(other.direction, direction) || other.direction == direction)&&(identical(other.date, date) || other.date == date)&&(identical(other.storagePath, storagePath) || other.storagePath == storagePath)&&(identical(other.blurred, blurred) || other.blurred == blurred));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,pose,direction,date,storagePath,blurred);

@override
String toString() {
  return 'BodyPhotoDto(id: $id, memberId: $memberId, pose: $pose, direction: $direction, date: $date, storagePath: $storagePath, blurred: $blurred)';
}


}

/// @nodoc
abstract mixin class _$BodyPhotoDtoCopyWith<$Res> implements $BodyPhotoDtoCopyWith<$Res> {
  factory _$BodyPhotoDtoCopyWith(_BodyPhotoDto value, $Res Function(_BodyPhotoDto) _then) = __$BodyPhotoDtoCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId, String pose, String direction, String date,@JsonKey(name: 'storage_path') String? storagePath, bool blurred
});




}
/// @nodoc
class __$BodyPhotoDtoCopyWithImpl<$Res>
    implements _$BodyPhotoDtoCopyWith<$Res> {
  __$BodyPhotoDtoCopyWithImpl(this._self, this._then);

  final _BodyPhotoDto _self;
  final $Res Function(_BodyPhotoDto) _then;

/// Create a copy of BodyPhotoDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? memberId = null,Object? pose = null,Object? direction = null,Object? date = null,Object? storagePath = freezed,Object? blurred = null,}) {
  return _then(_BodyPhotoDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,pose: null == pose ? _self.pose : pose // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,storagePath: freezed == storagePath ? _self.storagePath : storagePath // ignore: cast_nullable_to_non_nullable
as String?,blurred: null == blurred ? _self.blurred : blurred // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
