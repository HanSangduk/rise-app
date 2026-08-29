// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recurring_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RecurringDto {

 String get id;@JsonKey(name: 'member_id') String get memberId;@JsonKey(name: 'trainer_id') String get trainerId;@JsonKey(name: 'pass_id') String get passId; List<String> get days;// ["tue","fri"]
 int get hour; String? get until;
/// Create a copy of RecurringDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecurringDtoCopyWith<RecurringDto> get copyWith => _$RecurringDtoCopyWithImpl<RecurringDto>(this as RecurringDto, _$identity);

  /// Serializes this RecurringDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecurringDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.passId, passId) || other.passId == passId)&&const DeepCollectionEquality().equals(other.days, days)&&(identical(other.hour, hour) || other.hour == hour)&&(identical(other.until, until) || other.until == until));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,trainerId,passId,const DeepCollectionEquality().hash(days),hour,until);

@override
String toString() {
  return 'RecurringDto(id: $id, memberId: $memberId, trainerId: $trainerId, passId: $passId, days: $days, hour: $hour, until: $until)';
}


}

/// @nodoc
abstract mixin class $RecurringDtoCopyWith<$Res>  {
  factory $RecurringDtoCopyWith(RecurringDto value, $Res Function(RecurringDto) _then) = _$RecurringDtoCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'trainer_id') String trainerId,@JsonKey(name: 'pass_id') String passId, List<String> days, int hour, String? until
});




}
/// @nodoc
class _$RecurringDtoCopyWithImpl<$Res>
    implements $RecurringDtoCopyWith<$Res> {
  _$RecurringDtoCopyWithImpl(this._self, this._then);

  final RecurringDto _self;
  final $Res Function(RecurringDto) _then;

/// Create a copy of RecurringDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? memberId = null,Object? trainerId = null,Object? passId = null,Object? days = null,Object? hour = null,Object? until = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,passId: null == passId ? _self.passId : passId // ignore: cast_nullable_to_non_nullable
as String,days: null == days ? _self.days : days // ignore: cast_nullable_to_non_nullable
as List<String>,hour: null == hour ? _self.hour : hour // ignore: cast_nullable_to_non_nullable
as int,until: freezed == until ? _self.until : until // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [RecurringDto].
extension RecurringDtoPatterns on RecurringDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecurringDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecurringDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecurringDto value)  $default,){
final _that = this;
switch (_that) {
case _RecurringDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecurringDto value)?  $default,){
final _that = this;
switch (_that) {
case _RecurringDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'pass_id')  String passId,  List<String> days,  int hour,  String? until)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecurringDto() when $default != null:
return $default(_that.id,_that.memberId,_that.trainerId,_that.passId,_that.days,_that.hour,_that.until);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'pass_id')  String passId,  List<String> days,  int hour,  String? until)  $default,) {final _that = this;
switch (_that) {
case _RecurringDto():
return $default(_that.id,_that.memberId,_that.trainerId,_that.passId,_that.days,_that.hour,_that.until);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'pass_id')  String passId,  List<String> days,  int hour,  String? until)?  $default,) {final _that = this;
switch (_that) {
case _RecurringDto() when $default != null:
return $default(_that.id,_that.memberId,_that.trainerId,_that.passId,_that.days,_that.hour,_that.until);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RecurringDto implements RecurringDto {
  const _RecurringDto({required this.id, @JsonKey(name: 'member_id') required this.memberId, @JsonKey(name: 'trainer_id') required this.trainerId, @JsonKey(name: 'pass_id') required this.passId, final  List<String> days = const <String>[], required this.hour, this.until}): _days = days;
  factory _RecurringDto.fromJson(Map<String, dynamic> json) => _$RecurringDtoFromJson(json);

@override final  String id;
@override@JsonKey(name: 'member_id') final  String memberId;
@override@JsonKey(name: 'trainer_id') final  String trainerId;
@override@JsonKey(name: 'pass_id') final  String passId;
 final  List<String> _days;
@override@JsonKey() List<String> get days {
  if (_days is EqualUnmodifiableListView) return _days;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_days);
}

// ["tue","fri"]
@override final  int hour;
@override final  String? until;

/// Create a copy of RecurringDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecurringDtoCopyWith<_RecurringDto> get copyWith => __$RecurringDtoCopyWithImpl<_RecurringDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RecurringDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecurringDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.passId, passId) || other.passId == passId)&&const DeepCollectionEquality().equals(other._days, _days)&&(identical(other.hour, hour) || other.hour == hour)&&(identical(other.until, until) || other.until == until));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,trainerId,passId,const DeepCollectionEquality().hash(_days),hour,until);

@override
String toString() {
  return 'RecurringDto(id: $id, memberId: $memberId, trainerId: $trainerId, passId: $passId, days: $days, hour: $hour, until: $until)';
}


}

/// @nodoc
abstract mixin class _$RecurringDtoCopyWith<$Res> implements $RecurringDtoCopyWith<$Res> {
  factory _$RecurringDtoCopyWith(_RecurringDto value, $Res Function(_RecurringDto) _then) = __$RecurringDtoCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'trainer_id') String trainerId,@JsonKey(name: 'pass_id') String passId, List<String> days, int hour, String? until
});




}
/// @nodoc
class __$RecurringDtoCopyWithImpl<$Res>
    implements _$RecurringDtoCopyWith<$Res> {
  __$RecurringDtoCopyWithImpl(this._self, this._then);

  final _RecurringDto _self;
  final $Res Function(_RecurringDto) _then;

/// Create a copy of RecurringDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? memberId = null,Object? trainerId = null,Object? passId = null,Object? days = null,Object? hour = null,Object? until = freezed,}) {
  return _then(_RecurringDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,passId: null == passId ? _self.passId : passId // ignore: cast_nullable_to_non_nullable
as String,days: null == days ? _self._days : days // ignore: cast_nullable_to_non_nullable
as List<String>,hour: null == hour ? _self.hour : hour // ignore: cast_nullable_to_non_nullable
as int,until: freezed == until ? _self.until : until // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
