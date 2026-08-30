// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'center_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CenterResponseDto {

@JsonKey(name: 'center_id') String get centerId; CenterPolicyDto get policy;
/// Create a copy of CenterResponseDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CenterResponseDtoCopyWith<CenterResponseDto> get copyWith => _$CenterResponseDtoCopyWithImpl<CenterResponseDto>(this as CenterResponseDto, _$identity);

  /// Serializes this CenterResponseDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CenterResponseDto&&(identical(other.centerId, centerId) || other.centerId == centerId)&&(identical(other.policy, policy) || other.policy == policy));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,centerId,policy);

@override
String toString() {
  return 'CenterResponseDto(centerId: $centerId, policy: $policy)';
}


}

/// @nodoc
abstract mixin class $CenterResponseDtoCopyWith<$Res>  {
  factory $CenterResponseDtoCopyWith(CenterResponseDto value, $Res Function(CenterResponseDto) _then) = _$CenterResponseDtoCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'center_id') String centerId, CenterPolicyDto policy
});


$CenterPolicyDtoCopyWith<$Res> get policy;

}
/// @nodoc
class _$CenterResponseDtoCopyWithImpl<$Res>
    implements $CenterResponseDtoCopyWith<$Res> {
  _$CenterResponseDtoCopyWithImpl(this._self, this._then);

  final CenterResponseDto _self;
  final $Res Function(CenterResponseDto) _then;

/// Create a copy of CenterResponseDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? centerId = null,Object? policy = null,}) {
  return _then(_self.copyWith(
centerId: null == centerId ? _self.centerId : centerId // ignore: cast_nullable_to_non_nullable
as String,policy: null == policy ? _self.policy : policy // ignore: cast_nullable_to_non_nullable
as CenterPolicyDto,
  ));
}
/// Create a copy of CenterResponseDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CenterPolicyDtoCopyWith<$Res> get policy {
  
  return $CenterPolicyDtoCopyWith<$Res>(_self.policy, (value) {
    return _then(_self.copyWith(policy: value));
  });
}
}


/// Adds pattern-matching-related methods to [CenterResponseDto].
extension CenterResponseDtoPatterns on CenterResponseDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CenterResponseDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CenterResponseDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CenterResponseDto value)  $default,){
final _that = this;
switch (_that) {
case _CenterResponseDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CenterResponseDto value)?  $default,){
final _that = this;
switch (_that) {
case _CenterResponseDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'center_id')  String centerId,  CenterPolicyDto policy)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CenterResponseDto() when $default != null:
return $default(_that.centerId,_that.policy);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'center_id')  String centerId,  CenterPolicyDto policy)  $default,) {final _that = this;
switch (_that) {
case _CenterResponseDto():
return $default(_that.centerId,_that.policy);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'center_id')  String centerId,  CenterPolicyDto policy)?  $default,) {final _that = this;
switch (_that) {
case _CenterResponseDto() when $default != null:
return $default(_that.centerId,_that.policy);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CenterResponseDto implements CenterResponseDto {
  const _CenterResponseDto({@JsonKey(name: 'center_id') required this.centerId, required this.policy});
  factory _CenterResponseDto.fromJson(Map<String, dynamic> json) => _$CenterResponseDtoFromJson(json);

@override@JsonKey(name: 'center_id') final  String centerId;
@override final  CenterPolicyDto policy;

/// Create a copy of CenterResponseDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CenterResponseDtoCopyWith<_CenterResponseDto> get copyWith => __$CenterResponseDtoCopyWithImpl<_CenterResponseDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CenterResponseDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CenterResponseDto&&(identical(other.centerId, centerId) || other.centerId == centerId)&&(identical(other.policy, policy) || other.policy == policy));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,centerId,policy);

@override
String toString() {
  return 'CenterResponseDto(centerId: $centerId, policy: $policy)';
}


}

/// @nodoc
abstract mixin class _$CenterResponseDtoCopyWith<$Res> implements $CenterResponseDtoCopyWith<$Res> {
  factory _$CenterResponseDtoCopyWith(_CenterResponseDto value, $Res Function(_CenterResponseDto) _then) = __$CenterResponseDtoCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'center_id') String centerId, CenterPolicyDto policy
});


@override $CenterPolicyDtoCopyWith<$Res> get policy;

}
/// @nodoc
class __$CenterResponseDtoCopyWithImpl<$Res>
    implements _$CenterResponseDtoCopyWith<$Res> {
  __$CenterResponseDtoCopyWithImpl(this._self, this._then);

  final _CenterResponseDto _self;
  final $Res Function(_CenterResponseDto) _then;

/// Create a copy of CenterResponseDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? centerId = null,Object? policy = null,}) {
  return _then(_CenterResponseDto(
centerId: null == centerId ? _self.centerId : centerId // ignore: cast_nullable_to_non_nullable
as String,policy: null == policy ? _self.policy : policy // ignore: cast_nullable_to_non_nullable
as CenterPolicyDto,
  ));
}

/// Create a copy of CenterResponseDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CenterPolicyDtoCopyWith<$Res> get policy {
  
  return $CenterPolicyDtoCopyWith<$Res>(_self.policy, (value) {
    return _then(_self.copyWith(policy: value));
  });
}
}


/// @nodoc
mixin _$CenterPolicyDto {

@JsonKey(name: 'slot_capacity') int get slotCapacity;@JsonKey(name: 'cancel_cutoff_hours') int get cancelCutoffHours;@JsonKey(name: 'grace_once') bool get graceOnce;@JsonKey(name: 'penalty_rate') double get penaltyRate;/// 만료임박 기준일(대표가 설정 화면에서 정한다). 서버는 v1부터 이 값을 내려주는데
/// 앱이 파싱하지 않아, 홈의 "연장 상담 가능" 배지가 **조건 없이 항상** 켜져 있었다.
@JsonKey(name: 'expiring_days') int get expiringDays;@JsonKey(name: 'max_holds_per_pass') int get maxHoldsPerPass;@JsonKey(name: 'max_hold_total_days') int get maxHoldTotalDays;/// 센터 운영시간 — **슬롯 시작 시각, 양끝 포함**(9·21 → 09시 시작 ~ 21시 시작 13칸).
///
/// **이웃 필드와 달리 nullable이고 `@Default`가 없다.** 여기에 `@Default(9)`를
/// 박으면 같은 숫자가 DTO와 `CenterPolicy.fallback` 두 군데에 살면서 따로 움직일
/// 수 있는데, 이 두 자리는 반드시 같아야 한다 — "서버가 필드를 안 준 구버전"과
/// "정책 조회 자체가 실패"는 회원에게 **똑같이 오늘의 09~21시**로 보여야 한다.
/// 그래서 "서버가 안 줬다"를 null 그대로 넘기고, 기본값과 유효성(open ≤ close,
/// 0..23)은 정책을 읽는 경계 한 곳(`CenterPolicy.resolveHours`)이 전담한다.
@JsonKey(name: 'open_hour', fromJson: _hourOrNull) int? get openHour;@JsonKey(name: 'close_hour', fromJson: _hourOrNull) int? get closeHour;
/// Create a copy of CenterPolicyDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CenterPolicyDtoCopyWith<CenterPolicyDto> get copyWith => _$CenterPolicyDtoCopyWithImpl<CenterPolicyDto>(this as CenterPolicyDto, _$identity);

  /// Serializes this CenterPolicyDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CenterPolicyDto&&(identical(other.slotCapacity, slotCapacity) || other.slotCapacity == slotCapacity)&&(identical(other.cancelCutoffHours, cancelCutoffHours) || other.cancelCutoffHours == cancelCutoffHours)&&(identical(other.graceOnce, graceOnce) || other.graceOnce == graceOnce)&&(identical(other.penaltyRate, penaltyRate) || other.penaltyRate == penaltyRate)&&(identical(other.expiringDays, expiringDays) || other.expiringDays == expiringDays)&&(identical(other.maxHoldsPerPass, maxHoldsPerPass) || other.maxHoldsPerPass == maxHoldsPerPass)&&(identical(other.maxHoldTotalDays, maxHoldTotalDays) || other.maxHoldTotalDays == maxHoldTotalDays)&&(identical(other.openHour, openHour) || other.openHour == openHour)&&(identical(other.closeHour, closeHour) || other.closeHour == closeHour));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,slotCapacity,cancelCutoffHours,graceOnce,penaltyRate,expiringDays,maxHoldsPerPass,maxHoldTotalDays,openHour,closeHour);

@override
String toString() {
  return 'CenterPolicyDto(slotCapacity: $slotCapacity, cancelCutoffHours: $cancelCutoffHours, graceOnce: $graceOnce, penaltyRate: $penaltyRate, expiringDays: $expiringDays, maxHoldsPerPass: $maxHoldsPerPass, maxHoldTotalDays: $maxHoldTotalDays, openHour: $openHour, closeHour: $closeHour)';
}


}

/// @nodoc
abstract mixin class $CenterPolicyDtoCopyWith<$Res>  {
  factory $CenterPolicyDtoCopyWith(CenterPolicyDto value, $Res Function(CenterPolicyDto) _then) = _$CenterPolicyDtoCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'slot_capacity') int slotCapacity,@JsonKey(name: 'cancel_cutoff_hours') int cancelCutoffHours,@JsonKey(name: 'grace_once') bool graceOnce,@JsonKey(name: 'penalty_rate') double penaltyRate,@JsonKey(name: 'expiring_days') int expiringDays,@JsonKey(name: 'max_holds_per_pass') int maxHoldsPerPass,@JsonKey(name: 'max_hold_total_days') int maxHoldTotalDays,@JsonKey(name: 'open_hour', fromJson: _hourOrNull) int? openHour,@JsonKey(name: 'close_hour', fromJson: _hourOrNull) int? closeHour
});




}
/// @nodoc
class _$CenterPolicyDtoCopyWithImpl<$Res>
    implements $CenterPolicyDtoCopyWith<$Res> {
  _$CenterPolicyDtoCopyWithImpl(this._self, this._then);

  final CenterPolicyDto _self;
  final $Res Function(CenterPolicyDto) _then;

/// Create a copy of CenterPolicyDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? slotCapacity = null,Object? cancelCutoffHours = null,Object? graceOnce = null,Object? penaltyRate = null,Object? expiringDays = null,Object? maxHoldsPerPass = null,Object? maxHoldTotalDays = null,Object? openHour = freezed,Object? closeHour = freezed,}) {
  return _then(_self.copyWith(
slotCapacity: null == slotCapacity ? _self.slotCapacity : slotCapacity // ignore: cast_nullable_to_non_nullable
as int,cancelCutoffHours: null == cancelCutoffHours ? _self.cancelCutoffHours : cancelCutoffHours // ignore: cast_nullable_to_non_nullable
as int,graceOnce: null == graceOnce ? _self.graceOnce : graceOnce // ignore: cast_nullable_to_non_nullable
as bool,penaltyRate: null == penaltyRate ? _self.penaltyRate : penaltyRate // ignore: cast_nullable_to_non_nullable
as double,expiringDays: null == expiringDays ? _self.expiringDays : expiringDays // ignore: cast_nullable_to_non_nullable
as int,maxHoldsPerPass: null == maxHoldsPerPass ? _self.maxHoldsPerPass : maxHoldsPerPass // ignore: cast_nullable_to_non_nullable
as int,maxHoldTotalDays: null == maxHoldTotalDays ? _self.maxHoldTotalDays : maxHoldTotalDays // ignore: cast_nullable_to_non_nullable
as int,openHour: freezed == openHour ? _self.openHour : openHour // ignore: cast_nullable_to_non_nullable
as int?,closeHour: freezed == closeHour ? _self.closeHour : closeHour // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [CenterPolicyDto].
extension CenterPolicyDtoPatterns on CenterPolicyDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CenterPolicyDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CenterPolicyDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CenterPolicyDto value)  $default,){
final _that = this;
switch (_that) {
case _CenterPolicyDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CenterPolicyDto value)?  $default,){
final _that = this;
switch (_that) {
case _CenterPolicyDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'slot_capacity')  int slotCapacity, @JsonKey(name: 'cancel_cutoff_hours')  int cancelCutoffHours, @JsonKey(name: 'grace_once')  bool graceOnce, @JsonKey(name: 'penalty_rate')  double penaltyRate, @JsonKey(name: 'expiring_days')  int expiringDays, @JsonKey(name: 'max_holds_per_pass')  int maxHoldsPerPass, @JsonKey(name: 'max_hold_total_days')  int maxHoldTotalDays, @JsonKey(name: 'open_hour', fromJson: _hourOrNull)  int? openHour, @JsonKey(name: 'close_hour', fromJson: _hourOrNull)  int? closeHour)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CenterPolicyDto() when $default != null:
return $default(_that.slotCapacity,_that.cancelCutoffHours,_that.graceOnce,_that.penaltyRate,_that.expiringDays,_that.maxHoldsPerPass,_that.maxHoldTotalDays,_that.openHour,_that.closeHour);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'slot_capacity')  int slotCapacity, @JsonKey(name: 'cancel_cutoff_hours')  int cancelCutoffHours, @JsonKey(name: 'grace_once')  bool graceOnce, @JsonKey(name: 'penalty_rate')  double penaltyRate, @JsonKey(name: 'expiring_days')  int expiringDays, @JsonKey(name: 'max_holds_per_pass')  int maxHoldsPerPass, @JsonKey(name: 'max_hold_total_days')  int maxHoldTotalDays, @JsonKey(name: 'open_hour', fromJson: _hourOrNull)  int? openHour, @JsonKey(name: 'close_hour', fromJson: _hourOrNull)  int? closeHour)  $default,) {final _that = this;
switch (_that) {
case _CenterPolicyDto():
return $default(_that.slotCapacity,_that.cancelCutoffHours,_that.graceOnce,_that.penaltyRate,_that.expiringDays,_that.maxHoldsPerPass,_that.maxHoldTotalDays,_that.openHour,_that.closeHour);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'slot_capacity')  int slotCapacity, @JsonKey(name: 'cancel_cutoff_hours')  int cancelCutoffHours, @JsonKey(name: 'grace_once')  bool graceOnce, @JsonKey(name: 'penalty_rate')  double penaltyRate, @JsonKey(name: 'expiring_days')  int expiringDays, @JsonKey(name: 'max_holds_per_pass')  int maxHoldsPerPass, @JsonKey(name: 'max_hold_total_days')  int maxHoldTotalDays, @JsonKey(name: 'open_hour', fromJson: _hourOrNull)  int? openHour, @JsonKey(name: 'close_hour', fromJson: _hourOrNull)  int? closeHour)?  $default,) {final _that = this;
switch (_that) {
case _CenterPolicyDto() when $default != null:
return $default(_that.slotCapacity,_that.cancelCutoffHours,_that.graceOnce,_that.penaltyRate,_that.expiringDays,_that.maxHoldsPerPass,_that.maxHoldTotalDays,_that.openHour,_that.closeHour);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CenterPolicyDto implements CenterPolicyDto {
  const _CenterPolicyDto({@JsonKey(name: 'slot_capacity') this.slotCapacity = 3, @JsonKey(name: 'cancel_cutoff_hours') this.cancelCutoffHours = 24, @JsonKey(name: 'grace_once') this.graceOnce = true, @JsonKey(name: 'penalty_rate') this.penaltyRate = 0.10, @JsonKey(name: 'expiring_days') this.expiringDays = 7, @JsonKey(name: 'max_holds_per_pass') this.maxHoldsPerPass = 2, @JsonKey(name: 'max_hold_total_days') this.maxHoldTotalDays = 30, @JsonKey(name: 'open_hour', fromJson: _hourOrNull) this.openHour, @JsonKey(name: 'close_hour', fromJson: _hourOrNull) this.closeHour});
  factory _CenterPolicyDto.fromJson(Map<String, dynamic> json) => _$CenterPolicyDtoFromJson(json);

@override@JsonKey(name: 'slot_capacity') final  int slotCapacity;
@override@JsonKey(name: 'cancel_cutoff_hours') final  int cancelCutoffHours;
@override@JsonKey(name: 'grace_once') final  bool graceOnce;
@override@JsonKey(name: 'penalty_rate') final  double penaltyRate;
/// 만료임박 기준일(대표가 설정 화면에서 정한다). 서버는 v1부터 이 값을 내려주는데
/// 앱이 파싱하지 않아, 홈의 "연장 상담 가능" 배지가 **조건 없이 항상** 켜져 있었다.
@override@JsonKey(name: 'expiring_days') final  int expiringDays;
@override@JsonKey(name: 'max_holds_per_pass') final  int maxHoldsPerPass;
@override@JsonKey(name: 'max_hold_total_days') final  int maxHoldTotalDays;
/// 센터 운영시간 — **슬롯 시작 시각, 양끝 포함**(9·21 → 09시 시작 ~ 21시 시작 13칸).
///
/// **이웃 필드와 달리 nullable이고 `@Default`가 없다.** 여기에 `@Default(9)`를
/// 박으면 같은 숫자가 DTO와 `CenterPolicy.fallback` 두 군데에 살면서 따로 움직일
/// 수 있는데, 이 두 자리는 반드시 같아야 한다 — "서버가 필드를 안 준 구버전"과
/// "정책 조회 자체가 실패"는 회원에게 **똑같이 오늘의 09~21시**로 보여야 한다.
/// 그래서 "서버가 안 줬다"를 null 그대로 넘기고, 기본값과 유효성(open ≤ close,
/// 0..23)은 정책을 읽는 경계 한 곳(`CenterPolicy.resolveHours`)이 전담한다.
@override@JsonKey(name: 'open_hour', fromJson: _hourOrNull) final  int? openHour;
@override@JsonKey(name: 'close_hour', fromJson: _hourOrNull) final  int? closeHour;

/// Create a copy of CenterPolicyDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CenterPolicyDtoCopyWith<_CenterPolicyDto> get copyWith => __$CenterPolicyDtoCopyWithImpl<_CenterPolicyDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CenterPolicyDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CenterPolicyDto&&(identical(other.slotCapacity, slotCapacity) || other.slotCapacity == slotCapacity)&&(identical(other.cancelCutoffHours, cancelCutoffHours) || other.cancelCutoffHours == cancelCutoffHours)&&(identical(other.graceOnce, graceOnce) || other.graceOnce == graceOnce)&&(identical(other.penaltyRate, penaltyRate) || other.penaltyRate == penaltyRate)&&(identical(other.expiringDays, expiringDays) || other.expiringDays == expiringDays)&&(identical(other.maxHoldsPerPass, maxHoldsPerPass) || other.maxHoldsPerPass == maxHoldsPerPass)&&(identical(other.maxHoldTotalDays, maxHoldTotalDays) || other.maxHoldTotalDays == maxHoldTotalDays)&&(identical(other.openHour, openHour) || other.openHour == openHour)&&(identical(other.closeHour, closeHour) || other.closeHour == closeHour));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,slotCapacity,cancelCutoffHours,graceOnce,penaltyRate,expiringDays,maxHoldsPerPass,maxHoldTotalDays,openHour,closeHour);

@override
String toString() {
  return 'CenterPolicyDto(slotCapacity: $slotCapacity, cancelCutoffHours: $cancelCutoffHours, graceOnce: $graceOnce, penaltyRate: $penaltyRate, expiringDays: $expiringDays, maxHoldsPerPass: $maxHoldsPerPass, maxHoldTotalDays: $maxHoldTotalDays, openHour: $openHour, closeHour: $closeHour)';
}


}

/// @nodoc
abstract mixin class _$CenterPolicyDtoCopyWith<$Res> implements $CenterPolicyDtoCopyWith<$Res> {
  factory _$CenterPolicyDtoCopyWith(_CenterPolicyDto value, $Res Function(_CenterPolicyDto) _then) = __$CenterPolicyDtoCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'slot_capacity') int slotCapacity,@JsonKey(name: 'cancel_cutoff_hours') int cancelCutoffHours,@JsonKey(name: 'grace_once') bool graceOnce,@JsonKey(name: 'penalty_rate') double penaltyRate,@JsonKey(name: 'expiring_days') int expiringDays,@JsonKey(name: 'max_holds_per_pass') int maxHoldsPerPass,@JsonKey(name: 'max_hold_total_days') int maxHoldTotalDays,@JsonKey(name: 'open_hour', fromJson: _hourOrNull) int? openHour,@JsonKey(name: 'close_hour', fromJson: _hourOrNull) int? closeHour
});




}
/// @nodoc
class __$CenterPolicyDtoCopyWithImpl<$Res>
    implements _$CenterPolicyDtoCopyWith<$Res> {
  __$CenterPolicyDtoCopyWithImpl(this._self, this._then);

  final _CenterPolicyDto _self;
  final $Res Function(_CenterPolicyDto) _then;

/// Create a copy of CenterPolicyDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? slotCapacity = null,Object? cancelCutoffHours = null,Object? graceOnce = null,Object? penaltyRate = null,Object? expiringDays = null,Object? maxHoldsPerPass = null,Object? maxHoldTotalDays = null,Object? openHour = freezed,Object? closeHour = freezed,}) {
  return _then(_CenterPolicyDto(
slotCapacity: null == slotCapacity ? _self.slotCapacity : slotCapacity // ignore: cast_nullable_to_non_nullable
as int,cancelCutoffHours: null == cancelCutoffHours ? _self.cancelCutoffHours : cancelCutoffHours // ignore: cast_nullable_to_non_nullable
as int,graceOnce: null == graceOnce ? _self.graceOnce : graceOnce // ignore: cast_nullable_to_non_nullable
as bool,penaltyRate: null == penaltyRate ? _self.penaltyRate : penaltyRate // ignore: cast_nullable_to_non_nullable
as double,expiringDays: null == expiringDays ? _self.expiringDays : expiringDays // ignore: cast_nullable_to_non_nullable
as int,maxHoldsPerPass: null == maxHoldsPerPass ? _self.maxHoldsPerPass : maxHoldsPerPass // ignore: cast_nullable_to_non_nullable
as int,maxHoldTotalDays: null == maxHoldTotalDays ? _self.maxHoldTotalDays : maxHoldTotalDays // ignore: cast_nullable_to_non_nullable
as int,openHour: freezed == openHour ? _self.openHour : openHour // ignore: cast_nullable_to_non_nullable
as int?,closeHour: freezed == closeHour ? _self.closeHour : closeHour // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
