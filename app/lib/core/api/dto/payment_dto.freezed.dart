// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'payment_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PaymentDto {

 String get id;@JsonKey(name: 'member_id') String get memberId;@JsonKey(name: 'pass_id') String get passId; String get method;// card|cash|transfer
 int get total; List<InstallmentDto> get installments; String get channel;
/// Create a copy of PaymentDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PaymentDtoCopyWith<PaymentDto> get copyWith => _$PaymentDtoCopyWithImpl<PaymentDto>(this as PaymentDto, _$identity);

  /// Serializes this PaymentDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PaymentDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.passId, passId) || other.passId == passId)&&(identical(other.method, method) || other.method == method)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.installments, installments)&&(identical(other.channel, channel) || other.channel == channel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,passId,method,total,const DeepCollectionEquality().hash(installments),channel);

@override
String toString() {
  return 'PaymentDto(id: $id, memberId: $memberId, passId: $passId, method: $method, total: $total, installments: $installments, channel: $channel)';
}


}

/// @nodoc
abstract mixin class $PaymentDtoCopyWith<$Res>  {
  factory $PaymentDtoCopyWith(PaymentDto value, $Res Function(PaymentDto) _then) = _$PaymentDtoCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'pass_id') String passId, String method, int total, List<InstallmentDto> installments, String channel
});




}
/// @nodoc
class _$PaymentDtoCopyWithImpl<$Res>
    implements $PaymentDtoCopyWith<$Res> {
  _$PaymentDtoCopyWithImpl(this._self, this._then);

  final PaymentDto _self;
  final $Res Function(PaymentDto) _then;

/// Create a copy of PaymentDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? memberId = null,Object? passId = null,Object? method = null,Object? total = null,Object? installments = null,Object? channel = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,passId: null == passId ? _self.passId : passId // ignore: cast_nullable_to_non_nullable
as String,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,installments: null == installments ? _self.installments : installments // ignore: cast_nullable_to_non_nullable
as List<InstallmentDto>,channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PaymentDto].
extension PaymentDtoPatterns on PaymentDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PaymentDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PaymentDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PaymentDto value)  $default,){
final _that = this;
switch (_that) {
case _PaymentDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PaymentDto value)?  $default,){
final _that = this;
switch (_that) {
case _PaymentDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'pass_id')  String passId,  String method,  int total,  List<InstallmentDto> installments,  String channel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PaymentDto() when $default != null:
return $default(_that.id,_that.memberId,_that.passId,_that.method,_that.total,_that.installments,_that.channel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'pass_id')  String passId,  String method,  int total,  List<InstallmentDto> installments,  String channel)  $default,) {final _that = this;
switch (_that) {
case _PaymentDto():
return $default(_that.id,_that.memberId,_that.passId,_that.method,_that.total,_that.installments,_that.channel);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'pass_id')  String passId,  String method,  int total,  List<InstallmentDto> installments,  String channel)?  $default,) {final _that = this;
switch (_that) {
case _PaymentDto() when $default != null:
return $default(_that.id,_that.memberId,_that.passId,_that.method,_that.total,_that.installments,_that.channel);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PaymentDto implements PaymentDto {
  const _PaymentDto({required this.id, @JsonKey(name: 'member_id') required this.memberId, @JsonKey(name: 'pass_id') required this.passId, this.method = 'card', this.total = 0, final  List<InstallmentDto> installments = const <InstallmentDto>[], this.channel = ''}): _installments = installments;
  factory _PaymentDto.fromJson(Map<String, dynamic> json) => _$PaymentDtoFromJson(json);

@override final  String id;
@override@JsonKey(name: 'member_id') final  String memberId;
@override@JsonKey(name: 'pass_id') final  String passId;
@override@JsonKey() final  String method;
// card|cash|transfer
@override@JsonKey() final  int total;
 final  List<InstallmentDto> _installments;
@override@JsonKey() List<InstallmentDto> get installments {
  if (_installments is EqualUnmodifiableListView) return _installments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_installments);
}

@override@JsonKey() final  String channel;

/// Create a copy of PaymentDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PaymentDtoCopyWith<_PaymentDto> get copyWith => __$PaymentDtoCopyWithImpl<_PaymentDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PaymentDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PaymentDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.passId, passId) || other.passId == passId)&&(identical(other.method, method) || other.method == method)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other._installments, _installments)&&(identical(other.channel, channel) || other.channel == channel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,passId,method,total,const DeepCollectionEquality().hash(_installments),channel);

@override
String toString() {
  return 'PaymentDto(id: $id, memberId: $memberId, passId: $passId, method: $method, total: $total, installments: $installments, channel: $channel)';
}


}

/// @nodoc
abstract mixin class _$PaymentDtoCopyWith<$Res> implements $PaymentDtoCopyWith<$Res> {
  factory _$PaymentDtoCopyWith(_PaymentDto value, $Res Function(_PaymentDto) _then) = __$PaymentDtoCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'pass_id') String passId, String method, int total, List<InstallmentDto> installments, String channel
});




}
/// @nodoc
class __$PaymentDtoCopyWithImpl<$Res>
    implements _$PaymentDtoCopyWith<$Res> {
  __$PaymentDtoCopyWithImpl(this._self, this._then);

  final _PaymentDto _self;
  final $Res Function(_PaymentDto) _then;

/// Create a copy of PaymentDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? memberId = null,Object? passId = null,Object? method = null,Object? total = null,Object? installments = null,Object? channel = null,}) {
  return _then(_PaymentDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,passId: null == passId ? _self.passId : passId // ignore: cast_nullable_to_non_nullable
as String,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,installments: null == installments ? _self._installments : installments // ignore: cast_nullable_to_non_nullable
as List<InstallmentDto>,channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$InstallmentDto {

 String get due;// "YYYY-MM-DD"
 int get amount;@JsonKey(name: 'paid_at') String? get paidAt;@JsonKey(name: 'waived_at') String? get waivedAt;
/// Create a copy of InstallmentDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallmentDtoCopyWith<InstallmentDto> get copyWith => _$InstallmentDtoCopyWithImpl<InstallmentDto>(this as InstallmentDto, _$identity);

  /// Serializes this InstallmentDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallmentDto&&(identical(other.due, due) || other.due == due)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.paidAt, paidAt) || other.paidAt == paidAt)&&(identical(other.waivedAt, waivedAt) || other.waivedAt == waivedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,due,amount,paidAt,waivedAt);

@override
String toString() {
  return 'InstallmentDto(due: $due, amount: $amount, paidAt: $paidAt, waivedAt: $waivedAt)';
}


}

/// @nodoc
abstract mixin class $InstallmentDtoCopyWith<$Res>  {
  factory $InstallmentDtoCopyWith(InstallmentDto value, $Res Function(InstallmentDto) _then) = _$InstallmentDtoCopyWithImpl;
@useResult
$Res call({
 String due, int amount,@JsonKey(name: 'paid_at') String? paidAt,@JsonKey(name: 'waived_at') String? waivedAt
});




}
/// @nodoc
class _$InstallmentDtoCopyWithImpl<$Res>
    implements $InstallmentDtoCopyWith<$Res> {
  _$InstallmentDtoCopyWithImpl(this._self, this._then);

  final InstallmentDto _self;
  final $Res Function(InstallmentDto) _then;

/// Create a copy of InstallmentDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? due = null,Object? amount = null,Object? paidAt = freezed,Object? waivedAt = freezed,}) {
  return _then(_self.copyWith(
due: null == due ? _self.due : due // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as int,paidAt: freezed == paidAt ? _self.paidAt : paidAt // ignore: cast_nullable_to_non_nullable
as String?,waivedAt: freezed == waivedAt ? _self.waivedAt : waivedAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [InstallmentDto].
extension InstallmentDtoPatterns on InstallmentDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InstallmentDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InstallmentDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InstallmentDto value)  $default,){
final _that = this;
switch (_that) {
case _InstallmentDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InstallmentDto value)?  $default,){
final _that = this;
switch (_that) {
case _InstallmentDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String due,  int amount, @JsonKey(name: 'paid_at')  String? paidAt, @JsonKey(name: 'waived_at')  String? waivedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InstallmentDto() when $default != null:
return $default(_that.due,_that.amount,_that.paidAt,_that.waivedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String due,  int amount, @JsonKey(name: 'paid_at')  String? paidAt, @JsonKey(name: 'waived_at')  String? waivedAt)  $default,) {final _that = this;
switch (_that) {
case _InstallmentDto():
return $default(_that.due,_that.amount,_that.paidAt,_that.waivedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String due,  int amount, @JsonKey(name: 'paid_at')  String? paidAt, @JsonKey(name: 'waived_at')  String? waivedAt)?  $default,) {final _that = this;
switch (_that) {
case _InstallmentDto() when $default != null:
return $default(_that.due,_that.amount,_that.paidAt,_that.waivedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _InstallmentDto implements InstallmentDto {
  const _InstallmentDto({this.due = '', this.amount = 0, @JsonKey(name: 'paid_at') this.paidAt, @JsonKey(name: 'waived_at') this.waivedAt});
  factory _InstallmentDto.fromJson(Map<String, dynamic> json) => _$InstallmentDtoFromJson(json);

@override@JsonKey() final  String due;
// "YYYY-MM-DD"
@override@JsonKey() final  int amount;
@override@JsonKey(name: 'paid_at') final  String? paidAt;
@override@JsonKey(name: 'waived_at') final  String? waivedAt;

/// Create a copy of InstallmentDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InstallmentDtoCopyWith<_InstallmentDto> get copyWith => __$InstallmentDtoCopyWithImpl<_InstallmentDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$InstallmentDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InstallmentDto&&(identical(other.due, due) || other.due == due)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.paidAt, paidAt) || other.paidAt == paidAt)&&(identical(other.waivedAt, waivedAt) || other.waivedAt == waivedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,due,amount,paidAt,waivedAt);

@override
String toString() {
  return 'InstallmentDto(due: $due, amount: $amount, paidAt: $paidAt, waivedAt: $waivedAt)';
}


}

/// @nodoc
abstract mixin class _$InstallmentDtoCopyWith<$Res> implements $InstallmentDtoCopyWith<$Res> {
  factory _$InstallmentDtoCopyWith(_InstallmentDto value, $Res Function(_InstallmentDto) _then) = __$InstallmentDtoCopyWithImpl;
@override @useResult
$Res call({
 String due, int amount,@JsonKey(name: 'paid_at') String? paidAt,@JsonKey(name: 'waived_at') String? waivedAt
});




}
/// @nodoc
class __$InstallmentDtoCopyWithImpl<$Res>
    implements _$InstallmentDtoCopyWith<$Res> {
  __$InstallmentDtoCopyWithImpl(this._self, this._then);

  final _InstallmentDto _self;
  final $Res Function(_InstallmentDto) _then;

/// Create a copy of InstallmentDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? due = null,Object? amount = null,Object? paidAt = freezed,Object? waivedAt = freezed,}) {
  return _then(_InstallmentDto(
due: null == due ? _self.due : due // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as int,paidAt: freezed == paidAt ? _self.paidAt : paidAt // ignore: cast_nullable_to_non_nullable
as String?,waivedAt: freezed == waivedAt ? _self.waivedAt : waivedAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
