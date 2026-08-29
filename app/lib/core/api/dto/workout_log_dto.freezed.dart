// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workout_log_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WorkoutLogDto {

 String get id;@JsonKey(name: 'member_id') String get memberId;@JsonKey(name: 'trainer_id') String get trainerId;@JsonKey(name: 'booking_id') String? get bookingId; String get date;// "2026-08-22"
 String get title;// 서버 기본 "1:1 PT" — 빈 값은 repository에서 폴백
 List<WorkoutExerciseDto> get exercises;@JsonKey(name: 'coach_note') String get coachNote;
/// Create a copy of WorkoutLogDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkoutLogDtoCopyWith<WorkoutLogDto> get copyWith => _$WorkoutLogDtoCopyWithImpl<WorkoutLogDto>(this as WorkoutLogDto, _$identity);

  /// Serializes this WorkoutLogDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkoutLogDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.bookingId, bookingId) || other.bookingId == bookingId)&&(identical(other.date, date) || other.date == date)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.exercises, exercises)&&(identical(other.coachNote, coachNote) || other.coachNote == coachNote));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,trainerId,bookingId,date,title,const DeepCollectionEquality().hash(exercises),coachNote);

@override
String toString() {
  return 'WorkoutLogDto(id: $id, memberId: $memberId, trainerId: $trainerId, bookingId: $bookingId, date: $date, title: $title, exercises: $exercises, coachNote: $coachNote)';
}


}

/// @nodoc
abstract mixin class $WorkoutLogDtoCopyWith<$Res>  {
  factory $WorkoutLogDtoCopyWith(WorkoutLogDto value, $Res Function(WorkoutLogDto) _then) = _$WorkoutLogDtoCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'trainer_id') String trainerId,@JsonKey(name: 'booking_id') String? bookingId, String date, String title, List<WorkoutExerciseDto> exercises,@JsonKey(name: 'coach_note') String coachNote
});




}
/// @nodoc
class _$WorkoutLogDtoCopyWithImpl<$Res>
    implements $WorkoutLogDtoCopyWith<$Res> {
  _$WorkoutLogDtoCopyWithImpl(this._self, this._then);

  final WorkoutLogDto _self;
  final $Res Function(WorkoutLogDto) _then;

/// Create a copy of WorkoutLogDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? memberId = null,Object? trainerId = null,Object? bookingId = freezed,Object? date = null,Object? title = null,Object? exercises = null,Object? coachNote = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,bookingId: freezed == bookingId ? _self.bookingId : bookingId // ignore: cast_nullable_to_non_nullable
as String?,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,exercises: null == exercises ? _self.exercises : exercises // ignore: cast_nullable_to_non_nullable
as List<WorkoutExerciseDto>,coachNote: null == coachNote ? _self.coachNote : coachNote // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkoutLogDto].
extension WorkoutLogDtoPatterns on WorkoutLogDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkoutLogDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkoutLogDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkoutLogDto value)  $default,){
final _that = this;
switch (_that) {
case _WorkoutLogDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkoutLogDto value)?  $default,){
final _that = this;
switch (_that) {
case _WorkoutLogDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'booking_id')  String? bookingId,  String date,  String title,  List<WorkoutExerciseDto> exercises, @JsonKey(name: 'coach_note')  String coachNote)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkoutLogDto() when $default != null:
return $default(_that.id,_that.memberId,_that.trainerId,_that.bookingId,_that.date,_that.title,_that.exercises,_that.coachNote);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'booking_id')  String? bookingId,  String date,  String title,  List<WorkoutExerciseDto> exercises, @JsonKey(name: 'coach_note')  String coachNote)  $default,) {final _that = this;
switch (_that) {
case _WorkoutLogDto():
return $default(_that.id,_that.memberId,_that.trainerId,_that.bookingId,_that.date,_that.title,_that.exercises,_that.coachNote);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'trainer_id')  String trainerId, @JsonKey(name: 'booking_id')  String? bookingId,  String date,  String title,  List<WorkoutExerciseDto> exercises, @JsonKey(name: 'coach_note')  String coachNote)?  $default,) {final _that = this;
switch (_that) {
case _WorkoutLogDto() when $default != null:
return $default(_that.id,_that.memberId,_that.trainerId,_that.bookingId,_that.date,_that.title,_that.exercises,_that.coachNote);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorkoutLogDto implements WorkoutLogDto {
  const _WorkoutLogDto({required this.id, @JsonKey(name: 'member_id') required this.memberId, @JsonKey(name: 'trainer_id') required this.trainerId, @JsonKey(name: 'booking_id') this.bookingId, required this.date, this.title = '', final  List<WorkoutExerciseDto> exercises = const <WorkoutExerciseDto>[], @JsonKey(name: 'coach_note') this.coachNote = ''}): _exercises = exercises;
  factory _WorkoutLogDto.fromJson(Map<String, dynamic> json) => _$WorkoutLogDtoFromJson(json);

@override final  String id;
@override@JsonKey(name: 'member_id') final  String memberId;
@override@JsonKey(name: 'trainer_id') final  String trainerId;
@override@JsonKey(name: 'booking_id') final  String? bookingId;
@override final  String date;
// "2026-08-22"
@override@JsonKey() final  String title;
// 서버 기본 "1:1 PT" — 빈 값은 repository에서 폴백
 final  List<WorkoutExerciseDto> _exercises;
// 서버 기본 "1:1 PT" — 빈 값은 repository에서 폴백
@override@JsonKey() List<WorkoutExerciseDto> get exercises {
  if (_exercises is EqualUnmodifiableListView) return _exercises;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_exercises);
}

@override@JsonKey(name: 'coach_note') final  String coachNote;

/// Create a copy of WorkoutLogDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkoutLogDtoCopyWith<_WorkoutLogDto> get copyWith => __$WorkoutLogDtoCopyWithImpl<_WorkoutLogDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkoutLogDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkoutLogDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.trainerId, trainerId) || other.trainerId == trainerId)&&(identical(other.bookingId, bookingId) || other.bookingId == bookingId)&&(identical(other.date, date) || other.date == date)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other._exercises, _exercises)&&(identical(other.coachNote, coachNote) || other.coachNote == coachNote));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,trainerId,bookingId,date,title,const DeepCollectionEquality().hash(_exercises),coachNote);

@override
String toString() {
  return 'WorkoutLogDto(id: $id, memberId: $memberId, trainerId: $trainerId, bookingId: $bookingId, date: $date, title: $title, exercises: $exercises, coachNote: $coachNote)';
}


}

/// @nodoc
abstract mixin class _$WorkoutLogDtoCopyWith<$Res> implements $WorkoutLogDtoCopyWith<$Res> {
  factory _$WorkoutLogDtoCopyWith(_WorkoutLogDto value, $Res Function(_WorkoutLogDto) _then) = __$WorkoutLogDtoCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'trainer_id') String trainerId,@JsonKey(name: 'booking_id') String? bookingId, String date, String title, List<WorkoutExerciseDto> exercises,@JsonKey(name: 'coach_note') String coachNote
});




}
/// @nodoc
class __$WorkoutLogDtoCopyWithImpl<$Res>
    implements _$WorkoutLogDtoCopyWith<$Res> {
  __$WorkoutLogDtoCopyWithImpl(this._self, this._then);

  final _WorkoutLogDto _self;
  final $Res Function(_WorkoutLogDto) _then;

/// Create a copy of WorkoutLogDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? memberId = null,Object? trainerId = null,Object? bookingId = freezed,Object? date = null,Object? title = null,Object? exercises = null,Object? coachNote = null,}) {
  return _then(_WorkoutLogDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,trainerId: null == trainerId ? _self.trainerId : trainerId // ignore: cast_nullable_to_non_nullable
as String,bookingId: freezed == bookingId ? _self.bookingId : bookingId // ignore: cast_nullable_to_non_nullable
as String?,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,exercises: null == exercises ? _self._exercises : exercises // ignore: cast_nullable_to_non_nullable
as List<WorkoutExerciseDto>,coachNote: null == coachNote ? _self.coachNote : coachNote // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$WorkoutExerciseDto {

 String get name; int get sets;@JsonKey(fromJson: _repsToString) String? get reps;// 계약: 숫자(int/float 혼용 가능) → double. 0 = 자중/해당 없음.
@JsonKey(name: 'weight_kg') double get weightKg; String? get note;
/// Create a copy of WorkoutExerciseDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkoutExerciseDtoCopyWith<WorkoutExerciseDto> get copyWith => _$WorkoutExerciseDtoCopyWithImpl<WorkoutExerciseDto>(this as WorkoutExerciseDto, _$identity);

  /// Serializes this WorkoutExerciseDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkoutExerciseDto&&(identical(other.name, name) || other.name == name)&&(identical(other.sets, sets) || other.sets == sets)&&(identical(other.reps, reps) || other.reps == reps)&&(identical(other.weightKg, weightKg) || other.weightKg == weightKg)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,sets,reps,weightKg,note);

@override
String toString() {
  return 'WorkoutExerciseDto(name: $name, sets: $sets, reps: $reps, weightKg: $weightKg, note: $note)';
}


}

/// @nodoc
abstract mixin class $WorkoutExerciseDtoCopyWith<$Res>  {
  factory $WorkoutExerciseDtoCopyWith(WorkoutExerciseDto value, $Res Function(WorkoutExerciseDto) _then) = _$WorkoutExerciseDtoCopyWithImpl;
@useResult
$Res call({
 String name, int sets,@JsonKey(fromJson: _repsToString) String? reps,@JsonKey(name: 'weight_kg') double weightKg, String? note
});




}
/// @nodoc
class _$WorkoutExerciseDtoCopyWithImpl<$Res>
    implements $WorkoutExerciseDtoCopyWith<$Res> {
  _$WorkoutExerciseDtoCopyWithImpl(this._self, this._then);

  final WorkoutExerciseDto _self;
  final $Res Function(WorkoutExerciseDto) _then;

/// Create a copy of WorkoutExerciseDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? sets = null,Object? reps = freezed,Object? weightKg = null,Object? note = freezed,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sets: null == sets ? _self.sets : sets // ignore: cast_nullable_to_non_nullable
as int,reps: freezed == reps ? _self.reps : reps // ignore: cast_nullable_to_non_nullable
as String?,weightKg: null == weightKg ? _self.weightKg : weightKg // ignore: cast_nullable_to_non_nullable
as double,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkoutExerciseDto].
extension WorkoutExerciseDtoPatterns on WorkoutExerciseDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkoutExerciseDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkoutExerciseDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkoutExerciseDto value)  $default,){
final _that = this;
switch (_that) {
case _WorkoutExerciseDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkoutExerciseDto value)?  $default,){
final _that = this;
switch (_that) {
case _WorkoutExerciseDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  int sets, @JsonKey(fromJson: _repsToString)  String? reps, @JsonKey(name: 'weight_kg')  double weightKg,  String? note)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkoutExerciseDto() when $default != null:
return $default(_that.name,_that.sets,_that.reps,_that.weightKg,_that.note);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  int sets, @JsonKey(fromJson: _repsToString)  String? reps, @JsonKey(name: 'weight_kg')  double weightKg,  String? note)  $default,) {final _that = this;
switch (_that) {
case _WorkoutExerciseDto():
return $default(_that.name,_that.sets,_that.reps,_that.weightKg,_that.note);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  int sets, @JsonKey(fromJson: _repsToString)  String? reps, @JsonKey(name: 'weight_kg')  double weightKg,  String? note)?  $default,) {final _that = this;
switch (_that) {
case _WorkoutExerciseDto() when $default != null:
return $default(_that.name,_that.sets,_that.reps,_that.weightKg,_that.note);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorkoutExerciseDto implements WorkoutExerciseDto {
  const _WorkoutExerciseDto({required this.name, this.sets = 0, @JsonKey(fromJson: _repsToString) this.reps, @JsonKey(name: 'weight_kg') this.weightKg = 0, this.note});
  factory _WorkoutExerciseDto.fromJson(Map<String, dynamic> json) => _$WorkoutExerciseDtoFromJson(json);

@override final  String name;
@override@JsonKey() final  int sets;
@override@JsonKey(fromJson: _repsToString) final  String? reps;
// 계약: 숫자(int/float 혼용 가능) → double. 0 = 자중/해당 없음.
@override@JsonKey(name: 'weight_kg') final  double weightKg;
@override final  String? note;

/// Create a copy of WorkoutExerciseDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkoutExerciseDtoCopyWith<_WorkoutExerciseDto> get copyWith => __$WorkoutExerciseDtoCopyWithImpl<_WorkoutExerciseDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkoutExerciseDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkoutExerciseDto&&(identical(other.name, name) || other.name == name)&&(identical(other.sets, sets) || other.sets == sets)&&(identical(other.reps, reps) || other.reps == reps)&&(identical(other.weightKg, weightKg) || other.weightKg == weightKg)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,sets,reps,weightKg,note);

@override
String toString() {
  return 'WorkoutExerciseDto(name: $name, sets: $sets, reps: $reps, weightKg: $weightKg, note: $note)';
}


}

/// @nodoc
abstract mixin class _$WorkoutExerciseDtoCopyWith<$Res> implements $WorkoutExerciseDtoCopyWith<$Res> {
  factory _$WorkoutExerciseDtoCopyWith(_WorkoutExerciseDto value, $Res Function(_WorkoutExerciseDto) _then) = __$WorkoutExerciseDtoCopyWithImpl;
@override @useResult
$Res call({
 String name, int sets,@JsonKey(fromJson: _repsToString) String? reps,@JsonKey(name: 'weight_kg') double weightKg, String? note
});




}
/// @nodoc
class __$WorkoutExerciseDtoCopyWithImpl<$Res>
    implements _$WorkoutExerciseDtoCopyWith<$Res> {
  __$WorkoutExerciseDtoCopyWithImpl(this._self, this._then);

  final _WorkoutExerciseDto _self;
  final $Res Function(_WorkoutExerciseDto) _then;

/// Create a copy of WorkoutExerciseDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? sets = null,Object? reps = freezed,Object? weightKg = null,Object? note = freezed,}) {
  return _then(_WorkoutExerciseDto(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sets: null == sets ? _self.sets : sets // ignore: cast_nullable_to_non_nullable
as int,reps: freezed == reps ? _self.reps : reps // ignore: cast_nullable_to_non_nullable
as String?,weightKg: null == weightKg ? _self.weightKg : weightKg // ignore: cast_nullable_to_non_nullable
as double,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
