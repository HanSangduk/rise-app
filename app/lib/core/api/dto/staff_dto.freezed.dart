// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'staff_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$StaffDto {

 String get uid; String get role;// owner|trainer
 String get name; String? get color;/// v2.0 직원 생애주기 — "active|inactive". 계약: **필드 부재/""는 active로 승격**
/// (기존 Firestore 문서 마이그레이션 불필요). @Default는 키 누락·null만 메우므로
/// ""·미지값의 승격은 [isInactive]가 "inactive일 때만 퇴사"로 판정해 처리한다.
 String get status;/// v2.0 — RFC3339, inactive일 때만 존재(서버 기록). 프로필 시트 퇴사 시점 표기용.
@JsonKey(name: 'left_at') String? get leftAt;/// 휴무일 목록("YYYY-MM-DD"). 계약상 항상 배열(null 금지 — 서버 Normalize가
/// nil을 []로 승격)이지만, 구버전 서버/키 누락에도 빈 목록으로 안전하게 떨어진다.
/// 예약 사전 판정(BookingRules → TrainerOffday)이 이 값을 쓴다.
 List<String> get offdays;// v1.6 — 계약상 항상 객체(null 금지)지만, 구버전 서버/키 누락에도 빈 프로필로 안전.
// v2.0 — role=member 응답에선 inactive 스태프의 profile이 빈 객체로 마스킹된다
// (이름은 남는다). 즉 "inactive + isEmpty"는 오류가 아니라 정상 응답이다.
 StaffProfileDto get profile;
/// Create a copy of StaffDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StaffDtoCopyWith<StaffDto> get copyWith => _$StaffDtoCopyWithImpl<StaffDto>(this as StaffDto, _$identity);

  /// Serializes this StaffDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StaffDto&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.role, role) || other.role == role)&&(identical(other.name, name) || other.name == name)&&(identical(other.color, color) || other.color == color)&&(identical(other.status, status) || other.status == status)&&(identical(other.leftAt, leftAt) || other.leftAt == leftAt)&&const DeepCollectionEquality().equals(other.offdays, offdays)&&(identical(other.profile, profile) || other.profile == profile));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uid,role,name,color,status,leftAt,const DeepCollectionEquality().hash(offdays),profile);

@override
String toString() {
  return 'StaffDto(uid: $uid, role: $role, name: $name, color: $color, status: $status, leftAt: $leftAt, offdays: $offdays, profile: $profile)';
}


}

/// @nodoc
abstract mixin class $StaffDtoCopyWith<$Res>  {
  factory $StaffDtoCopyWith(StaffDto value, $Res Function(StaffDto) _then) = _$StaffDtoCopyWithImpl;
@useResult
$Res call({
 String uid, String role, String name, String? color, String status,@JsonKey(name: 'left_at') String? leftAt, List<String> offdays, StaffProfileDto profile
});


$StaffProfileDtoCopyWith<$Res> get profile;

}
/// @nodoc
class _$StaffDtoCopyWithImpl<$Res>
    implements $StaffDtoCopyWith<$Res> {
  _$StaffDtoCopyWithImpl(this._self, this._then);

  final StaffDto _self;
  final $Res Function(StaffDto) _then;

/// Create a copy of StaffDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? uid = null,Object? role = null,Object? name = null,Object? color = freezed,Object? status = null,Object? leftAt = freezed,Object? offdays = null,Object? profile = null,}) {
  return _then(_self.copyWith(
uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,color: freezed == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,leftAt: freezed == leftAt ? _self.leftAt : leftAt // ignore: cast_nullable_to_non_nullable
as String?,offdays: null == offdays ? _self.offdays : offdays // ignore: cast_nullable_to_non_nullable
as List<String>,profile: null == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as StaffProfileDto,
  ));
}
/// Create a copy of StaffDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StaffProfileDtoCopyWith<$Res> get profile {
  
  return $StaffProfileDtoCopyWith<$Res>(_self.profile, (value) {
    return _then(_self.copyWith(profile: value));
  });
}
}


/// Adds pattern-matching-related methods to [StaffDto].
extension StaffDtoPatterns on StaffDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StaffDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StaffDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StaffDto value)  $default,){
final _that = this;
switch (_that) {
case _StaffDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StaffDto value)?  $default,){
final _that = this;
switch (_that) {
case _StaffDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String uid,  String role,  String name,  String? color,  String status, @JsonKey(name: 'left_at')  String? leftAt,  List<String> offdays,  StaffProfileDto profile)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StaffDto() when $default != null:
return $default(_that.uid,_that.role,_that.name,_that.color,_that.status,_that.leftAt,_that.offdays,_that.profile);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String uid,  String role,  String name,  String? color,  String status, @JsonKey(name: 'left_at')  String? leftAt,  List<String> offdays,  StaffProfileDto profile)  $default,) {final _that = this;
switch (_that) {
case _StaffDto():
return $default(_that.uid,_that.role,_that.name,_that.color,_that.status,_that.leftAt,_that.offdays,_that.profile);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String uid,  String role,  String name,  String? color,  String status, @JsonKey(name: 'left_at')  String? leftAt,  List<String> offdays,  StaffProfileDto profile)?  $default,) {final _that = this;
switch (_that) {
case _StaffDto() when $default != null:
return $default(_that.uid,_that.role,_that.name,_that.color,_that.status,_that.leftAt,_that.offdays,_that.profile);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StaffDto extends StaffDto {
  const _StaffDto({required this.uid, this.role = 'trainer', required this.name, this.color, this.status = 'active', @JsonKey(name: 'left_at') this.leftAt, final  List<String> offdays = const [], this.profile = const StaffProfileDto()}): _offdays = offdays,super._();
  factory _StaffDto.fromJson(Map<String, dynamic> json) => _$StaffDtoFromJson(json);

@override final  String uid;
@override@JsonKey() final  String role;
// owner|trainer
@override final  String name;
@override final  String? color;
/// v2.0 직원 생애주기 — "active|inactive". 계약: **필드 부재/""는 active로 승격**
/// (기존 Firestore 문서 마이그레이션 불필요). @Default는 키 누락·null만 메우므로
/// ""·미지값의 승격은 [isInactive]가 "inactive일 때만 퇴사"로 판정해 처리한다.
@override@JsonKey() final  String status;
/// v2.0 — RFC3339, inactive일 때만 존재(서버 기록). 프로필 시트 퇴사 시점 표기용.
@override@JsonKey(name: 'left_at') final  String? leftAt;
/// 휴무일 목록("YYYY-MM-DD"). 계약상 항상 배열(null 금지 — 서버 Normalize가
/// nil을 []로 승격)이지만, 구버전 서버/키 누락에도 빈 목록으로 안전하게 떨어진다.
/// 예약 사전 판정(BookingRules → TrainerOffday)이 이 값을 쓴다.
 final  List<String> _offdays;
/// 휴무일 목록("YYYY-MM-DD"). 계약상 항상 배열(null 금지 — 서버 Normalize가
/// nil을 []로 승격)이지만, 구버전 서버/키 누락에도 빈 목록으로 안전하게 떨어진다.
/// 예약 사전 판정(BookingRules → TrainerOffday)이 이 값을 쓴다.
@override@JsonKey() List<String> get offdays {
  if (_offdays is EqualUnmodifiableListView) return _offdays;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_offdays);
}

// v1.6 — 계약상 항상 객체(null 금지)지만, 구버전 서버/키 누락에도 빈 프로필로 안전.
// v2.0 — role=member 응답에선 inactive 스태프의 profile이 빈 객체로 마스킹된다
// (이름은 남는다). 즉 "inactive + isEmpty"는 오류가 아니라 정상 응답이다.
@override@JsonKey() final  StaffProfileDto profile;

/// Create a copy of StaffDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StaffDtoCopyWith<_StaffDto> get copyWith => __$StaffDtoCopyWithImpl<_StaffDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StaffDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StaffDto&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.role, role) || other.role == role)&&(identical(other.name, name) || other.name == name)&&(identical(other.color, color) || other.color == color)&&(identical(other.status, status) || other.status == status)&&(identical(other.leftAt, leftAt) || other.leftAt == leftAt)&&const DeepCollectionEquality().equals(other._offdays, _offdays)&&(identical(other.profile, profile) || other.profile == profile));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uid,role,name,color,status,leftAt,const DeepCollectionEquality().hash(_offdays),profile);

@override
String toString() {
  return 'StaffDto(uid: $uid, role: $role, name: $name, color: $color, status: $status, leftAt: $leftAt, offdays: $offdays, profile: $profile)';
}


}

/// @nodoc
abstract mixin class _$StaffDtoCopyWith<$Res> implements $StaffDtoCopyWith<$Res> {
  factory _$StaffDtoCopyWith(_StaffDto value, $Res Function(_StaffDto) _then) = __$StaffDtoCopyWithImpl;
@override @useResult
$Res call({
 String uid, String role, String name, String? color, String status,@JsonKey(name: 'left_at') String? leftAt, List<String> offdays, StaffProfileDto profile
});


@override $StaffProfileDtoCopyWith<$Res> get profile;

}
/// @nodoc
class __$StaffDtoCopyWithImpl<$Res>
    implements _$StaffDtoCopyWith<$Res> {
  __$StaffDtoCopyWithImpl(this._self, this._then);

  final _StaffDto _self;
  final $Res Function(_StaffDto) _then;

/// Create a copy of StaffDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? uid = null,Object? role = null,Object? name = null,Object? color = freezed,Object? status = null,Object? leftAt = freezed,Object? offdays = null,Object? profile = null,}) {
  return _then(_StaffDto(
uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,color: freezed == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,leftAt: freezed == leftAt ? _self.leftAt : leftAt // ignore: cast_nullable_to_non_nullable
as String?,offdays: null == offdays ? _self._offdays : offdays // ignore: cast_nullable_to_non_nullable
as List<String>,profile: null == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as StaffProfileDto,
  ));
}

/// Create a copy of StaffDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StaffProfileDtoCopyWith<$Res> get profile {
  
  return $StaffProfileDtoCopyWith<$Res>(_self.profile, (value) {
    return _then(_self.copyWith(profile: value));
  });
}
}


/// @nodoc
mixin _$StaffProfileDto {

@JsonKey(name: 'photo_url') String get photoUrl; String get title;// 직함(예: "퍼포먼스 트레이너")
@JsonKey(name: 'career_years') int get careerYears;// 0=미표기
 List<String> get specialties; List<String> get certifications; List<String> get awards;// 수상·선수 경력
 String get bio;
/// Create a copy of StaffProfileDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StaffProfileDtoCopyWith<StaffProfileDto> get copyWith => _$StaffProfileDtoCopyWithImpl<StaffProfileDto>(this as StaffProfileDto, _$identity);

  /// Serializes this StaffProfileDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StaffProfileDto&&(identical(other.photoUrl, photoUrl) || other.photoUrl == photoUrl)&&(identical(other.title, title) || other.title == title)&&(identical(other.careerYears, careerYears) || other.careerYears == careerYears)&&const DeepCollectionEquality().equals(other.specialties, specialties)&&const DeepCollectionEquality().equals(other.certifications, certifications)&&const DeepCollectionEquality().equals(other.awards, awards)&&(identical(other.bio, bio) || other.bio == bio));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,photoUrl,title,careerYears,const DeepCollectionEquality().hash(specialties),const DeepCollectionEquality().hash(certifications),const DeepCollectionEquality().hash(awards),bio);

@override
String toString() {
  return 'StaffProfileDto(photoUrl: $photoUrl, title: $title, careerYears: $careerYears, specialties: $specialties, certifications: $certifications, awards: $awards, bio: $bio)';
}


}

/// @nodoc
abstract mixin class $StaffProfileDtoCopyWith<$Res>  {
  factory $StaffProfileDtoCopyWith(StaffProfileDto value, $Res Function(StaffProfileDto) _then) = _$StaffProfileDtoCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'photo_url') String photoUrl, String title,@JsonKey(name: 'career_years') int careerYears, List<String> specialties, List<String> certifications, List<String> awards, String bio
});




}
/// @nodoc
class _$StaffProfileDtoCopyWithImpl<$Res>
    implements $StaffProfileDtoCopyWith<$Res> {
  _$StaffProfileDtoCopyWithImpl(this._self, this._then);

  final StaffProfileDto _self;
  final $Res Function(StaffProfileDto) _then;

/// Create a copy of StaffProfileDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? photoUrl = null,Object? title = null,Object? careerYears = null,Object? specialties = null,Object? certifications = null,Object? awards = null,Object? bio = null,}) {
  return _then(_self.copyWith(
photoUrl: null == photoUrl ? _self.photoUrl : photoUrl // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,careerYears: null == careerYears ? _self.careerYears : careerYears // ignore: cast_nullable_to_non_nullable
as int,specialties: null == specialties ? _self.specialties : specialties // ignore: cast_nullable_to_non_nullable
as List<String>,certifications: null == certifications ? _self.certifications : certifications // ignore: cast_nullable_to_non_nullable
as List<String>,awards: null == awards ? _self.awards : awards // ignore: cast_nullable_to_non_nullable
as List<String>,bio: null == bio ? _self.bio : bio // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [StaffProfileDto].
extension StaffProfileDtoPatterns on StaffProfileDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StaffProfileDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StaffProfileDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StaffProfileDto value)  $default,){
final _that = this;
switch (_that) {
case _StaffProfileDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StaffProfileDto value)?  $default,){
final _that = this;
switch (_that) {
case _StaffProfileDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'photo_url')  String photoUrl,  String title, @JsonKey(name: 'career_years')  int careerYears,  List<String> specialties,  List<String> certifications,  List<String> awards,  String bio)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StaffProfileDto() when $default != null:
return $default(_that.photoUrl,_that.title,_that.careerYears,_that.specialties,_that.certifications,_that.awards,_that.bio);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'photo_url')  String photoUrl,  String title, @JsonKey(name: 'career_years')  int careerYears,  List<String> specialties,  List<String> certifications,  List<String> awards,  String bio)  $default,) {final _that = this;
switch (_that) {
case _StaffProfileDto():
return $default(_that.photoUrl,_that.title,_that.careerYears,_that.specialties,_that.certifications,_that.awards,_that.bio);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'photo_url')  String photoUrl,  String title, @JsonKey(name: 'career_years')  int careerYears,  List<String> specialties,  List<String> certifications,  List<String> awards,  String bio)?  $default,) {final _that = this;
switch (_that) {
case _StaffProfileDto() when $default != null:
return $default(_that.photoUrl,_that.title,_that.careerYears,_that.specialties,_that.certifications,_that.awards,_that.bio);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StaffProfileDto extends StaffProfileDto {
  const _StaffProfileDto({@JsonKey(name: 'photo_url') this.photoUrl = '', this.title = '', @JsonKey(name: 'career_years') this.careerYears = 0, final  List<String> specialties = const [], final  List<String> certifications = const [], final  List<String> awards = const [], this.bio = ''}): _specialties = specialties,_certifications = certifications,_awards = awards,super._();
  factory _StaffProfileDto.fromJson(Map<String, dynamic> json) => _$StaffProfileDtoFromJson(json);

@override@JsonKey(name: 'photo_url') final  String photoUrl;
@override@JsonKey() final  String title;
// 직함(예: "퍼포먼스 트레이너")
@override@JsonKey(name: 'career_years') final  int careerYears;
// 0=미표기
 final  List<String> _specialties;
// 0=미표기
@override@JsonKey() List<String> get specialties {
  if (_specialties is EqualUnmodifiableListView) return _specialties;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_specialties);
}

 final  List<String> _certifications;
@override@JsonKey() List<String> get certifications {
  if (_certifications is EqualUnmodifiableListView) return _certifications;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_certifications);
}

 final  List<String> _awards;
@override@JsonKey() List<String> get awards {
  if (_awards is EqualUnmodifiableListView) return _awards;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_awards);
}

// 수상·선수 경력
@override@JsonKey() final  String bio;

/// Create a copy of StaffProfileDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StaffProfileDtoCopyWith<_StaffProfileDto> get copyWith => __$StaffProfileDtoCopyWithImpl<_StaffProfileDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StaffProfileDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StaffProfileDto&&(identical(other.photoUrl, photoUrl) || other.photoUrl == photoUrl)&&(identical(other.title, title) || other.title == title)&&(identical(other.careerYears, careerYears) || other.careerYears == careerYears)&&const DeepCollectionEquality().equals(other._specialties, _specialties)&&const DeepCollectionEquality().equals(other._certifications, _certifications)&&const DeepCollectionEquality().equals(other._awards, _awards)&&(identical(other.bio, bio) || other.bio == bio));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,photoUrl,title,careerYears,const DeepCollectionEquality().hash(_specialties),const DeepCollectionEquality().hash(_certifications),const DeepCollectionEquality().hash(_awards),bio);

@override
String toString() {
  return 'StaffProfileDto(photoUrl: $photoUrl, title: $title, careerYears: $careerYears, specialties: $specialties, certifications: $certifications, awards: $awards, bio: $bio)';
}


}

/// @nodoc
abstract mixin class _$StaffProfileDtoCopyWith<$Res> implements $StaffProfileDtoCopyWith<$Res> {
  factory _$StaffProfileDtoCopyWith(_StaffProfileDto value, $Res Function(_StaffProfileDto) _then) = __$StaffProfileDtoCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'photo_url') String photoUrl, String title,@JsonKey(name: 'career_years') int careerYears, List<String> specialties, List<String> certifications, List<String> awards, String bio
});




}
/// @nodoc
class __$StaffProfileDtoCopyWithImpl<$Res>
    implements _$StaffProfileDtoCopyWith<$Res> {
  __$StaffProfileDtoCopyWithImpl(this._self, this._then);

  final _StaffProfileDto _self;
  final $Res Function(_StaffProfileDto) _then;

/// Create a copy of StaffProfileDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? photoUrl = null,Object? title = null,Object? careerYears = null,Object? specialties = null,Object? certifications = null,Object? awards = null,Object? bio = null,}) {
  return _then(_StaffProfileDto(
photoUrl: null == photoUrl ? _self.photoUrl : photoUrl // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,careerYears: null == careerYears ? _self.careerYears : careerYears // ignore: cast_nullable_to_non_nullable
as int,specialties: null == specialties ? _self._specialties : specialties // ignore: cast_nullable_to_non_nullable
as List<String>,certifications: null == certifications ? _self._certifications : certifications // ignore: cast_nullable_to_non_nullable
as List<String>,awards: null == awards ? _self._awards : awards // ignore: cast_nullable_to_non_nullable
as List<String>,bio: null == bio ? _self.bio : bio // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
