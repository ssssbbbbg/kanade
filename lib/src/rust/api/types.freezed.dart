// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$QrStatus {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QrStatus);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QrStatus()';
}


}

/// @nodoc
class $QrStatusCopyWith<$Res>  {
$QrStatusCopyWith(QrStatus _, $Res Function(QrStatus) __);
}


/// Adds pattern-matching-related methods to [QrStatus].
extension QrStatusPatterns on QrStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( QrStatus_Waiting value)?  waiting,TResult Function( QrStatus_Scanned value)?  scanned,TResult Function( QrStatus_Expired value)?  expired,TResult Function( QrStatus_Refused value)?  refused,TResult Function( QrStatus_Success value)?  success,required TResult orElse(),}){
final _that = this;
switch (_that) {
case QrStatus_Waiting() when waiting != null:
return waiting(_that);case QrStatus_Scanned() when scanned != null:
return scanned(_that);case QrStatus_Expired() when expired != null:
return expired(_that);case QrStatus_Refused() when refused != null:
return refused(_that);case QrStatus_Success() when success != null:
return success(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( QrStatus_Waiting value)  waiting,required TResult Function( QrStatus_Scanned value)  scanned,required TResult Function( QrStatus_Expired value)  expired,required TResult Function( QrStatus_Refused value)  refused,required TResult Function( QrStatus_Success value)  success,}){
final _that = this;
switch (_that) {
case QrStatus_Waiting():
return waiting(_that);case QrStatus_Scanned():
return scanned(_that);case QrStatus_Expired():
return expired(_that);case QrStatus_Refused():
return refused(_that);case QrStatus_Success():
return success(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( QrStatus_Waiting value)?  waiting,TResult? Function( QrStatus_Scanned value)?  scanned,TResult? Function( QrStatus_Expired value)?  expired,TResult? Function( QrStatus_Refused value)?  refused,TResult? Function( QrStatus_Success value)?  success,}){
final _that = this;
switch (_that) {
case QrStatus_Waiting() when waiting != null:
return waiting(_that);case QrStatus_Scanned() when scanned != null:
return scanned(_that);case QrStatus_Expired() when expired != null:
return expired(_that);case QrStatus_Refused() when refused != null:
return refused(_that);case QrStatus_Success() when success != null:
return success(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  waiting,TResult Function()?  scanned,TResult Function()?  expired,TResult Function()?  refused,TResult Function( UserInfo user)?  success,required TResult orElse(),}) {final _that = this;
switch (_that) {
case QrStatus_Waiting() when waiting != null:
return waiting();case QrStatus_Scanned() when scanned != null:
return scanned();case QrStatus_Expired() when expired != null:
return expired();case QrStatus_Refused() when refused != null:
return refused();case QrStatus_Success() when success != null:
return success(_that.user);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  waiting,required TResult Function()  scanned,required TResult Function()  expired,required TResult Function()  refused,required TResult Function( UserInfo user)  success,}) {final _that = this;
switch (_that) {
case QrStatus_Waiting():
return waiting();case QrStatus_Scanned():
return scanned();case QrStatus_Expired():
return expired();case QrStatus_Refused():
return refused();case QrStatus_Success():
return success(_that.user);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  waiting,TResult? Function()?  scanned,TResult? Function()?  expired,TResult? Function()?  refused,TResult? Function( UserInfo user)?  success,}) {final _that = this;
switch (_that) {
case QrStatus_Waiting() when waiting != null:
return waiting();case QrStatus_Scanned() when scanned != null:
return scanned();case QrStatus_Expired() when expired != null:
return expired();case QrStatus_Refused() when refused != null:
return refused();case QrStatus_Success() when success != null:
return success(_that.user);case _:
  return null;

}
}

}

/// @nodoc


class QrStatus_Waiting extends QrStatus {
  const QrStatus_Waiting(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QrStatus_Waiting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QrStatus.waiting()';
}


}




/// @nodoc


class QrStatus_Scanned extends QrStatus {
  const QrStatus_Scanned(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QrStatus_Scanned);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QrStatus.scanned()';
}


}




/// @nodoc


class QrStatus_Expired extends QrStatus {
  const QrStatus_Expired(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QrStatus_Expired);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QrStatus.expired()';
}


}




/// @nodoc


class QrStatus_Refused extends QrStatus {
  const QrStatus_Refused(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QrStatus_Refused);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QrStatus.refused()';
}


}




/// @nodoc


class QrStatus_Success extends QrStatus {
  const QrStatus_Success({required this.user}): super._();
  

 final  UserInfo user;

/// Create a copy of QrStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QrStatus_SuccessCopyWith<QrStatus_Success> get copyWith => _$QrStatus_SuccessCopyWithImpl<QrStatus_Success>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QrStatus_Success&&(identical(other.user, user) || other.user == user));
}


@override
int get hashCode {
    return Object.hash(runtimeType,user);
}

@override
String toString() {
    return 'QrStatus.success(user: $user)';
}


}

/// @nodoc
abstract mixin class $QrStatus_SuccessCopyWith<$Res> implements $QrStatusCopyWith<$Res> {
  factory $QrStatus_SuccessCopyWith(QrStatus_Success value, $Res Function(QrStatus_Success) _then) = _$QrStatus_SuccessCopyWithImpl;
@useResult
$Res call({
 UserInfo user
});




}
/// @nodoc
class _$QrStatus_SuccessCopyWithImpl<$Res>
    implements $QrStatus_SuccessCopyWith<$Res> {
  _$QrStatus_SuccessCopyWithImpl(this._self, this._then);

  final QrStatus_Success _self;
  final $Res Function(QrStatus_Success) _then;

/// Create a copy of QrStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? user = null,}) {
  return _then(QrStatus_Success(
user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as UserInfo,
  ));
}


}

/// @nodoc
mixin _$UpdateEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'UpdateEvent()';
}


}

/// @nodoc
class $UpdateEventCopyWith<$Res>  {
$UpdateEventCopyWith(UpdateEvent _, $Res Function(UpdateEvent) __);
}


/// Adds pattern-matching-related methods to [UpdateEvent].
extension UpdateEventPatterns on UpdateEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UpdateEvent_Connected value)?  connected,TResult Function( UpdateEvent_Progress value)?  progress,TResult Function( UpdateEvent_Done value)?  done,TResult Function( UpdateEvent_Corrupted value)?  corrupted,TResult Function( UpdateEvent_Failed value)?  failed,TResult Function( UpdateEvent_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UpdateEvent_Connected() when connected != null:
return connected(_that);case UpdateEvent_Progress() when progress != null:
return progress(_that);case UpdateEvent_Done() when done != null:
return done(_that);case UpdateEvent_Corrupted() when corrupted != null:
return corrupted(_that);case UpdateEvent_Failed() when failed != null:
return failed(_that);case UpdateEvent_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UpdateEvent_Connected value)  connected,required TResult Function( UpdateEvent_Progress value)  progress,required TResult Function( UpdateEvent_Done value)  done,required TResult Function( UpdateEvent_Corrupted value)  corrupted,required TResult Function( UpdateEvent_Failed value)  failed,required TResult Function( UpdateEvent_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case UpdateEvent_Connected():
return connected(_that);case UpdateEvent_Progress():
return progress(_that);case UpdateEvent_Done():
return done(_that);case UpdateEvent_Corrupted():
return corrupted(_that);case UpdateEvent_Failed():
return failed(_that);case UpdateEvent_Cancelled():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UpdateEvent_Connected value)?  connected,TResult? Function( UpdateEvent_Progress value)?  progress,TResult? Function( UpdateEvent_Done value)?  done,TResult? Function( UpdateEvent_Corrupted value)?  corrupted,TResult? Function( UpdateEvent_Failed value)?  failed,TResult? Function( UpdateEvent_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case UpdateEvent_Connected() when connected != null:
return connected(_that);case UpdateEvent_Progress() when progress != null:
return progress(_that);case UpdateEvent_Done() when done != null:
return done(_that);case UpdateEvent_Corrupted() when corrupted != null:
return corrupted(_that);case UpdateEvent_Failed() when failed != null:
return failed(_that);case UpdateEvent_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String source)?  connected,TResult Function( PlatformInt64 received,  PlatformInt64 total)?  progress,TResult Function()?  done,TResult Function()?  corrupted,TResult Function( ApiError error)?  failed,TResult Function()?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UpdateEvent_Connected() when connected != null:
return connected(_that.source);case UpdateEvent_Progress() when progress != null:
return progress(_that.received,_that.total);case UpdateEvent_Done() when done != null:
return done();case UpdateEvent_Corrupted() when corrupted != null:
return corrupted();case UpdateEvent_Failed() when failed != null:
return failed(_that.error);case UpdateEvent_Cancelled() when cancelled != null:
return cancelled();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String source)  connected,required TResult Function( PlatformInt64 received,  PlatformInt64 total)  progress,required TResult Function()  done,required TResult Function()  corrupted,required TResult Function( ApiError error)  failed,required TResult Function()  cancelled,}) {final _that = this;
switch (_that) {
case UpdateEvent_Connected():
return connected(_that.source);case UpdateEvent_Progress():
return progress(_that.received,_that.total);case UpdateEvent_Done():
return done();case UpdateEvent_Corrupted():
return corrupted();case UpdateEvent_Failed():
return failed(_that.error);case UpdateEvent_Cancelled():
return cancelled();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String source)?  connected,TResult? Function( PlatformInt64 received,  PlatformInt64 total)?  progress,TResult? Function()?  done,TResult? Function()?  corrupted,TResult? Function( ApiError error)?  failed,TResult? Function()?  cancelled,}) {final _that = this;
switch (_that) {
case UpdateEvent_Connected() when connected != null:
return connected(_that.source);case UpdateEvent_Progress() when progress != null:
return progress(_that.received,_that.total);case UpdateEvent_Done() when done != null:
return done();case UpdateEvent_Corrupted() when corrupted != null:
return corrupted();case UpdateEvent_Failed() when failed != null:
return failed(_that.error);case UpdateEvent_Cancelled() when cancelled != null:
return cancelled();case _:
  return null;

}
}

}

/// @nodoc


class UpdateEvent_Connected extends UpdateEvent {
  const UpdateEvent_Connected({required this.source}): super._();
  

 final  String source;

/// Create a copy of UpdateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateEvent_ConnectedCopyWith<UpdateEvent_Connected> get copyWith => _$UpdateEvent_ConnectedCopyWithImpl<UpdateEvent_Connected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateEvent_Connected&&(identical(other.source, source) || other.source == source));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source);
}

@override
String toString() {
    return 'UpdateEvent.connected(source: $source)';
}


}

/// @nodoc
abstract mixin class $UpdateEvent_ConnectedCopyWith<$Res> implements $UpdateEventCopyWith<$Res> {
  factory $UpdateEvent_ConnectedCopyWith(UpdateEvent_Connected value, $Res Function(UpdateEvent_Connected) _then) = _$UpdateEvent_ConnectedCopyWithImpl;
@useResult
$Res call({
 String source
});




}
/// @nodoc
class _$UpdateEvent_ConnectedCopyWithImpl<$Res>
    implements $UpdateEvent_ConnectedCopyWith<$Res> {
  _$UpdateEvent_ConnectedCopyWithImpl(this._self, this._then);

  final UpdateEvent_Connected _self;
  final $Res Function(UpdateEvent_Connected) _then;

/// Create a copy of UpdateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? source = null,}) {
  return _then(UpdateEvent_Connected(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class UpdateEvent_Progress extends UpdateEvent {
  const UpdateEvent_Progress({required this.received, required this.total}): super._();
  

 final  PlatformInt64 received;
 final  PlatformInt64 total;

/// Create a copy of UpdateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateEvent_ProgressCopyWith<UpdateEvent_Progress> get copyWith => _$UpdateEvent_ProgressCopyWithImpl<UpdateEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateEvent_Progress&&(identical(other.received, received) || other.received == received)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,received,total);
}

@override
String toString() {
    return 'UpdateEvent.progress(received: $received, total: $total)';
}


}

/// @nodoc
abstract mixin class $UpdateEvent_ProgressCopyWith<$Res> implements $UpdateEventCopyWith<$Res> {
  factory $UpdateEvent_ProgressCopyWith(UpdateEvent_Progress value, $Res Function(UpdateEvent_Progress) _then) = _$UpdateEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 received, PlatformInt64 total
});




}
/// @nodoc
class _$UpdateEvent_ProgressCopyWithImpl<$Res>
    implements $UpdateEvent_ProgressCopyWith<$Res> {
  _$UpdateEvent_ProgressCopyWithImpl(this._self, this._then);

  final UpdateEvent_Progress _self;
  final $Res Function(UpdateEvent_Progress) _then;

/// Create a copy of UpdateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? received = null,Object? total = null,}) {
  return _then(UpdateEvent_Progress(
received: null == received ? _self.received : received // ignore: cast_nullable_to_non_nullable
as PlatformInt64,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class UpdateEvent_Done extends UpdateEvent {
  const UpdateEvent_Done(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateEvent_Done);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'UpdateEvent.done()';
}


}




/// @nodoc


class UpdateEvent_Corrupted extends UpdateEvent {
  const UpdateEvent_Corrupted(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateEvent_Corrupted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'UpdateEvent.corrupted()';
}


}




/// @nodoc


class UpdateEvent_Failed extends UpdateEvent {
  const UpdateEvent_Failed({required this.error}): super._();
  

 final  ApiError error;

/// Create a copy of UpdateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateEvent_FailedCopyWith<UpdateEvent_Failed> get copyWith => _$UpdateEvent_FailedCopyWithImpl<UpdateEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'UpdateEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $UpdateEvent_FailedCopyWith<$Res> implements $UpdateEventCopyWith<$Res> {
  factory $UpdateEvent_FailedCopyWith(UpdateEvent_Failed value, $Res Function(UpdateEvent_Failed) _then) = _$UpdateEvent_FailedCopyWithImpl;
@useResult
$Res call({
 ApiError error
});


$ApiErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$UpdateEvent_FailedCopyWithImpl<$Res>
    implements $UpdateEvent_FailedCopyWith<$Res> {
  _$UpdateEvent_FailedCopyWithImpl(this._self, this._then);

  final UpdateEvent_Failed _self;
  final $Res Function(UpdateEvent_Failed) _then;

/// Create a copy of UpdateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(UpdateEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ApiError,
  ));
}

/// Create a copy of UpdateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApiErrorCopyWith<$Res> get error {
  
  return $ApiErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class UpdateEvent_Cancelled extends UpdateEvent {
  const UpdateEvent_Cancelled(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateEvent_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'UpdateEvent.cancelled()';
}


}




// dart format on
