// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'member_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MemberDto {

 String get id; String get name; String get phone; String? get channel;@JsonKey(name: 'trainer_id') String? get trainerId; List<MemberFlagDto> get flags; ConsentDto? get consent;@JsonKey(name: 'app_linked') bool get appLinked; String get status;// active|dormant
@JsonKey(name: 'last_visit_at') String? get lastVisitAt;/// 체형 촬영 포즈 시퀀스(계약 v2.10). **nullable로 둔다** — 구버전 서버는 이 키를
/// 안 보내고, required로 파싱하면 회원 목록 전체가 던져 앱이 통째로 죽는다
/// (인바디 `source`에서 같은 이유로 nullable을 택한 전례).
/// 서버는 응답에서 항상 구체화해 주므로 정상 경로에선 비어 있지 않다.
@JsonKey(name: 'body_poses') List<BodyPoseDto>? get bodyPoses;
/// Create a copy of MemberDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemberDtoCopyWith<MemberDto> get copyWith => _$MemberDtoCopyWithImpl<MemberDto>(this as MemberDto, _$identity);

  /// Serializes this MemberDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemberDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.channel, channel) || other.channel == channel)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&const DeepCollectionEquality().equals(other.flags, flags)&&(identical(other.consent, consent) || other.consent == consent)&&(identical(other.appLinked, appLinked) || other.appLinked == appLinked)&&(identical(other.status, status) || other.status == status)&&(identical(other.lastVisitAt, lastVisitAt) || other.lastVisitAt == lastVisitAt)&&const DeepCollectionEquality().equals(other.bodyPoses, bodyPoses));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,phone,channel,trainerId,const DeepCollectionEquality().hash(flags),consent,appLinked,status,lastVisitAt,const DeepCollectionEquality().hash(bodyPoses));

@override
String toString() {
  return 'MemberDto(id: $id, name: $name, phone: $phone, channel: $channel, trainerId: $trainerId, flags: $flags, consent: $consent, appLinked: $appLinked, status: $status, lastVisitAt: $lastVisitAt, bodyPoses: $bodyPoses)';
}


}

/// @nodoc
abstract mixin class $MemberDtoCopyWith<$Res>  {
  factory $MemberDtoCopyWith(MemberDto value, $Res Function(MemberDto) _then) = _$MemberDtoCopyWithImpl;
@useResult
$Res call({
 String id, String name, String phone, String? channel,@JsonKey(name: 'trainer_id') String? trainerId, List<MemberFlagDto> flags, ConsentDto? consent,@JsonKey(name: 'app_linked') bool appLinked, String status,@JsonKey(name: 'last_visit_at') String? lastVisitAt,@JsonKey(name: 'body_poses') List<BodyPoseDto>? bodyPoses
});


$ConsentDtoCopyWith<$Res>? get consent;

}
/// @nodoc
class _$MemberDtoCopyWithImpl<$Res>
    implements $MemberDtoCopyWith<$Res> {
  _$MemberDtoCopyWithImpl(this._self, this._then);

  final MemberDto _self;
  final $Res Function(MemberDto) _then;

/// Create a copy of MemberDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? phone = null,Object? channel = freezed,Object? trainerId = freezed,Object? flags = null,Object? consent = freezed,Object? appLinked = null,Object? status = null,Object? lastVisitAt = freezed,Object? bodyPoses = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,channel: freezed == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String?,trainerId: freezed == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String?,flags: null == flags ? _self.flags : flags // ignore: cast_nullable_to_non_nullable
as List<MemberFlagDto>,consent: freezed == consent ? _self.consent : consent // ignore: cast_nullable_to_non_nullable
as ConsentDto?,appLinked: null == appLinked ? _self.appLinked : appLinked // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,lastVisitAt: freezed == lastVisitAt ? _self.lastVisitAt : lastVisitAt // ignore: cast_nullable_to_non_nullable
as String?,bodyPoses: freezed == bodyPoses ? _self.bodyPoses : bodyPoses // ignore: cast_nullable_to_non_nullable
as List<BodyPoseDto>?,
  ));
}
/// Create a copy of MemberDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConsentDtoCopyWith<$Res>? get consent {
    if (_self.consent == null) {
    return null;
  }

  return $ConsentDtoCopyWith<$Res>(_self.consent!, (value) {
    return _then(_self.copyWith(consent: value));
  });
}
}


/// Adds pattern-matching-related methods to [MemberDto].
extension MemberDtoPatterns on MemberDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemberDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemberDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemberDto value)  $default,){
final _that = this;
switch (_that) {
case _MemberDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemberDto value)?  $default,){
final _that = this;
switch (_that) {
case _MemberDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String phone,  String? channel, @JsonKey(name: 'trainer_id')  String? trainerId,  List<MemberFlagDto> flags,  ConsentDto? consent, @JsonKey(name: 'app_linked')  bool appLinked,  String status, @JsonKey(name: 'last_visit_at')  String? lastVisitAt, @JsonKey(name: 'body_poses')  List<BodyPoseDto>? bodyPoses)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemberDto() when $default != null:
return $default(_that.id,_that.name,_that.phone,_that.channel,_that.trainerId,_that.flags,_that.consent,_that.appLinked,_that.status,_that.lastVisitAt,_that.bodyPoses);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String phone,  String? channel, @JsonKey(name: 'trainer_id')  String? trainerId,  List<MemberFlagDto> flags,  ConsentDto? consent, @JsonKey(name: 'app_linked')  bool appLinked,  String status, @JsonKey(name: 'last_visit_at')  String? lastVisitAt, @JsonKey(name: 'body_poses')  List<BodyPoseDto>? bodyPoses)  $default,) {final _that = this;
switch (_that) {
case _MemberDto():
return $default(_that.id,_that.name,_that.phone,_that.channel,_that.trainerId,_that.flags,_that.consent,_that.appLinked,_that.status,_that.lastVisitAt,_that.bodyPoses);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String phone,  String? channel, @JsonKey(name: 'trainer_id')  String? trainerId,  List<MemberFlagDto> flags,  ConsentDto? consent, @JsonKey(name: 'app_linked')  bool appLinked,  String status, @JsonKey(name: 'last_visit_at')  String? lastVisitAt, @JsonKey(name: 'body_poses')  List<BodyPoseDto>? bodyPoses)?  $default,) {final _that = this;
switch (_that) {
case _MemberDto() when $default != null:
return $default(_that.id,_that.name,_that.phone,_that.channel,_that.trainerId,_that.flags,_that.consent,_that.appLinked,_that.status,_that.lastVisitAt,_that.bodyPoses);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MemberDto implements MemberDto {
  const _MemberDto({required this.id, required this.name, required this.phone, this.channel, @JsonKey(name: 'trainer_id') this.trainerId, final  List<MemberFlagDto> flags = const <MemberFlagDto>[], this.consent, @JsonKey(name: 'app_linked') this.appLinked = false, this.status = 'active', @JsonKey(name: 'last_visit_at') this.lastVisitAt, @JsonKey(name: 'body_poses') final  List<BodyPoseDto>? bodyPoses}): _flags = flags,_bodyPoses = bodyPoses;
  factory _MemberDto.fromJson(Map<String, dynamic> json) => _$MemberDtoFromJson(json);

@override final  String id;
@override final  String name;
@override final  String phone;
@override final  String? channel;
@override@JsonKey(name: 'trainer_id') final  String? trainerId;
 final  List<MemberFlagDto> _flags;
@override@JsonKey() List<MemberFlagDto> get flags {
  if (_flags is EqualUnmodifiableListView) return _flags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_flags);
}

@override final  ConsentDto? consent;
@override@JsonKey(name: 'app_linked') final  bool appLinked;
@override@JsonKey() final  String status;
// active|dormant
@override@JsonKey(name: 'last_visit_at') final  String? lastVisitAt;
/// 체형 촬영 포즈 시퀀스(계약 v2.10). **nullable로 둔다** — 구버전 서버는 이 키를
/// 안 보내고, required로 파싱하면 회원 목록 전체가 던져 앱이 통째로 죽는다
/// (인바디 `source`에서 같은 이유로 nullable을 택한 전례).
/// 서버는 응답에서 항상 구체화해 주므로 정상 경로에선 비어 있지 않다.
 final  List<BodyPoseDto>? _bodyPoses;
/// 체형 촬영 포즈 시퀀스(계약 v2.10). **nullable로 둔다** — 구버전 서버는 이 키를
/// 안 보내고, required로 파싱하면 회원 목록 전체가 던져 앱이 통째로 죽는다
/// (인바디 `source`에서 같은 이유로 nullable을 택한 전례).
/// 서버는 응답에서 항상 구체화해 주므로 정상 경로에선 비어 있지 않다.
@override@JsonKey(name: 'body_poses') List<BodyPoseDto>? get bodyPoses {
  final value = _bodyPoses;
  if (value == null) return null;
  if (_bodyPoses is EqualUnmodifiableListView) return _bodyPoses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of MemberDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemberDtoCopyWith<_MemberDto> get copyWith => __$MemberDtoCopyWithImpl<_MemberDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MemberDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemberDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.channel, channel) || other.channel == channel)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&const DeepCollectionEquality().equals(other._flags, _flags)&&(identical(other.consent, consent) || other.consent == consent)&&(identical(other.appLinked, appLinked) || other.appLinked == appLinked)&&(identical(other.status, status) || other.status == status)&&(identical(other.lastVisitAt, lastVisitAt) || other.lastVisitAt == lastVisitAt)&&const DeepCollectionEquality().equals(other._bodyPoses, _bodyPoses));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,phone,channel,trainerId,const DeepCollectionEquality().hash(_flags),consent,appLinked,status,lastVisitAt,const DeepCollectionEquality().hash(_bodyPoses));

@override
String toString() {
  return 'MemberDto(id: $id, name: $name, phone: $phone, channel: $channel, trainerId: $trainerId, flags: $flags, consent: $consent, appLinked: $appLinked, status: $status, lastVisitAt: $lastVisitAt, bodyPoses: $bodyPoses)';
}


}

/// @nodoc
abstract mixin class _$MemberDtoCopyWith<$Res> implements $MemberDtoCopyWith<$Res> {
  factory _$MemberDtoCopyWith(_MemberDto value, $Res Function(_MemberDto) _then) = __$MemberDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String phone, String? channel,@JsonKey(name: 'trainer_id') String? trainerId, List<MemberFlagDto> flags, ConsentDto? consent,@JsonKey(name: 'app_linked') bool appLinked, String status,@JsonKey(name: 'last_visit_at') String? lastVisitAt,@JsonKey(name: 'body_poses') List<BodyPoseDto>? bodyPoses
});


@override $ConsentDtoCopyWith<$Res>? get consent;

}
/// @nodoc
class __$MemberDtoCopyWithImpl<$Res>
    implements _$MemberDtoCopyWith<$Res> {
  __$MemberDtoCopyWithImpl(this._self, this._then);

  final _MemberDto _self;
  final $Res Function(_MemberDto) _then;

/// Create a copy of MemberDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? phone = null,Object? channel = freezed,Object? trainerId = freezed,Object? flags = null,Object? consent = freezed,Object? appLinked = null,Object? status = null,Object? lastVisitAt = freezed,Object? bodyPoses = freezed,}) {
  return _then(_MemberDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,channel: freezed == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String?,trainerId: freezed == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String?,flags: null == flags ? _self._flags : flags // ignore: cast_nullable_to_non_nullable
as List<MemberFlagDto>,consent: freezed == consent ? _self.consent : consent // ignore: cast_nullable_to_non_nullable
as ConsentDto?,appLinked: null == appLinked ? _self.appLinked : appLinked // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,lastVisitAt: freezed == lastVisitAt ? _self.lastVisitAt : lastVisitAt // ignore: cast_nullable_to_non_nullable
as String?,bodyPoses: freezed == bodyPoses ? _self._bodyPoses : bodyPoses // ignore: cast_nullable_to_non_nullable
as List<BodyPoseDto>?,
  ));
}

/// Create a copy of MemberDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConsentDtoCopyWith<$Res>? get consent {
    if (_self.consent == null) {
    return null;
  }

  return $ConsentDtoCopyWith<$Res>(_self.consent!, (value) {
    return _then(_self.copyWith(consent: value));
  });
}
}


/// @nodoc
mixin _$BodyPoseDto {

 String get key; String get label;
/// Create a copy of BodyPoseDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BodyPoseDtoCopyWith<BodyPoseDto> get copyWith => _$BodyPoseDtoCopyWithImpl<BodyPoseDto>(this as BodyPoseDto, _$identity);

  /// Serializes this BodyPoseDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BodyPoseDto&&(identical(other.key, key) || other.key == key)&&(identical(other.label, label) || other.label == label));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,key,label);

@override
String toString() {
  return 'BodyPoseDto(key: $key, label: $label)';
}


}

/// @nodoc
abstract mixin class $BodyPoseDtoCopyWith<$Res>  {
  factory $BodyPoseDtoCopyWith(BodyPoseDto value, $Res Function(BodyPoseDto) _then) = _$BodyPoseDtoCopyWithImpl;
@useResult
$Res call({
 String key, String label
});




}
/// @nodoc
class _$BodyPoseDtoCopyWithImpl<$Res>
    implements $BodyPoseDtoCopyWith<$Res> {
  _$BodyPoseDtoCopyWithImpl(this._self, this._then);

  final BodyPoseDto _self;
  final $Res Function(BodyPoseDto) _then;

/// Create a copy of BodyPoseDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? label = null,}) {
  return _then(_self.copyWith(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BodyPoseDto].
extension BodyPoseDtoPatterns on BodyPoseDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BodyPoseDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BodyPoseDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BodyPoseDto value)  $default,){
final _that = this;
switch (_that) {
case _BodyPoseDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BodyPoseDto value)?  $default,){
final _that = this;
switch (_that) {
case _BodyPoseDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  String label)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BodyPoseDto() when $default != null:
return $default(_that.key,_that.label);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  String label)  $default,) {final _that = this;
switch (_that) {
case _BodyPoseDto():
return $default(_that.key,_that.label);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  String label)?  $default,) {final _that = this;
switch (_that) {
case _BodyPoseDto() when $default != null:
return $default(_that.key,_that.label);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BodyPoseDto implements BodyPoseDto {
  const _BodyPoseDto({required this.key, required this.label});
  factory _BodyPoseDto.fromJson(Map<String, dynamic> json) => _$BodyPoseDtoFromJson(json);

@override final  String key;
@override final  String label;

/// Create a copy of BodyPoseDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BodyPoseDtoCopyWith<_BodyPoseDto> get copyWith => __$BodyPoseDtoCopyWithImpl<_BodyPoseDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BodyPoseDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BodyPoseDto&&(identical(other.key, key) || other.key == key)&&(identical(other.label, label) || other.label == label));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,key,label);

@override
String toString() {
  return 'BodyPoseDto(key: $key, label: $label)';
}


}

/// @nodoc
abstract mixin class _$BodyPoseDtoCopyWith<$Res> implements $BodyPoseDtoCopyWith<$Res> {
  factory _$BodyPoseDtoCopyWith(_BodyPoseDto value, $Res Function(_BodyPoseDto) _then) = __$BodyPoseDtoCopyWithImpl;
@override @useResult
$Res call({
 String key, String label
});




}
/// @nodoc
class __$BodyPoseDtoCopyWithImpl<$Res>
    implements _$BodyPoseDtoCopyWith<$Res> {
  __$BodyPoseDtoCopyWithImpl(this._self, this._then);

  final _BodyPoseDto _self;
  final $Res Function(_BodyPoseDto) _then;

/// Create a copy of BodyPoseDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? label = null,}) {
  return _then(_BodyPoseDto(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$MemberFlagDto {

 String get type;// 예: "injury"
 String? get note;
/// Create a copy of MemberFlagDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemberFlagDtoCopyWith<MemberFlagDto> get copyWith => _$MemberFlagDtoCopyWithImpl<MemberFlagDto>(this as MemberFlagDto, _$identity);

  /// Serializes this MemberFlagDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemberFlagDto&&(identical(other.type, type) || other.type == type)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,note);

@override
String toString() {
  return 'MemberFlagDto(type: $type, note: $note)';
}


}

/// @nodoc
abstract mixin class $MemberFlagDtoCopyWith<$Res>  {
  factory $MemberFlagDtoCopyWith(MemberFlagDto value, $Res Function(MemberFlagDto) _then) = _$MemberFlagDtoCopyWithImpl;
@useResult
$Res call({
 String type, String? note
});




}
/// @nodoc
class _$MemberFlagDtoCopyWithImpl<$Res>
    implements $MemberFlagDtoCopyWith<$Res> {
  _$MemberFlagDtoCopyWithImpl(this._self, this._then);

  final MemberFlagDto _self;
  final $Res Function(MemberFlagDto) _then;

/// Create a copy of MemberFlagDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? note = freezed,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [MemberFlagDto].
extension MemberFlagDtoPatterns on MemberFlagDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemberFlagDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemberFlagDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemberFlagDto value)  $default,){
final _that = this;
switch (_that) {
case _MemberFlagDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemberFlagDto value)?  $default,){
final _that = this;
switch (_that) {
case _MemberFlagDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String type,  String? note)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemberFlagDto() when $default != null:
return $default(_that.type,_that.note);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String type,  String? note)  $default,) {final _that = this;
switch (_that) {
case _MemberFlagDto():
return $default(_that.type,_that.note);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String type,  String? note)?  $default,) {final _that = this;
switch (_that) {
case _MemberFlagDto() when $default != null:
return $default(_that.type,_that.note);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MemberFlagDto implements MemberFlagDto {
  const _MemberFlagDto({required this.type, this.note});
  factory _MemberFlagDto.fromJson(Map<String, dynamic> json) => _$MemberFlagDtoFromJson(json);

@override final  String type;
// 예: "injury"
@override final  String? note;

/// Create a copy of MemberFlagDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemberFlagDtoCopyWith<_MemberFlagDto> get copyWith => __$MemberFlagDtoCopyWithImpl<_MemberFlagDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MemberFlagDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemberFlagDto&&(identical(other.type, type) || other.type == type)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,note);

@override
String toString() {
  return 'MemberFlagDto(type: $type, note: $note)';
}


}

/// @nodoc
abstract mixin class _$MemberFlagDtoCopyWith<$Res> implements $MemberFlagDtoCopyWith<$Res> {
  factory _$MemberFlagDtoCopyWith(_MemberFlagDto value, $Res Function(_MemberFlagDto) _then) = __$MemberFlagDtoCopyWithImpl;
@override @useResult
$Res call({
 String type, String? note
});




}
/// @nodoc
class __$MemberFlagDtoCopyWithImpl<$Res>
    implements _$MemberFlagDtoCopyWith<$Res> {
  __$MemberFlagDtoCopyWithImpl(this._self, this._then);

  final _MemberFlagDto _self;
  final $Res Function(_MemberFlagDto) _then;

/// Create a copy of MemberFlagDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? note = freezed,}) {
  return _then(_MemberFlagDto(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$ConsentDto {

 bool get general; bool get sensitive;@JsonKey(name: 'signed_at') String? get signedAt;@JsonKey(name: 'revoked_at') String? get revokedAt;
/// Create a copy of ConsentDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConsentDtoCopyWith<ConsentDto> get copyWith => _$ConsentDtoCopyWithImpl<ConsentDto>(this as ConsentDto, _$identity);

  /// Serializes this ConsentDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConsentDto&&(identical(other.general, general) || other.general == general)&&(identical(other.sensitive, sensitive) || other.sensitive == sensitive)&&(identical(other.signedAt, signedAt) || other.signedAt == signedAt)&&(identical(other.revokedAt, revokedAt) || other.revokedAt == revokedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,general,sensitive,signedAt,revokedAt);

@override
String toString() {
  return 'ConsentDto(general: $general, sensitive: $sensitive, signedAt: $signedAt, revokedAt: $revokedAt)';
}


}

/// @nodoc
abstract mixin class $ConsentDtoCopyWith<$Res>  {
  factory $ConsentDtoCopyWith(ConsentDto value, $Res Function(ConsentDto) _then) = _$ConsentDtoCopyWithImpl;
@useResult
$Res call({
 bool general, bool sensitive,@JsonKey(name: 'signed_at') String? signedAt,@JsonKey(name: 'revoked_at') String? revokedAt
});




}
/// @nodoc
class _$ConsentDtoCopyWithImpl<$Res>
    implements $ConsentDtoCopyWith<$Res> {
  _$ConsentDtoCopyWithImpl(this._self, this._then);

  final ConsentDto _self;
  final $Res Function(ConsentDto) _then;

/// Create a copy of ConsentDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? general = null,Object? sensitive = null,Object? signedAt = freezed,Object? revokedAt = freezed,}) {
  return _then(_self.copyWith(
general: null == general ? _self.general : general // ignore: cast_nullable_to_non_nullable
as bool,sensitive: null == sensitive ? _self.sensitive : sensitive // ignore: cast_nullable_to_non_nullable
as bool,signedAt: freezed == signedAt ? _self.signedAt : signedAt // ignore: cast_nullable_to_non_nullable
as String?,revokedAt: freezed == revokedAt ? _self.revokedAt : revokedAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ConsentDto].
extension ConsentDtoPatterns on ConsentDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConsentDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConsentDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConsentDto value)  $default,){
final _that = this;
switch (_that) {
case _ConsentDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConsentDto value)?  $default,){
final _that = this;
switch (_that) {
case _ConsentDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool general,  bool sensitive, @JsonKey(name: 'signed_at')  String? signedAt, @JsonKey(name: 'revoked_at')  String? revokedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConsentDto() when $default != null:
return $default(_that.general,_that.sensitive,_that.signedAt,_that.revokedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool general,  bool sensitive, @JsonKey(name: 'signed_at')  String? signedAt, @JsonKey(name: 'revoked_at')  String? revokedAt)  $default,) {final _that = this;
switch (_that) {
case _ConsentDto():
return $default(_that.general,_that.sensitive,_that.signedAt,_that.revokedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool general,  bool sensitive, @JsonKey(name: 'signed_at')  String? signedAt, @JsonKey(name: 'revoked_at')  String? revokedAt)?  $default,) {final _that = this;
switch (_that) {
case _ConsentDto() when $default != null:
return $default(_that.general,_that.sensitive,_that.signedAt,_that.revokedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConsentDto implements ConsentDto {
  const _ConsentDto({this.general = false, this.sensitive = false, @JsonKey(name: 'signed_at') this.signedAt, @JsonKey(name: 'revoked_at') this.revokedAt});
  factory _ConsentDto.fromJson(Map<String, dynamic> json) => _$ConsentDtoFromJson(json);

@override@JsonKey() final  bool general;
@override@JsonKey() final  bool sensitive;
@override@JsonKey(name: 'signed_at') final  String? signedAt;
@override@JsonKey(name: 'revoked_at') final  String? revokedAt;

/// Create a copy of ConsentDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConsentDtoCopyWith<_ConsentDto> get copyWith => __$ConsentDtoCopyWithImpl<_ConsentDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConsentDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConsentDto&&(identical(other.general, general) || other.general == general)&&(identical(other.sensitive, sensitive) || other.sensitive == sensitive)&&(identical(other.signedAt, signedAt) || other.signedAt == signedAt)&&(identical(other.revokedAt, revokedAt) || other.revokedAt == revokedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,general,sensitive,signedAt,revokedAt);

@override
String toString() {
  return 'ConsentDto(general: $general, sensitive: $sensitive, signedAt: $signedAt, revokedAt: $revokedAt)';
}


}

/// @nodoc
abstract mixin class _$ConsentDtoCopyWith<$Res> implements $ConsentDtoCopyWith<$Res> {
  factory _$ConsentDtoCopyWith(_ConsentDto value, $Res Function(_ConsentDto) _then) = __$ConsentDtoCopyWithImpl;
@override @useResult
$Res call({
 bool general, bool sensitive,@JsonKey(name: 'signed_at') String? signedAt,@JsonKey(name: 'revoked_at') String? revokedAt
});




}
/// @nodoc
class __$ConsentDtoCopyWithImpl<$Res>
    implements _$ConsentDtoCopyWith<$Res> {
  __$ConsentDtoCopyWithImpl(this._self, this._then);

  final _ConsentDto _self;
  final $Res Function(_ConsentDto) _then;

/// Create a copy of ConsentDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? general = null,Object? sensitive = null,Object? signedAt = freezed,Object? revokedAt = freezed,}) {
  return _then(_ConsentDto(
general: null == general ? _self.general : general // ignore: cast_nullable_to_non_nullable
as bool,sensitive: null == sensitive ? _self.sensitive : sensitive // ignore: cast_nullable_to_non_nullable
as bool,signedAt: freezed == signedAt ? _self.signedAt : signedAt // ignore: cast_nullable_to_non_nullable
as String?,revokedAt: freezed == revokedAt ? _self.revokedAt : revokedAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
