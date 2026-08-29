// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'join_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$JoinMatchResponseDto {

 MemberDto? get member;@JsonKey(name: 'needs_confirm') bool get needsConfirm;
/// Create a copy of JoinMatchResponseDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JoinMatchResponseDtoCopyWith<JoinMatchResponseDto> get copyWith => _$JoinMatchResponseDtoCopyWithImpl<JoinMatchResponseDto>(this as JoinMatchResponseDto, _$identity);

  /// Serializes this JoinMatchResponseDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JoinMatchResponseDto&&(identical(other.member, member) || other.member == member)&&(identical(other.needsConfirm, needsConfirm) || other.needsConfirm == needsConfirm));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,member,needsConfirm);

@override
String toString() {
  return 'JoinMatchResponseDto(member: $member, needsConfirm: $needsConfirm)';
}


}

/// @nodoc
abstract mixin class $JoinMatchResponseDtoCopyWith<$Res>  {
  factory $JoinMatchResponseDtoCopyWith(JoinMatchResponseDto value, $Res Function(JoinMatchResponseDto) _then) = _$JoinMatchResponseDtoCopyWithImpl;
@useResult
$Res call({
 MemberDto? member,@JsonKey(name: 'needs_confirm') bool needsConfirm
});


$MemberDtoCopyWith<$Res>? get member;

}
/// @nodoc
class _$JoinMatchResponseDtoCopyWithImpl<$Res>
    implements $JoinMatchResponseDtoCopyWith<$Res> {
  _$JoinMatchResponseDtoCopyWithImpl(this._self, this._then);

  final JoinMatchResponseDto _self;
  final $Res Function(JoinMatchResponseDto) _then;

/// Create a copy of JoinMatchResponseDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? member = freezed,Object? needsConfirm = null,}) {
  return _then(_self.copyWith(
member: freezed == member ? _self.member : member // ignore: cast_nullable_to_non_nullable
as MemberDto?,needsConfirm: null == needsConfirm ? _self.needsConfirm : needsConfirm // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of JoinMatchResponseDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MemberDtoCopyWith<$Res>? get member {
    if (_self.member == null) {
    return null;
  }

  return $MemberDtoCopyWith<$Res>(_self.member!, (value) {
    return _then(_self.copyWith(member: value));
  });
}
}


/// Adds pattern-matching-related methods to [JoinMatchResponseDto].
extension JoinMatchResponseDtoPatterns on JoinMatchResponseDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JoinMatchResponseDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JoinMatchResponseDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JoinMatchResponseDto value)  $default,){
final _that = this;
switch (_that) {
case _JoinMatchResponseDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JoinMatchResponseDto value)?  $default,){
final _that = this;
switch (_that) {
case _JoinMatchResponseDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( MemberDto? member, @JsonKey(name: 'needs_confirm')  bool needsConfirm)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JoinMatchResponseDto() when $default != null:
return $default(_that.member,_that.needsConfirm);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( MemberDto? member, @JsonKey(name: 'needs_confirm')  bool needsConfirm)  $default,) {final _that = this;
switch (_that) {
case _JoinMatchResponseDto():
return $default(_that.member,_that.needsConfirm);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( MemberDto? member, @JsonKey(name: 'needs_confirm')  bool needsConfirm)?  $default,) {final _that = this;
switch (_that) {
case _JoinMatchResponseDto() when $default != null:
return $default(_that.member,_that.needsConfirm);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _JoinMatchResponseDto implements JoinMatchResponseDto {
  const _JoinMatchResponseDto({this.member, @JsonKey(name: 'needs_confirm') this.needsConfirm = false});
  factory _JoinMatchResponseDto.fromJson(Map<String, dynamic> json) => _$JoinMatchResponseDtoFromJson(json);

@override final  MemberDto? member;
@override@JsonKey(name: 'needs_confirm') final  bool needsConfirm;

/// Create a copy of JoinMatchResponseDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JoinMatchResponseDtoCopyWith<_JoinMatchResponseDto> get copyWith => __$JoinMatchResponseDtoCopyWithImpl<_JoinMatchResponseDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$JoinMatchResponseDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _JoinMatchResponseDto&&(identical(other.member, member) || other.member == member)&&(identical(other.needsConfirm, needsConfirm) || other.needsConfirm == needsConfirm));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,member,needsConfirm);

@override
String toString() {
  return 'JoinMatchResponseDto(member: $member, needsConfirm: $needsConfirm)';
}


}

/// @nodoc
abstract mixin class _$JoinMatchResponseDtoCopyWith<$Res> implements $JoinMatchResponseDtoCopyWith<$Res> {
  factory _$JoinMatchResponseDtoCopyWith(_JoinMatchResponseDto value, $Res Function(_JoinMatchResponseDto) _then) = __$JoinMatchResponseDtoCopyWithImpl;
@override @useResult
$Res call({
 MemberDto? member,@JsonKey(name: 'needs_confirm') bool needsConfirm
});


@override $MemberDtoCopyWith<$Res>? get member;

}
/// @nodoc
class __$JoinMatchResponseDtoCopyWithImpl<$Res>
    implements _$JoinMatchResponseDtoCopyWith<$Res> {
  __$JoinMatchResponseDtoCopyWithImpl(this._self, this._then);

  final _JoinMatchResponseDto _self;
  final $Res Function(_JoinMatchResponseDto) _then;

/// Create a copy of JoinMatchResponseDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? member = freezed,Object? needsConfirm = null,}) {
  return _then(_JoinMatchResponseDto(
member: freezed == member ? _self.member : member // ignore: cast_nullable_to_non_nullable
as MemberDto?,needsConfirm: null == needsConfirm ? _self.needsConfirm : needsConfirm // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of JoinMatchResponseDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MemberDtoCopyWith<$Res>? get member {
    if (_self.member == null) {
    return null;
  }

  return $MemberDtoCopyWith<$Res>(_self.member!, (value) {
    return _then(_self.copyWith(member: value));
  });
}
}


/// @nodoc
mixin _$MeResponseDto {

 String get uid; String get role;@JsonKey(name: 'center_id') String get centerId;@JsonKey(name: 'member_id') String? get memberId;/// 화면 표시용 본인 이름(계약 v2.2). **없을 수 있다** — 서버는 이름을
/// best-effort로만 채우고(조회 실패해도 /v1/me는 성공한다), 미연결 계정이면
/// omitempty로 아예 빠지며, 구버전 서버는 이 키 자체를 모른다.
/// 그래서 non-null 기본값(`@Default('')`)이 아니라 nullable이다 — "서버가
/// 안 줬다"와 "서버가 빈 이름을 줬다"를 굳이 가르지 않되, 호출부가 폴백을
/// **반드시** 거치게 강제한다.
 String? get name;
/// Create a copy of MeResponseDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MeResponseDtoCopyWith<MeResponseDto> get copyWith => _$MeResponseDtoCopyWithImpl<MeResponseDto>(this as MeResponseDto, _$identity);

  /// Serializes this MeResponseDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MeResponseDto&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.role, role) || other.role == role)&&(identical(other.centerId, centerId) || other.centerId == centerId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.name, name) || other.name == name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uid,role,centerId,memberId,name);

@override
String toString() {
  return 'MeResponseDto(uid: $uid, role: $role, centerId: $centerId, memberId: $memberId, name: $name)';
}


}

/// @nodoc
abstract mixin class $MeResponseDtoCopyWith<$Res>  {
  factory $MeResponseDtoCopyWith(MeResponseDto value, $Res Function(MeResponseDto) _then) = _$MeResponseDtoCopyWithImpl;
@useResult
$Res call({
 String uid, String role,@JsonKey(name: 'center_id') String centerId,@JsonKey(name: 'member_id') String? memberId, String? name
});




}
/// @nodoc
class _$MeResponseDtoCopyWithImpl<$Res>
    implements $MeResponseDtoCopyWith<$Res> {
  _$MeResponseDtoCopyWithImpl(this._self, this._then);

  final MeResponseDto _self;
  final $Res Function(MeResponseDto) _then;

/// Create a copy of MeResponseDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? uid = null,Object? role = null,Object? centerId = null,Object? memberId = freezed,Object? name = freezed,}) {
  return _then(_self.copyWith(
uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,centerId: null == centerId ? _self.centerId : centerId // ignore: cast_nullable_to_non_nullable
as String,memberId: freezed == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [MeResponseDto].
extension MeResponseDtoPatterns on MeResponseDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MeResponseDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MeResponseDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MeResponseDto value)  $default,){
final _that = this;
switch (_that) {
case _MeResponseDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MeResponseDto value)?  $default,){
final _that = this;
switch (_that) {
case _MeResponseDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String uid,  String role, @JsonKey(name: 'center_id')  String centerId, @JsonKey(name: 'member_id')  String? memberId,  String? name)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MeResponseDto() when $default != null:
return $default(_that.uid,_that.role,_that.centerId,_that.memberId,_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String uid,  String role, @JsonKey(name: 'center_id')  String centerId, @JsonKey(name: 'member_id')  String? memberId,  String? name)  $default,) {final _that = this;
switch (_that) {
case _MeResponseDto():
return $default(_that.uid,_that.role,_that.centerId,_that.memberId,_that.name);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String uid,  String role, @JsonKey(name: 'center_id')  String centerId, @JsonKey(name: 'member_id')  String? memberId,  String? name)?  $default,) {final _that = this;
switch (_that) {
case _MeResponseDto() when $default != null:
return $default(_that.uid,_that.role,_that.centerId,_that.memberId,_that.name);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MeResponseDto implements MeResponseDto {
  const _MeResponseDto({required this.uid, required this.role, @JsonKey(name: 'center_id') required this.centerId, @JsonKey(name: 'member_id') this.memberId, this.name});
  factory _MeResponseDto.fromJson(Map<String, dynamic> json) => _$MeResponseDtoFromJson(json);

@override final  String uid;
@override final  String role;
@override@JsonKey(name: 'center_id') final  String centerId;
@override@JsonKey(name: 'member_id') final  String? memberId;
/// 화면 표시용 본인 이름(계약 v2.2). **없을 수 있다** — 서버는 이름을
/// best-effort로만 채우고(조회 실패해도 /v1/me는 성공한다), 미연결 계정이면
/// omitempty로 아예 빠지며, 구버전 서버는 이 키 자체를 모른다.
/// 그래서 non-null 기본값(`@Default('')`)이 아니라 nullable이다 — "서버가
/// 안 줬다"와 "서버가 빈 이름을 줬다"를 굳이 가르지 않되, 호출부가 폴백을
/// **반드시** 거치게 강제한다.
@override final  String? name;

/// Create a copy of MeResponseDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MeResponseDtoCopyWith<_MeResponseDto> get copyWith => __$MeResponseDtoCopyWithImpl<_MeResponseDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MeResponseDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MeResponseDto&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.role, role) || other.role == role)&&(identical(other.centerId, centerId) || other.centerId == centerId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.name, name) || other.name == name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uid,role,centerId,memberId,name);

@override
String toString() {
  return 'MeResponseDto(uid: $uid, role: $role, centerId: $centerId, memberId: $memberId, name: $name)';
}


}

/// @nodoc
abstract mixin class _$MeResponseDtoCopyWith<$Res> implements $MeResponseDtoCopyWith<$Res> {
  factory _$MeResponseDtoCopyWith(_MeResponseDto value, $Res Function(_MeResponseDto) _then) = __$MeResponseDtoCopyWithImpl;
@override @useResult
$Res call({
 String uid, String role,@JsonKey(name: 'center_id') String centerId,@JsonKey(name: 'member_id') String? memberId, String? name
});




}
/// @nodoc
class __$MeResponseDtoCopyWithImpl<$Res>
    implements _$MeResponseDtoCopyWith<$Res> {
  __$MeResponseDtoCopyWithImpl(this._self, this._then);

  final _MeResponseDto _self;
  final $Res Function(_MeResponseDto) _then;

/// Create a copy of MeResponseDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? uid = null,Object? role = null,Object? centerId = null,Object? memberId = freezed,Object? name = freezed,}) {
  return _then(_MeResponseDto(
uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,centerId: null == centerId ? _self.centerId : centerId // ignore: cast_nullable_to_non_nullable
as String,memberId: freezed == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
