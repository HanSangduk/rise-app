// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'slot_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SlotDto {

@JsonKey(name: 'slot_key') String get slotKey; int get capacity; List<SlotTeamDto> get teams;
/// Create a copy of SlotDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SlotDtoCopyWith<SlotDto> get copyWith => _$SlotDtoCopyWithImpl<SlotDto>(this as SlotDto, _$identity);

  /// Serializes this SlotDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SlotDto&&(identical(other.slotKey, slotKey) || other.slotKey == slotKey)&&(identical(other.capacity, capacity) || other.capacity == capacity)&&const DeepCollectionEquality().equals(other.teams, teams));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,slotKey,capacity,const DeepCollectionEquality().hash(teams));

@override
String toString() {
  return 'SlotDto(slotKey: $slotKey, capacity: $capacity, teams: $teams)';
}


}

/// @nodoc
abstract mixin class $SlotDtoCopyWith<$Res>  {
  factory $SlotDtoCopyWith(SlotDto value, $Res Function(SlotDto) _then) = _$SlotDtoCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'slot_key') String slotKey, int capacity, List<SlotTeamDto> teams
});




}
/// @nodoc
class _$SlotDtoCopyWithImpl<$Res>
    implements $SlotDtoCopyWith<$Res> {
  _$SlotDtoCopyWithImpl(this._self, this._then);

  final SlotDto _self;
  final $Res Function(SlotDto) _then;

/// Create a copy of SlotDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? slotKey = null,Object? capacity = null,Object? teams = null,}) {
  return _then(_self.copyWith(
slotKey: null == slotKey ? _self.slotKey : slotKey // ignore: cast_nullable_to_non_nullable
as String,capacity: null == capacity ? _self.capacity : capacity // ignore: cast_nullable_to_non_nullable
as int,teams: null == teams ? _self.teams : teams // ignore: cast_nullable_to_non_nullable
as List<SlotTeamDto>,
  ));
}

}


/// Adds pattern-matching-related methods to [SlotDto].
extension SlotDtoPatterns on SlotDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SlotDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SlotDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SlotDto value)  $default,){
final _that = this;
switch (_that) {
case _SlotDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SlotDto value)?  $default,){
final _that = this;
switch (_that) {
case _SlotDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'slot_key')  String slotKey,  int capacity,  List<SlotTeamDto> teams)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SlotDto() when $default != null:
return $default(_that.slotKey,_that.capacity,_that.teams);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'slot_key')  String slotKey,  int capacity,  List<SlotTeamDto> teams)  $default,) {final _that = this;
switch (_that) {
case _SlotDto():
return $default(_that.slotKey,_that.capacity,_that.teams);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'slot_key')  String slotKey,  int capacity,  List<SlotTeamDto> teams)?  $default,) {final _that = this;
switch (_that) {
case _SlotDto() when $default != null:
return $default(_that.slotKey,_that.capacity,_that.teams);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SlotDto implements SlotDto {
  const _SlotDto({@JsonKey(name: 'slot_key') required this.slotKey, this.capacity = 3, final  List<SlotTeamDto> teams = const <SlotTeamDto>[]}): _teams = teams;
  factory _SlotDto.fromJson(Map<String, dynamic> json) => _$SlotDtoFromJson(json);

@override@JsonKey(name: 'slot_key') final  String slotKey;
@override@JsonKey() final  int capacity;
 final  List<SlotTeamDto> _teams;
@override@JsonKey() List<SlotTeamDto> get teams {
  if (_teams is EqualUnmodifiableListView) return _teams;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_teams);
}


/// Create a copy of SlotDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SlotDtoCopyWith<_SlotDto> get copyWith => __$SlotDtoCopyWithImpl<_SlotDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SlotDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SlotDto&&(identical(other.slotKey, slotKey) || other.slotKey == slotKey)&&(identical(other.capacity, capacity) || other.capacity == capacity)&&const DeepCollectionEquality().equals(other._teams, _teams));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,slotKey,capacity,const DeepCollectionEquality().hash(_teams));

@override
String toString() {
  return 'SlotDto(slotKey: $slotKey, capacity: $capacity, teams: $teams)';
}


}

/// @nodoc
abstract mixin class _$SlotDtoCopyWith<$Res> implements $SlotDtoCopyWith<$Res> {
  factory _$SlotDtoCopyWith(_SlotDto value, $Res Function(_SlotDto) _then) = __$SlotDtoCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'slot_key') String slotKey, int capacity, List<SlotTeamDto> teams
});




}
/// @nodoc
class __$SlotDtoCopyWithImpl<$Res>
    implements _$SlotDtoCopyWith<$Res> {
  __$SlotDtoCopyWithImpl(this._self, this._then);

  final _SlotDto _self;
  final $Res Function(_SlotDto) _then;

/// Create a copy of SlotDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? slotKey = null,Object? capacity = null,Object? teams = null,}) {
  return _then(_SlotDto(
slotKey: null == slotKey ? _self.slotKey : slotKey // ignore: cast_nullable_to_non_nullable
as String,capacity: null == capacity ? _self.capacity : capacity // ignore: cast_nullable_to_non_nullable
as int,teams: null == teams ? _self._teams : teams // ignore: cast_nullable_to_non_nullable
as List<SlotTeamDto>,
  ));
}


}


/// @nodoc
mixin _$SlotTeamDto {

@JsonKey(name: 'booking_id') String get bookingId;@JsonKey(name: 'trainer_id') String get trainerId;@JsonKey(name: 'member_id') String get memberId; String get kind;
/// Create a copy of SlotTeamDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SlotTeamDtoCopyWith<SlotTeamDto> get copyWith => _$SlotTeamDtoCopyWithImpl<SlotTeamDto>(this as SlotTeamDto, _$identity);

  /// Serializes this SlotTeamDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SlotTeamDto&&(identical(other.bookingId, bookingId) || other.bookingId == bookingId)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.kind, kind) || other.kind == kind));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,bookingId,trainerId,memberId,kind);

@override
String toString() {
  return 'SlotTeamDto(bookingId: $bookingId, trainerId: $trainerId, memberId: $memberId, kind: $kind)';
}


}

/// @nodoc
abstract mixin class $SlotTeamDtoCopyWith<$Res>  {
  factory $SlotTeamDtoCopyWith(SlotTeamDto value, $Res Function(SlotTeamDto) _then) = _$SlotTeamDtoCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'booking_id') String bookingId,@JsonKey(name: 'trainer_id') String trainerId,@JsonKey(name: 'member_id') String memberId, String kind
});




}
/// @nodoc
class _$SlotTeamDtoCopyWithImpl<$Res>
    implements $SlotTeamDtoCopyWith<$Res> {
  _$SlotTeamDtoCopyWithImpl(this._self, this._then);

  final SlotTeamDto _self;
  final $Res Function(SlotTeamDto) _then;

/// Create a copy of SlotTeamDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? bookingId = null,Object? trainerId = null,Object? memberId = null,Object? kind = null,}) {
  return _then(_self.copyWith(
bookingId: null == bookingId ? _self.bookingId : bookingId // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SlotTeamDto].
extension SlotTeamDtoPatterns on SlotTeamDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SlotTeamDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SlotTeamDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SlotTeamDto value)  $default,){
final _that = this;
switch (_that) {
case _SlotTeamDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SlotTeamDto value)?  $default,){
final _that = this;
switch (_that) {
case _SlotTeamDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'booking_id')  String bookingId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'member_id')  String memberId,  String kind)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SlotTeamDto() when $default != null:
return $default(_that.bookingId,_that.trainerId,_that.memberId,_that.kind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'booking_id')  String bookingId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'member_id')  String memberId,  String kind)  $default,) {final _that = this;
switch (_that) {
case _SlotTeamDto():
return $default(_that.bookingId,_that.trainerId,_that.memberId,_that.kind);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'booking_id')  String bookingId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'member_id')  String memberId,  String kind)?  $default,) {final _that = this;
switch (_that) {
case _SlotTeamDto() when $default != null:
return $default(_that.bookingId,_that.trainerId,_that.memberId,_that.kind);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SlotTeamDto implements SlotTeamDto {
  const _SlotTeamDto({@JsonKey(name: 'booking_id') required this.bookingId, @JsonKey(name: 'trainer_id') required this.trainerId, @JsonKey(name: 'member_id') required this.memberId, required this.kind});
  factory _SlotTeamDto.fromJson(Map<String, dynamic> json) => _$SlotTeamDtoFromJson(json);

@override@JsonKey(name: 'booking_id') final  String bookingId;
@override@JsonKey(name: 'trainer_id') final  String trainerId;
@override@JsonKey(name: 'member_id') final  String memberId;
@override final  String kind;

/// Create a copy of SlotTeamDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SlotTeamDtoCopyWith<_SlotTeamDto> get copyWith => __$SlotTeamDtoCopyWithImpl<_SlotTeamDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SlotTeamDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SlotTeamDto&&(identical(other.bookingId, bookingId) || other.bookingId == bookingId)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.kind, kind) || other.kind == kind));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,bookingId,trainerId,memberId,kind);

@override
String toString() {
  return 'SlotTeamDto(bookingId: $bookingId, trainerId: $trainerId, memberId: $memberId, kind: $kind)';
}


}

/// @nodoc
abstract mixin class _$SlotTeamDtoCopyWith<$Res> implements $SlotTeamDtoCopyWith<$Res> {
  factory _$SlotTeamDtoCopyWith(_SlotTeamDto value, $Res Function(_SlotTeamDto) _then) = __$SlotTeamDtoCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'booking_id') String bookingId,@JsonKey(name: 'trainer_id') String trainerId,@JsonKey(name: 'member_id') String memberId, String kind
});




}
/// @nodoc
class __$SlotTeamDtoCopyWithImpl<$Res>
    implements _$SlotTeamDtoCopyWith<$Res> {
  __$SlotTeamDtoCopyWithImpl(this._self, this._then);

  final _SlotTeamDto _self;
  final $Res Function(_SlotTeamDto) _then;

/// Create a copy of SlotTeamDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? bookingId = null,Object? trainerId = null,Object? memberId = null,Object? kind = null,}) {
  return _then(_SlotTeamDto(
bookingId: null == bookingId ? _self.bookingId : bookingId // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
