import '../data/song_json.dart';
import '../src/rust/api/error.dart';
import 'player_error.dart';

List<Object?> encodePlaybackException(Object error) => switch (error) {
  ApiError_NotLoggedIn() => ['notLoggedIn'],
  ApiError_NoPlayableUrl() => ['noPlayableUrl'],
  ApiError_UnsupportedFormat() => ['unsupportedFormat'],
  ApiError_UnverifiedFormat() => ['unverifiedFormat'],
  ApiError_LoginFailed(:final detail) => ['loginFailed', detail],
  ApiError_InvalidCookie(:final missing) => ['invalidCookie', missing],
  ApiError_ServerError(:final api, :final code) => ['serverError', api, code],
  ApiError_BadResponse(:final detail) => ['badResponse', detail],
  ApiError_Network(:final detail) => ['network', detail],
  ApiError_Internal(:final detail) => ['internal', detail],
  _ => ['message', error.toString()],
};

Object decodePlaybackException(Object? value) => switch (value) {
  ['notLoggedIn'] => const ApiError.notLoggedIn(),
  ['noPlayableUrl'] => const ApiError.noPlayableUrl(),
  ['unsupportedFormat'] => const ApiError.unsupportedFormat(),
  ['unverifiedFormat'] => const ApiError.unverifiedFormat(),
  ['loginFailed', String detail] => ApiError.loginFailed(detail: detail),
  ['invalidCookie', String missing] => ApiError.invalidCookie(missing: missing),
  ['serverError', String api, String code] => ApiError.serverError(
    api: api,
    code: code,
  ),
  ['badResponse', String detail] => ApiError.badResponse(detail: detail),
  ['network', String detail] => ApiError.network(detail: detail),
  ['internal', String detail] => ApiError.internal(detail: detail),
  ['message', String message] => message,
  _ => StateError('Invalid playback error'),
};

Object? encodePlayerError(PlayerError? error) => switch (error) {
  PlaybackFailed(:final song, :final cause) => [
    songToJson(song),
    encodePlaybackException(cause),
  ],
  StreamFailed(:final message) => message,
  null => null,
};

PlayerError? decodePlayerError(Object? value) => switch (value) {
  [Map<String, dynamic> song, final cause] => PlaybackFailed(
    songFromJson(song),
    decodePlaybackException(cause),
  ),
  String message => StreamFailed(message),
  _ => null,
};
