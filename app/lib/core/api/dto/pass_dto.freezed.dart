// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'pass_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PassDto {

 String get id;@JsonKey(name: 'member_id') String get memberId;@JsonKey(name: 'trainer_id') String get trainerId; String get product;@JsonKey(name: 'paid_amount') int get paidAmount;@JsonKey(name: 'total_sessions') int get totalSessions; int get remaining;@JsonKey(name: 'valid_from') String get validFrom;@JsonKey(name: 'valid_until') String get validUntil; String get status;// active|scheduled|expired|refunded
 List<PassHoldDto> get holds;
/// Create a copy of PassDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PassDtoCopyWith<PassDto> get copyWith => _$PassDtoCopyWithImpl<PassDto>(this as PassDto, _$identity);

  /// Serializes this PassDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PassDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.product, product) || other.product == product)&&(identical(other.paidAmount, paidAmount) || other.paidAmount == paidAmount)&&(identical(other.totalSessions, totalSessions) || other.totalSessions == totalSessions)&&(identical(other.remaining, remaining) || other.remaining == remaining)&&(identical(other.validFrom, validFrom) || other.validFrom == validFrom)&&(identical(other.validUntil, validUntil) || other.validUntil == validUntil)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.holds, holds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,trainerId,product,paidAmount,totalSessions,remaining,validFrom,validUntil,status,const DeepCollectionEquality().hash(holds));

@override
String toString() {
  return 'PassDto(id: $id, memberId: $memberId, trainerId: $trainerId, product: $product, paidAmount: $paidAmount, totalSessions: $totalSessions, remaining: $remaining, validFrom: $validFrom, validUntil: $validUntil, status: $status, holds: $holds)';
}


}

/// @nodoc
abstract mixin class $PassDtoCopyWith<$Res>  {
  factory $PassDtoCopyWith(PassDto value, $Res Function(PassDto) _then) = _$PassDtoCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'trainer_id') String trainerId, String product,@JsonKey(name: 'paid_amount') int paidAmount,@JsonKey(name: 'total_sessions') int totalSessions, int remaining,@JsonKey(name: 'valid_from') String validFrom,@JsonKey(name: 'valid_until') String validUntil, String status, List<PassHoldDto> holds
});




}
/// @nodoc
class _$PassDtoCopyWithImpl<$Res>
    implements $PassDtoCopyWith<$Res> {
  _$PassDtoCopyWithImpl(this._self, this._then);

  final PassDto _self;
  final $Res Function(PassDto) _then;

/// Create a copy of PassDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? memberId = null,Object? trainerId = null,Object? product = null,Object? paidAmount = null,Object? totalSessions = null,Object? remaining = null,Object? validFrom = null,Object? validUntil = null,Object? status = null,Object? holds = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,product: null == product ? _self.product : product // ignore: cast_nullable_to_non_nullable
as String,paidAmount: null == paidAmount ? _self.paidAmount : paidAmount // ignore: cast_nullable_to_non_nullable
as int,totalSessions: null == totalSessions ? _self.totalSessions : totalSessions // ignore: cast_nullable_to_non_nullable
as int,remaining: null == remaining ? _self.remaining : remaining // ignore: cast_nullable_to_non_nullable
as int,validFrom: null == validFrom ? _self.validFrom : validFrom // ignore: cast_nullable_to_non_nullable
as String,validUntil: null == validUntil ? _self.validUntil : validUntil // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,holds: null == holds ? _self.holds : holds // ignore: cast_nullable_to_non_nullable
as List<PassHoldDto>,
  ));
}

}


/// Adds pattern-matching-related methods to [PassDto].
extension PassDtoPatterns on PassDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PassDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PassDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PassDto value)  $default,){
final _that = this;
switch (_that) {
case _PassDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PassDto value)?  $default,){
final _that = this;
switch (_that) {
case _PassDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId,  String product, @JsonKey(name: 'paid_amount')  int paidAmount, @JsonKey(name: 'total_sessions')  int totalSessions,  int remaining, @JsonKey(name: 'valid_from')  String validFrom, @JsonKey(name: 'valid_until')  String validUntil,  String status,  List<PassHoldDto> holds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PassDto() when $default != null:
return $default(_that.id,_that.memberId,_that.trainerId,_that.product,_that.paidAmount,_that.totalSessions,_that.remaining,_that.validFrom,_that.validUntil,_that.status,_that.holds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId,  String product, @JsonKey(name: 'paid_amount')  int paidAmount, @JsonKey(name: 'total_sessions')  int totalSessions,  int remaining, @JsonKey(name: 'valid_from')  String validFrom, @JsonKey(name: 'valid_until')  String validUntil,  String status,  List<PassHoldDto> holds)  $default,) {final _that = this;
switch (_that) {
case _PassDto():
return $default(_that.id,_that.memberId,_that.trainerId,_that.product,_that.paidAmount,_that.totalSessions,_that.remaining,_that.validFrom,_that.validUntil,_that.status,_that.holds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId,  String product, @JsonKey(name: 'paid_amount')  int paidAmount, @JsonKey(name: 'total_sessions')  int totalSessions,  int remaining, @JsonKey(name: 'valid_from')  String validFrom, @JsonKey(name: 'valid_until')  String validUntil,  String status,  List<PassHoldDto> holds)?  $default,) {final _that = this;
switch (_that) {
case _PassDto() when $default != null:
return $default(_that.id,_that.memberId,_that.trainerId,_that.product,_that.paidAmount,_that.totalSessions,_that.remaining,_that.validFrom,_that.validUntil,_that.status,_that.holds);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PassDto implements PassDto {
  const _PassDto({required this.id, @JsonKey(name: 'member_id') required this.memberId, @JsonKey(name: 'trainer_id') required this.trainerId, required this.product, @JsonKey(name: 'paid_amount') required this.paidAmount, @JsonKey(name: 'total_sessions') required this.totalSessions, required this.remaining, @JsonKey(name: 'valid_from') required this.validFrom, @JsonKey(name: 'valid_until') required this.validUntil, this.status = 'active', final  List<PassHoldDto> holds = const <PassHoldDto>[]}): _holds = holds;
  factory _PassDto.fromJson(Map<String, dynamic> json) => _$PassDtoFromJson(json);

@override final  String id;
@override@JsonKey(name: 'member_id') final  String memberId;
@override@JsonKey(name: 'trainer_id') final  String trainerId;
@override final  String product;
@override@JsonKey(name: 'paid_amount') final  int paidAmount;
@override@JsonKey(name: 'total_sessions') final  int totalSessions;
@override final  int remaining;
@override@JsonKey(name: 'valid_from') final  String validFrom;
@override@JsonKey(name: 'valid_until') final  String validUntil;
@override@JsonKey() final  String status;
// active|scheduled|expired|refunded
 final  List<PassHoldDto> _holds;
// active|scheduled|expired|refunded
@override@JsonKey() List<PassHoldDto> get holds {
  if (_holds is EqualUnmodifiableListView) return _holds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_holds);
}


/// Create a copy of PassDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PassDtoCopyWith<_PassDto> get copyWith => __$PassDtoCopyWithImpl<_PassDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PassDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PassDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.product, product) || other.product == product)&&(identical(other.paidAmount, paidAmount) || other.paidAmount == paidAmount)&&(identical(other.totalSessions, totalSessions) || other.totalSessions == totalSessions)&&(identical(other.remaining, remaining) || other.remaining == remaining)&&(identical(other.validFrom, validFrom) || other.validFrom == validFrom)&&(identical(other.validUntil, validUntil) || other.validUntil == validUntil)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other._holds, _holds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,trainerId,product,paidAmount,totalSessions,remaining,validFrom,validUntil,status,const DeepCollectionEquality().hash(_holds));

@override
String toString() {
  return 'PassDto(id: $id, memberId: $memberId, trainerId: $trainerId, product: $product, paidAmount: $paidAmount, totalSessions: $totalSessions, remaining: $remaining, validFrom: $validFrom, validUntil: $validUntil, status: $status, holds: $holds)';
}


}

/// @nodoc
abstract mixin class _$PassDtoCopyWith<$Res> implements $PassDtoCopyWith<$Res> {
  factory _$PassDtoCopyWith(_PassDto value, $Res Function(_PassDto) _then) = __$PassDtoCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'trainer_id') String trainerId, String product,@JsonKey(name: 'paid_amount') int paidAmount,@JsonKey(name: 'total_sessions') int totalSessions, int remaining,@JsonKey(name: 'valid_from') String validFrom,@JsonKey(name: 'valid_until') String validUntil, String status, List<PassHoldDto> holds
});




}
/// @nodoc
class __$PassDtoCopyWithImpl<$Res>
    implements _$PassDtoCopyWith<$Res> {
  __$PassDtoCopyWithImpl(this._self, this._then);

  final _PassDto _self;
  final $Res Function(_PassDto) _then;

/// Create a copy of PassDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? memberId = null,Object? trainerId = null,Object? product = null,Object? paidAmount = null,Object? totalSessions = null,Object? remaining = null,Object? validFrom = null,Object? validUntil = null,Object? status = null,Object? holds = null,}) {
  return _then(_PassDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,product: null == product ? _self.product : product // ignore: cast_nullable_to_non_nullable
as String,paidAmount: null == paidAmount ? _self.paidAmount : paidAmount // ignore: cast_nullable_to_non_nullable
as int,totalSessions: null == totalSessions ? _self.totalSessions : totalSessions // ignore: cast_nullable_to_non_nullable
as int,remaining: null == remaining ? _self.remaining : remaining // ignore: cast_nullable_to_non_nullable
as int,validFrom: null == validFrom ? _self.validFrom : validFrom // ignore: cast_nullable_to_non_nullable
as String,validUntil: null == validUntil ? _self.validUntil : validUntil // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,holds: null == holds ? _self._holds : holds // ignore: cast_nullable_to_non_nullable
as List<PassHoldDto>,
  ));
}


}


/// @nodoc
mixin _$PassHoldDto {

 String get from; String get to; String? get reason;
/// Create a copy of PassHoldDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PassHoldDtoCopyWith<PassHoldDto> get copyWith => _$PassHoldDtoCopyWithImpl<PassHoldDto>(this as PassHoldDto, _$identity);

  /// Serializes this PassHoldDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PassHoldDto&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to)&&(identical(other.reason, reason) || other.reason == reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,from,to,reason);

@override
String toString() {
  return 'PassHoldDto(from: $from, to: $to, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $PassHoldDtoCopyWith<$Res>  {
  factory $PassHoldDtoCopyWith(PassHoldDto value, $Res Function(PassHoldDto) _then) = _$PassHoldDtoCopyWithImpl;
@useResult
$Res call({
 String from, String to, String? reason
});




}
/// @nodoc
class _$PassHoldDtoCopyWithImpl<$Res>
    implements $PassHoldDtoCopyWith<$Res> {
  _$PassHoldDtoCopyWithImpl(this._self, this._then);

  final PassHoldDto _self;
  final $Res Function(PassHoldDto) _then;

/// Create a copy of PassHoldDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? from = null,Object? to = null,Object? reason = freezed,}) {
  return _then(_self.copyWith(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PassHoldDto].
extension PassHoldDtoPatterns on PassHoldDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PassHoldDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PassHoldDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PassHoldDto value)  $default,){
final _that = this;
switch (_that) {
case _PassHoldDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PassHoldDto value)?  $default,){
final _that = this;
switch (_that) {
case _PassHoldDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String from,  String to,  String? reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PassHoldDto() when $default != null:
return $default(_that.from,_that.to,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String from,  String to,  String? reason)  $default,) {final _that = this;
switch (_that) {
case _PassHoldDto():
return $default(_that.from,_that.to,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String from,  String to,  String? reason)?  $default,) {final _that = this;
switch (_that) {
case _PassHoldDto() when $default != null:
return $default(_that.from,_that.to,_that.reason);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PassHoldDto implements PassHoldDto {
  const _PassHoldDto({required this.from, required this.to, this.reason});
  factory _PassHoldDto.fromJson(Map<String, dynamic> json) => _$PassHoldDtoFromJson(json);

@override final  String from;
@override final  String to;
@override final  String? reason;

/// Create a copy of PassHoldDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PassHoldDtoCopyWith<_PassHoldDto> get copyWith => __$PassHoldDtoCopyWithImpl<_PassHoldDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PassHoldDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PassHoldDto&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to)&&(identical(other.reason, reason) || other.reason == reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,from,to,reason);

@override
String toString() {
  return 'PassHoldDto(from: $from, to: $to, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$PassHoldDtoCopyWith<$Res> implements $PassHoldDtoCopyWith<$Res> {
  factory _$PassHoldDtoCopyWith(_PassHoldDto value, $Res Function(_PassHoldDto) _then) = __$PassHoldDtoCopyWithImpl;
@override @useResult
$Res call({
 String from, String to, String? reason
});




}
/// @nodoc
class __$PassHoldDtoCopyWithImpl<$Res>
    implements _$PassHoldDtoCopyWith<$Res> {
  __$PassHoldDtoCopyWithImpl(this._self, this._then);

  final _PassHoldDto _self;
  final $Res Function(_PassHoldDto) _then;

/// Create a copy of PassHoldDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? from = null,Object? to = null,Object? reason = freezed,}) {
  return _then(_PassHoldDto(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
