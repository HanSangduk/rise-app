// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'inbody_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$InbodyDto {

 String get id;@JsonKey(name: 'member_id') String get memberId; String get date; double get weight; double get smm;// 골격근량
 double get bfm;// 체지방량
 double get pbf;// 체지방률
 double get vfl;// 내장지방레벨
 double get bmr;// 기초대사량
/// 출처(`member_self` = 회원 본인 입력 / 그 외 = 코치·어드민).
///
/// **반드시 nullable.** 서버가 이 필드를 채우기 전에 저장된 레코드에는 키가
/// 아예 없어서, required로 두면 그 전부가 fromJson에서 던진다 — 인바디 파싱
/// 실패 1건이 기록 탭 셋(운동·인바디·체형)을 통째로 죽인 전례가 이미 있다
/// (`records_repository_impl.dart`의 날짜 가드 주석).
///
/// 응답 파싱 전용이다. 생성 요청 바디에는 넣지 않는다 — 서버 `decodeJSON`이
/// `DisallowUnknownFields`라 미지 필드는 400이고, 출처는 서버가 Principal로
/// 판정하는 값이라 클라이언트가 주장할 성질이 아니다.
 String? get source;
/// Create a copy of InbodyDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InbodyDtoCopyWith<InbodyDto> get copyWith => _$InbodyDtoCopyWithImpl<InbodyDto>(this as InbodyDto, _$identity);

  /// Serializes this InbodyDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InbodyDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.date, date) || other.date == date)&&(identical(other.weight, weight) || other.weight == weight)&&(identical(other.smm, smm) || other.smm == smm)&&(identical(other.bfm, bfm) || other.bfm == bfm)&&(identical(other.pbf, pbf) || other.pbf == pbf)&&(identical(other.vfl, vfl) || other.vfl == vfl)&&(identical(other.bmr, bmr) || other.bmr == bmr)&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,date,weight,smm,bfm,pbf,vfl,bmr,source);

@override
String toString() {
  return 'InbodyDto(id: $id, memberId: $memberId, date: $date, weight: $weight, smm: $smm, bfm: $bfm, pbf: $pbf, vfl: $vfl, bmr: $bmr, source: $source)';
}


}

/// @nodoc
abstract mixin class $InbodyDtoCopyWith<$Res>  {
  factory $InbodyDtoCopyWith(InbodyDto value, $Res Function(InbodyDto) _then) = _$InbodyDtoCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId, String date, double weight, double smm, double bfm, double pbf, double vfl, double bmr, String? source
});




}
/// @nodoc
class _$InbodyDtoCopyWithImpl<$Res>
    implements $InbodyDtoCopyWith<$Res> {
  _$InbodyDtoCopyWithImpl(this._self, this._then);

  final InbodyDto _self;
  final $Res Function(InbodyDto) _then;

/// Create a copy of InbodyDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? memberId = null,Object? date = null,Object? weight = null,Object? smm = null,Object? bfm = null,Object? pbf = null,Object? vfl = null,Object? bmr = null,Object? source = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,weight: null == weight ? _self.weight : weight // ignore: cast_nullable_to_non_nullable
as double,smm: null == smm ? _self.smm : smm // ignore: cast_nullable_to_non_nullable
as double,bfm: null == bfm ? _self.bfm : bfm // ignore: cast_nullable_to_non_nullable
as double,pbf: null == pbf ? _self.pbf : pbf // ignore: cast_nullable_to_non_nullable
as double,vfl: null == vfl ? _self.vfl : vfl // ignore: cast_nullable_to_non_nullable
as double,bmr: null == bmr ? _self.bmr : bmr // ignore: cast_nullable_to_non_nullable
as double,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [InbodyDto].
extension InbodyDtoPatterns on InbodyDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InbodyDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InbodyDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InbodyDto value)  $default,){
final _that = this;
switch (_that) {
case _InbodyDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InbodyDto value)?  $default,){
final _that = this;
switch (_that) {
case _InbodyDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId,  String date,  double weight,  double smm,  double bfm,  double pbf,  double vfl,  double bmr,  String? source)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InbodyDto() when $default != null:
return $default(_that.id,_that.memberId,_that.date,_that.weight,_that.smm,_that.bfm,_that.pbf,_that.vfl,_that.bmr,_that.source);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId,  String date,  double weight,  double smm,  double bfm,  double pbf,  double vfl,  double bmr,  String? source)  $default,) {final _that = this;
switch (_that) {
case _InbodyDto():
return $default(_that.id,_that.memberId,_that.date,_that.weight,_that.smm,_that.bfm,_that.pbf,_that.vfl,_that.bmr,_that.source);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'member_id')  String memberId,  String date,  double weight,  double smm,  double bfm,  double pbf,  double vfl,  double bmr,  String? source)?  $default,) {final _that = this;
switch (_that) {
case _InbodyDto() when $default != null:
return $default(_that.id,_that.memberId,_that.date,_that.weight,_that.smm,_that.bfm,_that.pbf,_that.vfl,_that.bmr,_that.source);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _InbodyDto implements InbodyDto {
  const _InbodyDto({required this.id, @JsonKey(name: 'member_id') required this.memberId, required this.date, required this.weight, required this.smm, required this.bfm, required this.pbf, required this.vfl, required this.bmr, this.source});
  factory _InbodyDto.fromJson(Map<String, dynamic> json) => _$InbodyDtoFromJson(json);

@override final  String id;
@override@JsonKey(name: 'member_id') final  String memberId;
@override final  String date;
@override final  double weight;
@override final  double smm;
// 골격근량
@override final  double bfm;
// 체지방량
@override final  double pbf;
// 체지방률
@override final  double vfl;
// 내장지방레벨
@override final  double bmr;
// 기초대사량
/// 출처(`member_self` = 회원 본인 입력 / 그 외 = 코치·어드민).
///
/// **반드시 nullable.** 서버가 이 필드를 채우기 전에 저장된 레코드에는 키가
/// 아예 없어서, required로 두면 그 전부가 fromJson에서 던진다 — 인바디 파싱
/// 실패 1건이 기록 탭 셋(운동·인바디·체형)을 통째로 죽인 전례가 이미 있다
/// (`records_repository_impl.dart`의 날짜 가드 주석).
///
/// 응답 파싱 전용이다. 생성 요청 바디에는 넣지 않는다 — 서버 `decodeJSON`이
/// `DisallowUnknownFields`라 미지 필드는 400이고, 출처는 서버가 Principal로
/// 판정하는 값이라 클라이언트가 주장할 성질이 아니다.
@override final  String? source;

/// Create a copy of InbodyDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InbodyDtoCopyWith<_InbodyDto> get copyWith => __$InbodyDtoCopyWithImpl<_InbodyDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$InbodyDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InbodyDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.date, date) || other.date == date)&&(identical(other.weight, weight) || other.weight == weight)&&(identical(other.smm, smm) || other.smm == smm)&&(identical(other.bfm, bfm) || other.bfm == bfm)&&(identical(other.pbf, pbf) || other.pbf == pbf)&&(identical(other.vfl, vfl) || other.vfl == vfl)&&(identical(other.bmr, bmr) || other.bmr == bmr)&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,date,weight,smm,bfm,pbf,vfl,bmr,source);

@override
String toString() {
  return 'InbodyDto(id: $id, memberId: $memberId, date: $date, weight: $weight, smm: $smm, bfm: $bfm, pbf: $pbf, vfl: $vfl, bmr: $bmr, source: $source)';
}


}

/// @nodoc
abstract mixin class _$InbodyDtoCopyWith<$Res> implements $InbodyDtoCopyWith<$Res> {
  factory _$InbodyDtoCopyWith(_InbodyDto value, $Res Function(_InbodyDto) _then) = __$InbodyDtoCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId, String date, double weight, double smm, double bfm, double pbf, double vfl, double bmr, String? source
});




}
/// @nodoc
class __$InbodyDtoCopyWithImpl<$Res>
    implements _$InbodyDtoCopyWith<$Res> {
  __$InbodyDtoCopyWithImpl(this._self, this._then);

  final _InbodyDto _self;
  final $Res Function(_InbodyDto) _then;

/// Create a copy of InbodyDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? memberId = null,Object? date = null,Object? weight = null,Object? smm = null,Object? bfm = null,Object? pbf = null,Object? vfl = null,Object? bmr = null,Object? source = freezed,}) {
  return _then(_InbodyDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,weight: null == weight ? _self.weight : weight // ignore: cast_nullable_to_non_nullable
as double,smm: null == smm ? _self.smm : smm // ignore: cast_nullable_to_non_nullable
as double,bfm: null == bfm ? _self.bfm : bfm // ignore: cast_nullable_to_non_nullable
as double,pbf: null == pbf ? _self.pbf : pbf // ignore: cast_nullable_to_non_nullable
as double,vfl: null == vfl ? _self.vfl : vfl // ignore: cast_nullable_to_non_nullable
as double,bmr: null == bmr ? _self.bmr : bmr // ignore: cast_nullable_to_non_nullable
as double,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
