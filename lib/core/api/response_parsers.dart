import 'package:dio/dio.dart';

const _defaultEnvelopeKeys = <String>[
  'data',
  'items',
  'rows',
  'episodes',
  'notes',
  'contacts',
  'providers',
  'alerts',
];

List<dynamic> readListEnvelope(
  dynamic payload, {
  List<String> preferredKeys = const <String>[],
}) {
  if (payload is List) return payload;
  if (payload is Map) {
    final map = Map<String, dynamic>.from(payload);
    for (final key in [...preferredKeys, ..._defaultEnvelopeKeys]) {
      final candidate = map[key];
      if (candidate is List) return candidate;
    }
  }
  throw const FormatException('API response did not contain a list payload.');
}

List<Map<String, dynamic>> readMapListEnvelope(
  dynamic payload, {
  List<String> preferredKeys = const <String>[],
}) {
  final list = readListEnvelope(payload, preferredKeys: preferredKeys);
  return list
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

Map<String, dynamic> readMapEnvelope(
  dynamic payload, {
  List<String> preferredKeys = const <String>[],
}) {
  if (payload is Map) {
    final map = Map<String, dynamic>.from(payload);
    for (final key in preferredKeys) {
      final candidate = map[key];
      if (candidate is Map) {
        return Map<String, dynamic>.from(candidate);
      }
    }
    return map;
  }
  throw const FormatException('API response did not contain an object payload.');
}

String readApiErrorMessage(
  Object error, {
  String fallback = 'Unable to load data.',
}) {
  if (error is DioException) {
    final body = error.response?.data;
    if (body is Map) {
      final asMap = Map<String, dynamic>.from(body);
      final message = asMap['message'] ?? asMap['error'] ?? asMap['code'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }
    if (error.message != null && error.message!.trim().isNotEmpty) {
      return error.message!;
    }
  }
  final text = error.toString().trim();
  if (text.isEmpty) return fallback;
  return text;
}
