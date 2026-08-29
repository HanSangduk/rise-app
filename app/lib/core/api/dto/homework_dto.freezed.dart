// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'homework_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$HomeworkDto {

 String get id;@JsonKey(name: 'trainer_id') String get trainerId; String get scope;// individual|my_members|center_notice
@JsonKey(name: 'target_member_ids') List<String> get targetMemberIds; List<String> get excluded; List<HomeworkItemDto> get items; HomeworkScheduleDto? get schedule;
/// Create a copy of HomeworkDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HomeworkDtoCopyWith<HomeworkDto> get copyWith => _$HomeworkDtoCopyWithImpl<HomeworkDto>(this as HomeworkDto, _$identity);

  /// Serializes this HomeworkDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HomeworkDto&&(identical(other.id, id) || other.id == id)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.scope, scope) || other.scope == scope)&&const DeepCollectionEquality().equals(other.targetMemberIds, targetMemberIds)&&const DeepCollectionEquality().equals(other.excluded, excluded)&&const DeepCollectionEquality().equals(other.items, items)&&(identical(other.schedule, schedule) || other.schedule == schedule));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,trainerId,scope,const DeepCollectionEquality().hash(targetMemberIds),const DeepCollectionEquality().hash(excluded),const DeepCollectionEquality().hash(items),schedule);

@override
String toString() {
  return 'HomeworkDto(id: $id, trainerId: $trainerId, scope: $scope, targetMemberIds: $targetMemberIds, excluded: $excluded, items: $items, schedule: $schedule)';
}


}

/// @nodoc
abstract mixin class $HomeworkDtoCopyWith<$Res>  {
  factory $HomeworkDtoCopyWith(HomeworkDto value, $Res Function(HomeworkDto) _then) = _$HomeworkDtoCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'trainer_id') String trainerId, String scope,@JsonKey(name: 'target_member_ids') List<String> targetMemberIds, List<String> excluded, List<HomeworkItemDto> items, HomeworkScheduleDto? schedule
});


$HomeworkScheduleDtoCopyWith<$Res>? get schedule;

}
/// @nodoc
class _$HomeworkDtoCopyWithImpl<$Res>
    implements $HomeworkDtoCopyWith<$Res> {
  _$HomeworkDtoCopyWithImpl(this._self, this._then);

  final HomeworkDto _self;
  final $Res Function(HomeworkDto) _then;

/// Create a copy of HomeworkDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? trainerId = null,Object? scope = null,Object? targetMemberIds = null,Object? excluded = null,Object? items = null,Object? schedule = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as String,targetMemberIds: null == targetMemberIds ? _self.targetMemberIds : targetMemberIds // ignore: cast_nullable_to_non_nullable
as List<String>,excluded: null == excluded ? _self.excluded : excluded // ignore: cast_nullable_to_non_nullable
as List<String>,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<HomeworkItemDto>,schedule: freezed == schedule ? _self.schedule : schedule // ignore: cast_nullable_to_non_nullable
as HomeworkScheduleDto?,
  ));
}
/// Create a copy of HomeworkDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HomeworkScheduleDtoCopyWith<$Res>? get schedule {
    if (_self.schedule == null) {
    return null;
  }

  return $HomeworkScheduleDtoCopyWith<$Res>(_self.schedule!, (value) {
    return _then(_self.copyWith(schedule: value));
  });
}
}


/// Adds pattern-matching-related methods to [HomeworkDto].
extension HomeworkDtoPatterns on HomeworkDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HomeworkDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HomeworkDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HomeworkDto value)  $default,){
final _that = this;
switch (_that) {
case _HomeworkDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HomeworkDto value)?  $default,){
final _that = this;
switch (_that) {
case _HomeworkDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'trainer_id')  String trainerId,  String scope, @JsonKey(name: 'target_member_ids')  List<String> targetMemberIds,  List<String> excluded,  List<HomeworkItemDto> items,  HomeworkScheduleDto? schedule)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HomeworkDto() when $default != null:
return $default(_that.id,_that.trainerId,_that.scope,_that.targetMemberIds,_that.excluded,_that.items,_that.schedule);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'trainer_id')  String trainerId,  String scope, @JsonKey(name: 'target_member_ids')  List<String> targetMemberIds,  List<String> excluded,  List<HomeworkItemDto> items,  HomeworkScheduleDto? schedule)  $default,) {final _that = this;
switch (_that) {
case _HomeworkDto():
return $default(_that.id,_that.trainerId,_that.scope,_that.targetMemberIds,_that.excluded,_that.items,_that.schedule);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'trainer_id')  String trainerId,  String scope, @JsonKey(name: 'target_member_ids')  List<String> targetMemberIds,  List<String> excluded,  List<HomeworkItemDto> items,  HomeworkScheduleDto? schedule)?  $default,) {final _that = this;
switch (_that) {
case _HomeworkDto() when $default != null:
return $default(_that.id,_that.trainerId,_that.scope,_that.targetMemberIds,_that.excluded,_that.items,_that.schedule);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _HomeworkDto implements HomeworkDto {
  const _HomeworkDto({required this.id, @JsonKey(name: 'trainer_id') required this.trainerId, this.scope = 'individual', @JsonKey(name: 'target_member_ids') final  List<String> targetMemberIds = const <String>[], final  List<String> excluded = const <String>[], final  List<HomeworkItemDto> items = const <HomeworkItemDto>[], this.schedule}): _targetMemberIds = targetMemberIds,_excluded = excluded,_items = items;
  factory _HomeworkDto.fromJson(Map<String, dynamic> json) => _$HomeworkDtoFromJson(json);

@override final  String id;
@override@JsonKey(name: 'trainer_id') final  String trainerId;
@override@JsonKey() final  String scope;
// individual|my_members|center_notice
 final  List<String> _targetMemberIds;
// individual|my_members|center_notice
@override@JsonKey(name: 'target_member_ids') List<String> get targetMemberIds {
  if (_targetMemberIds is EqualUnmodifiableListView) return _targetMemberIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_targetMemberIds);
}

 final  List<String> _excluded;
@override@JsonKey() List<String> get excluded {
  if (_excluded is EqualUnmodifiableListView) return _excluded;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_excluded);
}

 final  List<HomeworkItemDto> _items;
@override@JsonKey() List<HomeworkItemDto> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  HomeworkScheduleDto? schedule;

/// Create a copy of HomeworkDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HomeworkDtoCopyWith<_HomeworkDto> get copyWith => __$HomeworkDtoCopyWithImpl<_HomeworkDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$HomeworkDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HomeworkDto&&(identical(other.id, id) || other.id == id)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.scope, scope) || other.scope == scope)&&const DeepCollectionEquality().equals(other._targetMemberIds, _targetMemberIds)&&const DeepCollectionEquality().equals(other._excluded, _excluded)&&const DeepCollectionEquality().equals(other._items, _items)&&(identical(other.schedule, schedule) || other.schedule == schedule));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,trainerId,scope,const DeepCollectionEquality().hash(_targetMemberIds),const DeepCollectionEquality().hash(_excluded),const DeepCollectionEquality().hash(_items),schedule);

@override
String toString() {
  return 'HomeworkDto(id: $id, trainerId: $trainerId, scope: $scope, targetMemberIds: $targetMemberIds, excluded: $excluded, items: $items, schedule: $schedule)';
}


}

/// @nodoc
abstract mixin class _$HomeworkDtoCopyWith<$Res> implements $HomeworkDtoCopyWith<$Res> {
  factory _$HomeworkDtoCopyWith(_HomeworkDto value, $Res Function(_HomeworkDto) _then) = __$HomeworkDtoCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'trainer_id') String trainerId, String scope,@JsonKey(name: 'target_member_ids') List<String> targetMemberIds, List<String> excluded, List<HomeworkItemDto> items, HomeworkScheduleDto? schedule
});


@override $HomeworkScheduleDtoCopyWith<$Res>? get schedule;

}
/// @nodoc
class __$HomeworkDtoCopyWithImpl<$Res>
    implements _$HomeworkDtoCopyWith<$Res> {
  __$HomeworkDtoCopyWithImpl(this._self, this._then);

  final _HomeworkDto _self;
  final $Res Function(_HomeworkDto) _then;

/// Create a copy of HomeworkDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? trainerId = null,Object? scope = null,Object? targetMemberIds = null,Object? excluded = null,Object? items = null,Object? schedule = freezed,}) {
  return _then(_HomeworkDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as String,targetMemberIds: null == targetMemberIds ? _self._targetMemberIds : targetMemberIds // ignore: cast_nullable_to_non_nullable
as List<String>,excluded: null == excluded ? _self._excluded : excluded // ignore: cast_nullable_to_non_nullable
as List<String>,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<HomeworkItemDto>,schedule: freezed == schedule ? _self.schedule : schedule // ignore: cast_nullable_to_non_nullable
as HomeworkScheduleDto?,
  ));
}

/// Create a copy of HomeworkDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HomeworkScheduleDtoCopyWith<$Res>? get schedule {
    if (_self.schedule == null) {
    return null;
  }

  return $HomeworkScheduleDtoCopyWith<$Res>(_self.schedule!, (value) {
    return _then(_self.copyWith(schedule: value));
  });
}
}


/// @nodoc
mixin _$HomeworkItemDto {

 String get name; int? get sets;@JsonKey(fromJson: _repsToString) String? get reps; String? get note;
/// Create a copy of HomeworkItemDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HomeworkItemDtoCopyWith<HomeworkItemDto> get copyWith => _$HomeworkItemDtoCopyWithImpl<HomeworkItemDto>(this as HomeworkItemDto, _$identity);

  /// Serializes this HomeworkItemDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HomeworkItemDto&&(identical(other.name, name) || other.name == name)&&(identical(other.sets, sets) || other.sets == sets)&&(identical(other.reps, reps) || other.reps == reps)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,sets,reps,note);

@override
String toString() {
  return 'HomeworkItemDto(name: $name, sets: $sets, reps: $reps, note: $note)';
}


}

/// @nodoc
abstract mixin class $HomeworkItemDtoCopyWith<$Res>  {
  factory $HomeworkItemDtoCopyWith(HomeworkItemDto value, $Res Function(HomeworkItemDto) _then) = _$HomeworkItemDtoCopyWithImpl;
@useResult
$Res call({
 String name, int? sets,@JsonKey(fromJson: _repsToString) String? reps, String? note
});




}
/// @nodoc
class _$HomeworkItemDtoCopyWithImpl<$Res>
    implements $HomeworkItemDtoCopyWith<$Res> {
  _$HomeworkItemDtoCopyWithImpl(this._self, this._then);

  final HomeworkItemDto _self;
  final $Res Function(HomeworkItemDto) _then;

/// Create a copy of HomeworkItemDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? sets = freezed,Object? reps = freezed,Object? note = freezed,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sets: freezed == sets ? _self.sets : sets // ignore: cast_nullable_to_non_nullable
as int?,reps: freezed == reps ? _self.reps : reps // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [HomeworkItemDto].
extension HomeworkItemDtoPatterns on HomeworkItemDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HomeworkItemDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HomeworkItemDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HomeworkItemDto value)  $default,){
final _that = this;
switch (_that) {
case _HomeworkItemDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HomeworkItemDto value)?  $default,){
final _that = this;
switch (_that) {
case _HomeworkItemDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  int? sets, @JsonKey(fromJson: _repsToString)  String? reps,  String? note)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HomeworkItemDto() when $default != null:
return $default(_that.name,_that.sets,_that.reps,_that.note);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  int? sets, @JsonKey(fromJson: _repsToString)  String? reps,  String? note)  $default,) {final _that = this;
switch (_that) {
case _HomeworkItemDto():
return $default(_that.name,_that.sets,_that.reps,_that.note);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  int? sets, @JsonKey(fromJson: _repsToString)  String? reps,  String? note)?  $default,) {final _that = this;
switch (_that) {
case _HomeworkItemDto() when $default != null:
return $default(_that.name,_that.sets,_that.reps,_that.note);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _HomeworkItemDto implements HomeworkItemDto {
  const _HomeworkItemDto({required this.name, this.sets, @JsonKey(fromJson: _repsToString) this.reps, this.note});
  factory _HomeworkItemDto.fromJson(Map<String, dynamic> json) => _$HomeworkItemDtoFromJson(json);

@override final  String name;
@override final  int? sets;
@override@JsonKey(fromJson: _repsToString) final  String? reps;
@override final  String? note;

/// Create a copy of HomeworkItemDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HomeworkItemDtoCopyWith<_HomeworkItemDto> get copyWith => __$HomeworkItemDtoCopyWithImpl<_HomeworkItemDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$HomeworkItemDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HomeworkItemDto&&(identical(other.name, name) || other.name == name)&&(identical(other.sets, sets) || other.sets == sets)&&(identical(other.reps, reps) || other.reps == reps)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,sets,reps,note);

@override
String toString() {
  return 'HomeworkItemDto(name: $name, sets: $sets, reps: $reps, note: $note)';
}


}

/// @nodoc
abstract mixin class _$HomeworkItemDtoCopyWith<$Res> implements $HomeworkItemDtoCopyWith<$Res> {
  factory _$HomeworkItemDtoCopyWith(_HomeworkItemDto value, $Res Function(_HomeworkItemDto) _then) = __$HomeworkItemDtoCopyWithImpl;
@override @useResult
$Res call({
 String name, int? sets,@JsonKey(fromJson: _repsToString) String? reps, String? note
});




}
/// @nodoc
class __$HomeworkItemDtoCopyWithImpl<$Res>
    implements _$HomeworkItemDtoCopyWith<$Res> {
  __$HomeworkItemDtoCopyWithImpl(this._self, this._then);

  final _HomeworkItemDto _self;
  final $Res Function(_HomeworkItemDto) _then;

/// Create a copy of HomeworkItemDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? sets = freezed,Object? reps = freezed,Object? note = freezed,}) {
  return _then(_HomeworkItemDto(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sets: freezed == sets ? _self.sets : sets // ignore: cast_nullable_to_non_nullable
as int?,reps: freezed == reps ? _self.reps : reps // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$HomeworkScheduleDto {

 String get type;// once|weekly
 List<String> get days; String? get from; String? get to;
/// Create a copy of HomeworkScheduleDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HomeworkScheduleDtoCopyWith<HomeworkScheduleDto> get copyWith => _$HomeworkScheduleDtoCopyWithImpl<HomeworkScheduleDto>(this as HomeworkScheduleDto, _$identity);

  /// Serializes this HomeworkScheduleDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HomeworkScheduleDto&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.days, days)&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,const DeepCollectionEquality().hash(days),from,to);

@override
String toString() {
  return 'HomeworkScheduleDto(type: $type, days: $days, from: $from, to: $to)';
}


}

/// @nodoc
abstract mixin class $HomeworkScheduleDtoCopyWith<$Res>  {
  factory $HomeworkScheduleDtoCopyWith(HomeworkScheduleDto value, $Res Function(HomeworkScheduleDto) _then) = _$HomeworkScheduleDtoCopyWithImpl;
@useResult
$Res call({
 String type, List<String> days, String? from, String? to
});




}
/// @nodoc
class _$HomeworkScheduleDtoCopyWithImpl<$Res>
    implements $HomeworkScheduleDtoCopyWith<$Res> {
  _$HomeworkScheduleDtoCopyWithImpl(this._self, this._then);

  final HomeworkScheduleDto _self;
  final $Res Function(HomeworkScheduleDto) _then;

/// Create a copy of HomeworkScheduleDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? days = null,Object? from = freezed,Object? to = freezed,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,days: null == days ? _self.days : days // ignore: cast_nullable_to_non_nullable
as List<String>,from: freezed == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String?,to: freezed == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [HomeworkScheduleDto].
extension HomeworkScheduleDtoPatterns on HomeworkScheduleDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HomeworkScheduleDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HomeworkScheduleDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HomeworkScheduleDto value)  $default,){
final _that = this;
switch (_that) {
case _HomeworkScheduleDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HomeworkScheduleDto value)?  $default,){
final _that = this;
switch (_that) {
case _HomeworkScheduleDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String type,  List<String> days,  String? from,  String? to)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HomeworkScheduleDto() when $default != null:
return $default(_that.type,_that.days,_that.from,_that.to);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String type,  List<String> days,  String? from,  String? to)  $default,) {final _that = this;
switch (_that) {
case _HomeworkScheduleDto():
return $default(_that.type,_that.days,_that.from,_that.to);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String type,  List<String> days,  String? from,  String? to)?  $default,) {final _that = this;
switch (_that) {
case _HomeworkScheduleDto() when $default != null:
return $default(_that.type,_that.days,_that.from,_that.to);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _HomeworkScheduleDto implements HomeworkScheduleDto {
  const _HomeworkScheduleDto({this.type = 'weekly', final  List<String> days = const <String>[], this.from, this.to}): _days = days;
  factory _HomeworkScheduleDto.fromJson(Map<String, dynamic> json) => _$HomeworkScheduleDtoFromJson(json);

@override@JsonKey() final  String type;
// once|weekly
 final  List<String> _days;
// once|weekly
@override@JsonKey() List<String> get days {
  if (_days is EqualUnmodifiableListView) return _days;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_days);
}

@override final  String? from;
@override final  String? to;

/// Create a copy of HomeworkScheduleDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HomeworkScheduleDtoCopyWith<_HomeworkScheduleDto> get copyWith => __$HomeworkScheduleDtoCopyWithImpl<_HomeworkScheduleDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$HomeworkScheduleDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HomeworkScheduleDto&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other._days, _days)&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,const DeepCollectionEquality().hash(_days),from,to);

@override
String toString() {
  return 'HomeworkScheduleDto(type: $type, days: $days, from: $from, to: $to)';
}


}

/// @nodoc
abstract mixin class _$HomeworkScheduleDtoCopyWith<$Res> implements $HomeworkScheduleDtoCopyWith<$Res> {
  factory _$HomeworkScheduleDtoCopyWith(_HomeworkScheduleDto value, $Res Function(_HomeworkScheduleDto) _then) = __$HomeworkScheduleDtoCopyWithImpl;
@override @useResult
$Res call({
 String type, List<String> days, String? from, String? to
});




}
/// @nodoc
class __$HomeworkScheduleDtoCopyWithImpl<$Res>
    implements _$HomeworkScheduleDtoCopyWith<$Res> {
  __$HomeworkScheduleDtoCopyWithImpl(this._self, this._then);

  final _HomeworkScheduleDto _self;
  final $Res Function(_HomeworkScheduleDto) _then;

/// Create a copy of HomeworkScheduleDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? days = null,Object? from = freezed,Object? to = freezed,}) {
  return _then(_HomeworkScheduleDto(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,days: null == days ? _self._days : days // ignore: cast_nullable_to_non_nullable
as List<String>,from: freezed == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String?,to: freezed == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$HwCheckDto {

@JsonKey(name: 'member_id') String get memberId;@JsonKey(name: 'hw_id') String get hwId; String get date; List<bool> get done;
/// Create a copy of HwCheckDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HwCheckDtoCopyWith<HwCheckDto> get copyWith => _$HwCheckDtoCopyWithImpl<HwCheckDto>(this as HwCheckDto, _$identity);

  /// Serializes this HwCheckDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HwCheckDto&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.hwId, hwId) || other.hwId == hwId)&&(identical(other.date, date) || other.date == date)&&const DeepCollectionEquality().equals(other.done, done));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,memberId,hwId,date,const DeepCollectionEquality().hash(done));

@override
String toString() {
  return 'HwCheckDto(memberId: $memberId, hwId: $hwId, date: $date, done: $done)';
}


}

/// @nodoc
abstract mixin class $HwCheckDtoCopyWith<$Res>  {
  factory $HwCheckDtoCopyWith(HwCheckDto value, $Res Function(HwCheckDto) _then) = _$HwCheckDtoCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'hw_id') String hwId, String date, List<bool> done
});




}
/// @nodoc
class _$HwCheckDtoCopyWithImpl<$Res>
    implements $HwCheckDtoCopyWith<$Res> {
  _$HwCheckDtoCopyWithImpl(this._self, this._then);

  final HwCheckDto _self;
  final $Res Function(HwCheckDto) _then;

/// Create a copy of HwCheckDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? memberId = null,Object? hwId = null,Object? date = null,Object? done = null,}) {
  return _then(_self.copyWith(
memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,hwId: null == hwId ? _self.hwId : hwId // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,done: null == done ? _self.done : done // ignore: cast_nullable_to_non_nullable
as List<bool>,
  ));
}

}


/// Adds pattern-matching-related methods to [HwCheckDto].
extension HwCheckDtoPatterns on HwCheckDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HwCheckDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HwCheckDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HwCheckDto value)  $default,){
final _that = this;
switch (_that) {
case _HwCheckDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HwCheckDto value)?  $default,){
final _that = this;
switch (_that) {
case _HwCheckDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'hw_id')  String hwId,  String date,  List<bool> done)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HwCheckDto() when $default != null:
return $default(_that.memberId,_that.hwId,_that.date,_that.done);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'hw_id')  String hwId,  String date,  List<bool> done)  $default,) {final _that = this;
switch (_that) {
case _HwCheckDto():
return $default(_that.memberId,_that.hwId,_that.date,_that.done);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'hw_id')  String hwId,  String date,  List<bool> done)?  $default,) {final _that = this;
switch (_that) {
case _HwCheckDto() when $default != null:
return $default(_that.memberId,_that.hwId,_that.date,_that.done);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _HwCheckDto implements HwCheckDto {
  const _HwCheckDto({@JsonKey(name: 'member_id') required this.memberId, @JsonKey(name: 'hw_id') required this.hwId, required this.date, final  List<bool> done = const <bool>[]}): _done = done;
  factory _HwCheckDto.fromJson(Map<String, dynamic> json) => _$HwCheckDtoFromJson(json);

@override@JsonKey(name: 'member_id') final  String memberId;
@override@JsonKey(name: 'hw_id') final  String hwId;
@override final  String date;
 final  List<bool> _done;
@override@JsonKey() List<bool> get done {
  if (_done is EqualUnmodifiableListView) return _done;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_done);
}


/// Create a copy of HwCheckDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HwCheckDtoCopyWith<_HwCheckDto> get copyWith => __$HwCheckDtoCopyWithImpl<_HwCheckDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$HwCheckDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HwCheckDto&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.hwId, hwId) || other.hwId == hwId)&&(identical(other.date, date) || other.date == date)&&const DeepCollectionEquality().equals(other._done, _done));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,memberId,hwId,date,const DeepCollectionEquality().hash(_done));

@override
String toString() {
  return 'HwCheckDto(memberId: $memberId, hwId: $hwId, date: $date, done: $done)';
}


}

/// @nodoc
abstract mixin class _$HwCheckDtoCopyWith<$Res> implements $HwCheckDtoCopyWith<$Res> {
  factory _$HwCheckDtoCopyWith(_HwCheckDto value, $Res Function(_HwCheckDto) _then) = __$HwCheckDtoCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'hw_id') String hwId, String date, List<bool> done
});




}
/// @nodoc
class __$HwCheckDtoCopyWithImpl<$Res>
    implements _$HwCheckDtoCopyWith<$Res> {
  __$HwCheckDtoCopyWithImpl(this._self, this._then);

  final _HwCheckDto _self;
  final $Res Function(_HwCheckDto) _then;

/// Create a copy of HwCheckDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? memberId = null,Object? hwId = null,Object? date = null,Object? done = null,}) {
  return _then(_HwCheckDto(
memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,hwId: null == hwId ? _self.hwId : hwId // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,done: null == done ? _self._done : done // ignore: cast_nullable_to_non_nullable
as List<bool>,
  ));
}


}

// dart format on
