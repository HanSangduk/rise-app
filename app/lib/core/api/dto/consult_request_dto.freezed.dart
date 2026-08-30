// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'consult_request_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ConsultRequestDto {

 String get id; String get kind;// renewal|consult
 String get note; String get status;// pending|done
@JsonKey(name: 'created_at') String? get createdAt;
/// Create a copy of ConsultRequestDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConsultRequestDtoCopyWith<ConsultRequestDto> get copyWith => _$ConsultRequestDtoCopyWithImpl<ConsultRequestDto>(this as ConsultRequestDto, _$identity);

  /// Serializes this ConsultRequestDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConsultRequestDto&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.note, note) || other.note == note)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,kind,note,status,createdAt);

@override
String toString() {
  return 'ConsultRequestDto(id: $id, kind: $kind, note: $note, status: $status, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $ConsultRequestDtoCopyWith<$Res>  {
  factory $ConsultRequestDtoCopyWith(ConsultRequestDto value, $Res Function(ConsultRequestDto) _then) = _$ConsultRequestDtoCopyWithImpl;
@useResult
$Res call({
 String id, String kind, String note, String status,@JsonKey(name: 'created_at') String? createdAt
});




}
/// @nodoc
class _$ConsultRequestDtoCopyWithImpl<$Res>
    implements $ConsultRequestDtoCopyWith<$Res> {
  _$ConsultRequestDtoCopyWithImpl(this._self, this._then);

  final ConsultRequestDto _self;
  final $Res Function(ConsultRequestDto) _then;

/// Create a copy of ConsultRequestDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? kind = null,Object? note = null,Object? status = null,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ConsultRequestDto].
extension ConsultRequestDtoPatterns on ConsultRequestDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConsultRequestDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConsultRequestDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConsultRequestDto value)  $default,){
final _that = this;
switch (_that) {
case _ConsultRequestDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConsultRequestDto value)?  $default,){
final _that = this;
switch (_that) {
case _ConsultRequestDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String kind,  String note,  String status, @JsonKey(name: 'created_at')  String? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConsultRequestDto() when $default != null:
return $default(_that.id,_that.kind,_that.note,_that.status,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String kind,  String note,  String status, @JsonKey(name: 'created_at')  String? createdAt)  $default,) {final _that = this;
switch (_that) {
case _ConsultRequestDto():
return $default(_that.id,_that.kind,_that.note,_that.status,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String kind,  String note,  String status, @JsonKey(name: 'created_at')  String? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _ConsultRequestDto() when $default != null:
return $default(_that.id,_that.kind,_that.note,_that.status,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConsultRequestDto extends ConsultRequestDto {
  const _ConsultRequestDto({required this.id, this.kind = 'renewal', this.note = '', this.status = 'pending', @JsonKey(name: 'created_at') this.createdAt}): super._();
  factory _ConsultRequestDto.fromJson(Map<String, dynamic> json) => _$ConsultRequestDtoFromJson(json);

@override final  String id;
@override@JsonKey() final  String kind;
// renewal|consult
@override@JsonKey() final  String note;
@override@JsonKey() final  String status;
// pending|done
@override@JsonKey(name: 'created_at') final  String? createdAt;

/// Create a copy of ConsultRequestDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConsultRequestDtoCopyWith<_ConsultRequestDto> get copyWith => __$ConsultRequestDtoCopyWithImpl<_ConsultRequestDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConsultRequestDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConsultRequestDto&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.note, note) || other.note == note)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,kind,note,status,createdAt);

@override
String toString() {
  return 'ConsultRequestDto(id: $id, kind: $kind, note: $note, status: $status, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$ConsultRequestDtoCopyWith<$Res> implements $ConsultRequestDtoCopyWith<$Res> {
  factory _$ConsultRequestDtoCopyWith(_ConsultRequestDto value, $Res Function(_ConsultRequestDto) _then) = __$ConsultRequestDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String kind, String note, String status,@JsonKey(name: 'created_at') String? createdAt
});




}
/// @nodoc
class __$ConsultRequestDtoCopyWithImpl<$Res>
    implements _$ConsultRequestDtoCopyWith<$Res> {
  __$ConsultRequestDtoCopyWithImpl(this._self, this._then);

  final _ConsultRequestDto _self;
  final $Res Function(_ConsultRequestDto) _then;

/// Create a copy of ConsultRequestDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? kind = null,Object? note = null,Object? status = null,Object? createdAt = freezed,}) {
  return _then(_ConsultRequestDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
