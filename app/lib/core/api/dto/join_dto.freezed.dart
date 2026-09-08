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
 String? get name;/// 진행 중인 가입 요청(계약 v2.27). **`member_id`가 없을 때만** 실린다 —
/// 연결된 회원·스태프에겐 서버가 키 자체를 빼므로 nullable이다.
///
/// 이 필드가 생기기 전엔 "요청을 보냈다"는 사실이 **기기의 SharedPreferences에만**
/// 있었다. 그래서 기기를 바꾸거나 앱을 지웠다 깔면 근거가 사라져 화면이
/// "요청한 적 없음"으로 떨어졌고, 사용자는 같은 요청을 또 보냈다 — 그 중복이
/// 대표 어드민을 죽이던 재료였다(P55). 이제 서버가 주인이다.
@JsonKey(name: 'join_request') JoinRequestStatusDto? get joinRequest;
/// Create a copy of MeResponseDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MeResponseDtoCopyWith<MeResponseDto> get copyWith => _$MeResponseDtoCopyWithImpl<MeResponseDto>(this as MeResponseDto, _$identity);

  /// Serializes this MeResponseDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MeResponseDto&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.role, role) || other.role == role)&&(identical(other.centerId, centerId) || other.centerId == centerId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.name, name) || other.name == name)&&(identical(other.joinRequest, joinRequest) || other.joinRequest == joinRequest));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uid,role,centerId,memberId,name,joinRequest);

@override
String toString() {
  return 'MeResponseDto(uid: $uid, role: $role, centerId: $centerId, memberId: $memberId, name: $name, joinRequest: $joinRequest)';
}


}

/// @nodoc
abstract mixin class $MeResponseDtoCopyWith<$Res>  {
  factory $MeResponseDtoCopyWith(MeResponseDto value, $Res Function(MeResponseDto) _then) = _$MeResponseDtoCopyWithImpl;
@useResult
$Res call({
 String uid, String role,@JsonKey(name: 'center_id') String centerId,@JsonKey(name: 'member_id') String? memberId, String? name,@JsonKey(name: 'join_request') JoinRequestStatusDto? joinRequest
});


$JoinRequestStatusDtoCopyWith<$Res>? get joinRequest;

}
/// @nodoc
class _$MeResponseDtoCopyWithImpl<$Res>
    implements $MeResponseDtoCopyWith<$Res> {
  _$MeResponseDtoCopyWithImpl(this._self, this._then);

  final MeResponseDto _self;
  final $Res Function(MeResponseDto) _then;

/// Create a copy of MeResponseDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? uid = null,Object? role = null,Object? centerId = null,Object? memberId = freezed,Object? name = freezed,Object? joinRequest = freezed,}) {
  return _then(_self.copyWith(
uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,centerId: null == centerId ? _self.centerId : centerId // ignore: cast_nullable_to_non_nullable
as String,memberId: freezed == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,joinRequest: freezed == joinRequest ? _self.joinRequest : joinRequest // ignore: cast_nullable_to_non_nullable
as JoinRequestStatusDto?,
  ));
}
/// Create a copy of MeResponseDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JoinRequestStatusDtoCopyWith<$Res>? get joinRequest {
    if (_self.joinRequest == null) {
    return null;
  }

  return $JoinRequestStatusDtoCopyWith<$Res>(_self.joinRequest!, (value) {
    return _then(_self.copyWith(joinRequest: value));
  });
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String uid,  String role, @JsonKey(name: 'center_id')  String centerId, @JsonKey(name: 'member_id')  String? memberId,  String? name, @JsonKey(name: 'join_request')  JoinRequestStatusDto? joinRequest)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MeResponseDto() when $default != null:
return $default(_that.uid,_that.role,_that.centerId,_that.memberId,_that.name,_that.joinRequest);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String uid,  String role, @JsonKey(name: 'center_id')  String centerId, @JsonKey(name: 'member_id')  String? memberId,  String? name, @JsonKey(name: 'join_request')  JoinRequestStatusDto? joinRequest)  $default,) {final _that = this;
switch (_that) {
case _MeResponseDto():
return $default(_that.uid,_that.role,_that.centerId,_that.memberId,_that.name,_that.joinRequest);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String uid,  String role, @JsonKey(name: 'center_id')  String centerId, @JsonKey(name: 'member_id')  String? memberId,  String? name, @JsonKey(name: 'join_request')  JoinRequestStatusDto? joinRequest)?  $default,) {final _that = this;
switch (_that) {
case _MeResponseDto() when $default != null:
return $default(_that.uid,_that.role,_that.centerId,_that.memberId,_that.name,_that.joinRequest);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MeResponseDto implements MeResponseDto {
  const _MeResponseDto({required this.uid, required this.role, @JsonKey(name: 'center_id') required this.centerId, @JsonKey(name: 'member_id') this.memberId, this.name, @JsonKey(name: 'join_request') this.joinRequest});
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
/// 진행 중인 가입 요청(계약 v2.27). **`member_id`가 없을 때만** 실린다 —
/// 연결된 회원·스태프에겐 서버가 키 자체를 빼므로 nullable이다.
///
/// 이 필드가 생기기 전엔 "요청을 보냈다"는 사실이 **기기의 SharedPreferences에만**
/// 있었다. 그래서 기기를 바꾸거나 앱을 지웠다 깔면 근거가 사라져 화면이
/// "요청한 적 없음"으로 떨어졌고, 사용자는 같은 요청을 또 보냈다 — 그 중복이
/// 대표 어드민을 죽이던 재료였다(P55). 이제 서버가 주인이다.
@override@JsonKey(name: 'join_request') final  JoinRequestStatusDto? joinRequest;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MeResponseDto&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.role, role) || other.role == role)&&(identical(other.centerId, centerId) || other.centerId == centerId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.name, name) || other.name == name)&&(identical(other.joinRequest, joinRequest) || other.joinRequest == joinRequest));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uid,role,centerId,memberId,name,joinRequest);

@override
String toString() {
  return 'MeResponseDto(uid: $uid, role: $role, centerId: $centerId, memberId: $memberId, name: $name, joinRequest: $joinRequest)';
}


}

/// @nodoc
abstract mixin class _$MeResponseDtoCopyWith<$Res> implements $MeResponseDtoCopyWith<$Res> {
  factory _$MeResponseDtoCopyWith(_MeResponseDto value, $Res Function(_MeResponseDto) _then) = __$MeResponseDtoCopyWithImpl;
@override @useResult
$Res call({
 String uid, String role,@JsonKey(name: 'center_id') String centerId,@JsonKey(name: 'member_id') String? memberId, String? name,@JsonKey(name: 'join_request') JoinRequestStatusDto? joinRequest
});


@override $JoinRequestStatusDtoCopyWith<$Res>? get joinRequest;

}
/// @nodoc
class __$MeResponseDtoCopyWithImpl<$Res>
    implements _$MeResponseDtoCopyWith<$Res> {
  __$MeResponseDtoCopyWithImpl(this._self, this._then);

  final _MeResponseDto _self;
  final $Res Function(_MeResponseDto) _then;

/// Create a copy of MeResponseDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? uid = null,Object? role = null,Object? centerId = null,Object? memberId = freezed,Object? name = freezed,Object? joinRequest = freezed,}) {
  return _then(_MeResponseDto(
uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,centerId: null == centerId ? _self.centerId : centerId // ignore: cast_nullable_to_non_nullable
as String,memberId: freezed == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,joinRequest: freezed == joinRequest ? _self.joinRequest : joinRequest // ignore: cast_nullable_to_non_nullable
as JoinRequestStatusDto?,
  ));
}

/// Create a copy of MeResponseDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JoinRequestStatusDtoCopyWith<$Res>? get joinRequest {
    if (_self.joinRequest == null) {
    return null;
  }

  return $JoinRequestStatusDtoCopyWith<$Res>(_self.joinRequest!, (value) {
    return _then(_self.copyWith(joinRequest: value));
  });
}
}


/// @nodoc
mixin _$JoinRequestStatusDto {

/// `pending` | `rejected` | `approved`.
///
/// `approved`는 정상 경로에서 보이지 않는다 — 승인되면 `member_id`가 생겨
/// 이 필드 자체가 빠지기 때문이다. 승인 도중 인덱스 쓰기만 실패한 부분 잔여에서만
/// 관측되므로 "승인됐는데 아직 연결 중"으로 다루고 재조회한다.
 String get status;/// 요청이 귀속된 센터(계약 v2.34). **구서버는 이 키를 모른다** → `''`. v2.33이 요청 시
/// 센터 선택을 열었으므로 대기실이 "어느 센터에 보냈는지"를 알아야 그 센터의 연락처를
/// 보여줄 수 있다(없으면 기본 센터 — 종전 동작).
@JsonKey(name: 'center_id') String get centerId;@JsonKey(name: 'created_at') String get createdAt;
/// Create a copy of JoinRequestStatusDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JoinRequestStatusDtoCopyWith<JoinRequestStatusDto> get copyWith => _$JoinRequestStatusDtoCopyWithImpl<JoinRequestStatusDto>(this as JoinRequestStatusDto, _$identity);

  /// Serializes this JoinRequestStatusDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JoinRequestStatusDto&&(identical(other.status, status) || other.status == status)&&(identical(other.centerId, centerId) || other.centerId == centerId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,status,centerId,createdAt);

@override
String toString() {
  return 'JoinRequestStatusDto(status: $status, centerId: $centerId, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $JoinRequestStatusDtoCopyWith<$Res>  {
  factory $JoinRequestStatusDtoCopyWith(JoinRequestStatusDto value, $Res Function(JoinRequestStatusDto) _then) = _$JoinRequestStatusDtoCopyWithImpl;
@useResult
$Res call({
 String status,@JsonKey(name: 'center_id') String centerId,@JsonKey(name: 'created_at') String createdAt
});




}
/// @nodoc
class _$JoinRequestStatusDtoCopyWithImpl<$Res>
    implements $JoinRequestStatusDtoCopyWith<$Res> {
  _$JoinRequestStatusDtoCopyWithImpl(this._self, this._then);

  final JoinRequestStatusDto _self;
  final $Res Function(JoinRequestStatusDto) _then;

/// Create a copy of JoinRequestStatusDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? centerId = null,Object? createdAt = null,}) {
  return _then(_self.copyWith(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,centerId: null == centerId ? _self.centerId : centerId // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [JoinRequestStatusDto].
extension JoinRequestStatusDtoPatterns on JoinRequestStatusDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JoinRequestStatusDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JoinRequestStatusDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JoinRequestStatusDto value)  $default,){
final _that = this;
switch (_that) {
case _JoinRequestStatusDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JoinRequestStatusDto value)?  $default,){
final _that = this;
switch (_that) {
case _JoinRequestStatusDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String status, @JsonKey(name: 'center_id')  String centerId, @JsonKey(name: 'created_at')  String createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JoinRequestStatusDto() when $default != null:
return $default(_that.status,_that.centerId,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String status, @JsonKey(name: 'center_id')  String centerId, @JsonKey(name: 'created_at')  String createdAt)  $default,) {final _that = this;
switch (_that) {
case _JoinRequestStatusDto():
return $default(_that.status,_that.centerId,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String status, @JsonKey(name: 'center_id')  String centerId, @JsonKey(name: 'created_at')  String createdAt)?  $default,) {final _that = this;
switch (_that) {
case _JoinRequestStatusDto() when $default != null:
return $default(_that.status,_that.centerId,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _JoinRequestStatusDto implements JoinRequestStatusDto {
  const _JoinRequestStatusDto({required this.status, @JsonKey(name: 'center_id') this.centerId = '', @JsonKey(name: 'created_at') required this.createdAt});
  factory _JoinRequestStatusDto.fromJson(Map<String, dynamic> json) => _$JoinRequestStatusDtoFromJson(json);

/// `pending` | `rejected` | `approved`.
///
/// `approved`는 정상 경로에서 보이지 않는다 — 승인되면 `member_id`가 생겨
/// 이 필드 자체가 빠지기 때문이다. 승인 도중 인덱스 쓰기만 실패한 부분 잔여에서만
/// 관측되므로 "승인됐는데 아직 연결 중"으로 다루고 재조회한다.
@override final  String status;
/// 요청이 귀속된 센터(계약 v2.34). **구서버는 이 키를 모른다** → `''`. v2.33이 요청 시
/// 센터 선택을 열었으므로 대기실이 "어느 센터에 보냈는지"를 알아야 그 센터의 연락처를
/// 보여줄 수 있다(없으면 기본 센터 — 종전 동작).
@override@JsonKey(name: 'center_id') final  String centerId;
@override@JsonKey(name: 'created_at') final  String createdAt;

/// Create a copy of JoinRequestStatusDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JoinRequestStatusDtoCopyWith<_JoinRequestStatusDto> get copyWith => __$JoinRequestStatusDtoCopyWithImpl<_JoinRequestStatusDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$JoinRequestStatusDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _JoinRequestStatusDto&&(identical(other.status, status) || other.status == status)&&(identical(other.centerId, centerId) || other.centerId == centerId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,status,centerId,createdAt);

@override
String toString() {
  return 'JoinRequestStatusDto(status: $status, centerId: $centerId, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$JoinRequestStatusDtoCopyWith<$Res> implements $JoinRequestStatusDtoCopyWith<$Res> {
  factory _$JoinRequestStatusDtoCopyWith(_JoinRequestStatusDto value, $Res Function(_JoinRequestStatusDto) _then) = __$JoinRequestStatusDtoCopyWithImpl;
@override @useResult
$Res call({
 String status,@JsonKey(name: 'center_id') String centerId,@JsonKey(name: 'created_at') String createdAt
});




}
/// @nodoc
class __$JoinRequestStatusDtoCopyWithImpl<$Res>
    implements _$JoinRequestStatusDtoCopyWith<$Res> {
  __$JoinRequestStatusDtoCopyWithImpl(this._self, this._then);

  final _JoinRequestStatusDto _self;
  final $Res Function(_JoinRequestStatusDto) _then;

/// Create a copy of JoinRequestStatusDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? centerId = null,Object? createdAt = null,}) {
  return _then(_JoinRequestStatusDto(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,centerId: null == centerId ? _self.centerId : centerId // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
