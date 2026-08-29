// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'contract_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ContractDto {

 String get id;@JsonKey(name: 'member_id') String get memberId;@JsonKey(name: 'pass_id') String get passId; String get product;@JsonKey(name: 'paid_amount') int get paidAmount;// v1.5 이전 서버 응답엔 없을 수 있어 nullable — 회원 앱은 표시에 안 쓰고 파싱 안전만 보장.
@JsonKey(name: 'penalty_rate') double? get penaltyRate; String get status;// draft|sent|signed|voided
@JsonKey(name: 'sent_at') String? get sentAt;@JsonKey(name: 'first_sent_at') String? get firstSentAt;@JsonKey(name: 'signed_at') String? get signedAt;@JsonKey(name: 'signer_ip') String? get signerIp; String? get sha256;@JsonKey(name: 'pdf_path') String? get pdfPath;
/// Create a copy of ContractDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContractDtoCopyWith<ContractDto> get copyWith => _$ContractDtoCopyWithImpl<ContractDto>(this as ContractDto, _$identity);

  /// Serializes this ContractDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContractDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.passId, passId) || other.passId == passId)&&(identical(other.product, product) || other.product == product)&&(identical(other.paidAmount, paidAmount) || other.paidAmount == paidAmount)&&(identical(other.penaltyRate, penaltyRate) || other.penaltyRate == penaltyRate)&&(identical(other.status, status) || other.status == status)&&(identical(other.sentAt, sentAt) || other.sentAt == sentAt)&&(identical(other.firstSentAt, firstSentAt) || other.firstSentAt == firstSentAt)&&(identical(other.signedAt, signedAt) || other.signedAt == signedAt)&&(identical(other.signerIp, signerIp) || other.signerIp == signerIp)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.pdfPath, pdfPath) || other.pdfPath == pdfPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,passId,product,paidAmount,penaltyRate,status,sentAt,firstSentAt,signedAt,signerIp,sha256,pdfPath);

@override
String toString() {
  return 'ContractDto(id: $id, memberId: $memberId, passId: $passId, product: $product, paidAmount: $paidAmount, penaltyRate: $penaltyRate, status: $status, sentAt: $sentAt, firstSentAt: $firstSentAt, signedAt: $signedAt, signerIp: $signerIp, sha256: $sha256, pdfPath: $pdfPath)';
}


}

/// @nodoc
abstract mixin class $ContractDtoCopyWith<$Res>  {
  factory $ContractDtoCopyWith(ContractDto value, $Res Function(ContractDto) _then) = _$ContractDtoCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'pass_id') String passId, String product,@JsonKey(name: 'paid_amount') int paidAmount,@JsonKey(name: 'penalty_rate') double? penaltyRate, String status,@JsonKey(name: 'sent_at') String? sentAt,@JsonKey(name: 'first_sent_at') String? firstSentAt,@JsonKey(name: 'signed_at') String? signedAt,@JsonKey(name: 'signer_ip') String? signerIp, String? sha256,@JsonKey(name: 'pdf_path') String? pdfPath
});




}
/// @nodoc
class _$ContractDtoCopyWithImpl<$Res>
    implements $ContractDtoCopyWith<$Res> {
  _$ContractDtoCopyWithImpl(this._self, this._then);

  final ContractDto _self;
  final $Res Function(ContractDto) _then;

/// Create a copy of ContractDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? memberId = null,Object? passId = null,Object? product = null,Object? paidAmount = null,Object? penaltyRate = freezed,Object? status = null,Object? sentAt = freezed,Object? firstSentAt = freezed,Object? signedAt = freezed,Object? signerIp = freezed,Object? sha256 = freezed,Object? pdfPath = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,passId: null == passId ? _self.passId : passId // ignore: cast_nullable_to_non_nullable
as String,product: null == product ? _self.product : product // ignore: cast_nullable_to_non_nullable
as String,paidAmount: null == paidAmount ? _self.paidAmount : paidAmount // ignore: cast_nullable_to_non_nullable
as int,penaltyRate: freezed == penaltyRate ? _self.penaltyRate : penaltyRate // ignore: cast_nullable_to_non_nullable
as double?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,sentAt: freezed == sentAt ? _self.sentAt : sentAt // ignore: cast_nullable_to_non_nullable
as String?,firstSentAt: freezed == firstSentAt ? _self.firstSentAt : firstSentAt // ignore: cast_nullable_to_non_nullable
as String?,signedAt: freezed == signedAt ? _self.signedAt : signedAt // ignore: cast_nullable_to_non_nullable
as String?,signerIp: freezed == signerIp ? _self.signerIp : signerIp // ignore: cast_nullable_to_non_nullable
as String?,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,pdfPath: freezed == pdfPath ? _self.pdfPath : pdfPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ContractDto].
extension ContractDtoPatterns on ContractDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContractDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContractDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContractDto value)  $default,){
final _that = this;
switch (_that) {
case _ContractDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContractDto value)?  $default,){
final _that = this;
switch (_that) {
case _ContractDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'pass_id')  String passId,  String product, @JsonKey(name: 'paid_amount')  int paidAmount, @JsonKey(name: 'penalty_rate')  double? penaltyRate,  String status, @JsonKey(name: 'sent_at')  String? sentAt, @JsonKey(name: 'first_sent_at')  String? firstSentAt, @JsonKey(name: 'signed_at')  String? signedAt, @JsonKey(name: 'signer_ip')  String? signerIp,  String? sha256, @JsonKey(name: 'pdf_path')  String? pdfPath)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContractDto() when $default != null:
return $default(_that.id,_that.memberId,_that.passId,_that.product,_that.paidAmount,_that.penaltyRate,_that.status,_that.sentAt,_that.firstSentAt,_that.signedAt,_that.signerIp,_that.sha256,_that.pdfPath);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'pass_id')  String passId,  String product, @JsonKey(name: 'paid_amount')  int paidAmount, @JsonKey(name: 'penalty_rate')  double? penaltyRate,  String status, @JsonKey(name: 'sent_at')  String? sentAt, @JsonKey(name: 'first_sent_at')  String? firstSentAt, @JsonKey(name: 'signed_at')  String? signedAt, @JsonKey(name: 'signer_ip')  String? signerIp,  String? sha256, @JsonKey(name: 'pdf_path')  String? pdfPath)  $default,) {final _that = this;
switch (_that) {
case _ContractDto():
return $default(_that.id,_that.memberId,_that.passId,_that.product,_that.paidAmount,_that.penaltyRate,_that.status,_that.sentAt,_that.firstSentAt,_that.signedAt,_that.signerIp,_that.sha256,_that.pdfPath);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'member_id')  String memberId, @JsonKey(name: 'pass_id')  String passId,  String product, @JsonKey(name: 'paid_amount')  int paidAmount, @JsonKey(name: 'penalty_rate')  double? penaltyRate,  String status, @JsonKey(name: 'sent_at')  String? sentAt, @JsonKey(name: 'first_sent_at')  String? firstSentAt, @JsonKey(name: 'signed_at')  String? signedAt, @JsonKey(name: 'signer_ip')  String? signerIp,  String? sha256, @JsonKey(name: 'pdf_path')  String? pdfPath)?  $default,) {final _that = this;
switch (_that) {
case _ContractDto() when $default != null:
return $default(_that.id,_that.memberId,_that.passId,_that.product,_that.paidAmount,_that.penaltyRate,_that.status,_that.sentAt,_that.firstSentAt,_that.signedAt,_that.signerIp,_that.sha256,_that.pdfPath);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ContractDto implements ContractDto {
  const _ContractDto({required this.id, @JsonKey(name: 'member_id') required this.memberId, @JsonKey(name: 'pass_id') required this.passId, required this.product, @JsonKey(name: 'paid_amount') required this.paidAmount, @JsonKey(name: 'penalty_rate') this.penaltyRate, this.status = 'draft', @JsonKey(name: 'sent_at') this.sentAt, @JsonKey(name: 'first_sent_at') this.firstSentAt, @JsonKey(name: 'signed_at') this.signedAt, @JsonKey(name: 'signer_ip') this.signerIp, this.sha256, @JsonKey(name: 'pdf_path') this.pdfPath});
  factory _ContractDto.fromJson(Map<String, dynamic> json) => _$ContractDtoFromJson(json);

@override final  String id;
@override@JsonKey(name: 'member_id') final  String memberId;
@override@JsonKey(name: 'pass_id') final  String passId;
@override final  String product;
@override@JsonKey(name: 'paid_amount') final  int paidAmount;
// v1.5 이전 서버 응답엔 없을 수 있어 nullable — 회원 앱은 표시에 안 쓰고 파싱 안전만 보장.
@override@JsonKey(name: 'penalty_rate') final  double? penaltyRate;
@override@JsonKey() final  String status;
// draft|sent|signed|voided
@override@JsonKey(name: 'sent_at') final  String? sentAt;
@override@JsonKey(name: 'first_sent_at') final  String? firstSentAt;
@override@JsonKey(name: 'signed_at') final  String? signedAt;
@override@JsonKey(name: 'signer_ip') final  String? signerIp;
@override final  String? sha256;
@override@JsonKey(name: 'pdf_path') final  String? pdfPath;

/// Create a copy of ContractDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContractDtoCopyWith<_ContractDto> get copyWith => __$ContractDtoCopyWithImpl<_ContractDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ContractDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContractDto&&(identical(other.id, id) || other.id == id)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.passId, passId) || other.passId == passId)&&(identical(other.product, product) || other.product == product)&&(identical(other.paidAmount, paidAmount) || other.paidAmount == paidAmount)&&(identical(other.penaltyRate, penaltyRate) || other.penaltyRate == penaltyRate)&&(identical(other.status, status) || other.status == status)&&(identical(other.sentAt, sentAt) || other.sentAt == sentAt)&&(identical(other.firstSentAt, firstSentAt) || other.firstSentAt == firstSentAt)&&(identical(other.signedAt, signedAt) || other.signedAt == signedAt)&&(identical(other.signerIp, signerIp) || other.signerIp == signerIp)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.pdfPath, pdfPath) || other.pdfPath == pdfPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,memberId,passId,product,paidAmount,penaltyRate,status,sentAt,firstSentAt,signedAt,signerIp,sha256,pdfPath);

@override
String toString() {
  return 'ContractDto(id: $id, memberId: $memberId, passId: $passId, product: $product, paidAmount: $paidAmount, penaltyRate: $penaltyRate, status: $status, sentAt: $sentAt, firstSentAt: $firstSentAt, signedAt: $signedAt, signerIp: $signerIp, sha256: $sha256, pdfPath: $pdfPath)';
}


}

/// @nodoc
abstract mixin class _$ContractDtoCopyWith<$Res> implements $ContractDtoCopyWith<$Res> {
  factory _$ContractDtoCopyWith(_ContractDto value, $Res Function(_ContractDto) _then) = __$ContractDtoCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'member_id') String memberId,@JsonKey(name: 'pass_id') String passId, String product,@JsonKey(name: 'paid_amount') int paidAmount,@JsonKey(name: 'penalty_rate') double? penaltyRate, String status,@JsonKey(name: 'sent_at') String? sentAt,@JsonKey(name: 'first_sent_at') String? firstSentAt,@JsonKey(name: 'signed_at') String? signedAt,@JsonKey(name: 'signer_ip') String? signerIp, String? sha256,@JsonKey(name: 'pdf_path') String? pdfPath
});




}
/// @nodoc
class __$ContractDtoCopyWithImpl<$Res>
    implements _$ContractDtoCopyWith<$Res> {
  __$ContractDtoCopyWithImpl(this._self, this._then);

  final _ContractDto _self;
  final $Res Function(_ContractDto) _then;

/// Create a copy of ContractDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? memberId = null,Object? passId = null,Object? product = null,Object? paidAmount = null,Object? penaltyRate = freezed,Object? status = null,Object? sentAt = freezed,Object? firstSentAt = freezed,Object? signedAt = freezed,Object? signerIp = freezed,Object? sha256 = freezed,Object? pdfPath = freezed,}) {
  return _then(_ContractDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,passId: null == passId ? _self.passId : passId // ignore: cast_nullable_to_non_nullable
as String,product: null == product ? _self.product : product // ignore: cast_nullable_to_non_nullable
as String,paidAmount: null == paidAmount ? _self.paidAmount : paidAmount // ignore: cast_nullable_to_non_nullable
as int,penaltyRate: freezed == penaltyRate ? _self.penaltyRate : penaltyRate // ignore: cast_nullable_to_non_nullable
as double?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,sentAt: freezed == sentAt ? _self.sentAt : sentAt // ignore: cast_nullable_to_non_nullable
as String?,firstSentAt: freezed == firstSentAt ? _self.firstSentAt : firstSentAt // ignore: cast_nullable_to_non_nullable
as String?,signedAt: freezed == signedAt ? _self.signedAt : signedAt // ignore: cast_nullable_to_non_nullable
as String?,signerIp: freezed == signerIp ? _self.signerIp : signerIp // ignore: cast_nullable_to_non_nullable
as String?,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,pdfPath: freezed == pdfPath ? _self.pdfPath : pdfPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
