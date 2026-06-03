import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kBaseUrlKey = 'signacare_base_url';
const _kDefaultBaseUrl = 'http://localhost:4000/api/v1';
const _kAccessTokenKey = 'access_token';
const _kRefreshTokenKey = 'refresh_token';

/// Token storage that works on both web and native.
/// Web: in-memory (tokens survive until page refresh).
/// Native: FlutterSecureStorage (encrypted keychain).
class _TokenStore {
  // In-memory cache — always works
  final Map<String, String> _mem = {};

  // Native secure storage — only used on iOS/Android
  final FlutterSecureStorage? _secure = kIsWeb
      ? null
      : const FlutterSecureStorage(mOptions: MacOsOptions(useDataProtectionKeyChain: false));

  Future<String?> read(String key) async {
    // Memory first
    if (_mem.containsKey(key)) return _mem[key];
    // Native: try secure storage
    if (_secure != null) {
      try {
        final val = await _secure.read(key: key);
        if (val != null) _mem[key] = val;
        return val;
      } catch (_) {}
    }
    return null;
  }

  Future<void> write(String key, String value) async {
    _mem[key] = value;
    if (_secure != null) {
      try { await _secure.write(key: key, value: value); } catch (_) {}
    }
  }

  Future<void> delete(String key) async {
    _mem.remove(key);
    if (_secure != null) {
      try { await _secure.delete(key: key); } catch (_) {}
    }
  }
}

/// Singleton Dio client pre-configured for the Signacare API.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final _store = _TokenStore();
  late final Dio _dio;
  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    final baseUrl = await _store.read(_kBaseUrlKey) ?? _kDefaultBaseUrl;

    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ));

    // Auth interceptor — injects Bearer token and handles 401 refresh
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _store.read(_kAccessTokenKey);
        if (token != null && token.trim().isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        } else {
          options.headers.remove('Authorization');
        }
        options.headers['X-Client'] = 'mobile';
        handler.next(options);
      },
      onError: (DioException e, handler) async {
        if (e.response?.statusCode == 401) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            final token = await _store.read(_kAccessTokenKey);
            if (token != null && token.trim().isNotEmpty) {
              e.requestOptions.headers['Authorization'] = 'Bearer $token';
            } else {
              e.requestOptions.headers.remove('Authorization');
            }
            final retry = await _dio.fetch(e.requestOptions);
            return handler.resolve(retry);
          }
        }
        handler.next(e);
      },
    ));

    _initialised = true;
  }

  Future<bool> _tryRefresh() async {
    try {
      final refreshToken = await _store.read(_kRefreshTokenKey);
      if (refreshToken == null || refreshToken.trim().isEmpty) return false;
      final resp = await _dio.post('/auth/refresh', data: {'refreshToken': refreshToken});
      final body = Map<String, dynamic>.from(resp.data as Map);
      final nextAccessToken = body['accessToken'] as String?;
      final nextRefreshToken = (body['refreshToken'] as String?) ?? refreshToken;
      if (nextAccessToken == null || nextAccessToken.trim().isEmpty) return false;
      await storeTokens(
        accessToken: nextAccessToken,
        refreshToken: nextRefreshToken,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Auth helpers ──────────────────────────────────────────────────────────

  Future<void> storeTokens({required String accessToken, String? refreshToken}) async {
    await _store.write(_kAccessTokenKey, accessToken);
    final nextRefresh = refreshToken?.trim() ?? '';
    if (nextRefresh.isNotEmpty) {
      await _store.write(_kRefreshTokenKey, nextRefresh);
    } else {
      await _store.delete(_kRefreshTokenKey);
    }
  }

  Future<void> clearTokens() async {
    await _store.delete(_kAccessTokenKey);
    await _store.delete(_kRefreshTokenKey);
  }

  Future<String?> get accessToken => _store.read(_kAccessTokenKey);

  // ── URL config ────────────────────────────────────────────────────────────

  Future<String> getBaseUrl() async =>
      await _store.read(_kBaseUrlKey) ?? _kDefaultBaseUrl;

  Future<void> setBaseUrl(String url) async {
    await _store.write(_kBaseUrlKey, url);
    _dio.options.baseUrl = url;
  }

  // ── HTTP methods ──────────────────────────────────────────────────────────

  Future<dynamic> get(String path, {Map<String, dynamic>? params}) async {
    await init();
    final r = await _dio.get(path, queryParameters: params);
    return r.data;
  }

  Future<dynamic> post(String path, {required Map<String, dynamic> data}) async {
    await init();
    final r = await _dio.post(path, data: data);
    return r.data;
  }

  Future<dynamic> patch(String path, {required Map<String, dynamic> data}) async {
    await init();
    final r = await _dio.patch(path, data: data);
    return r.data;
  }

  Future<dynamic> delete(String path) async {
    await init();
    final r = await _dio.delete(path);
    return r.data;
  }

  /// Login — extracts JWT from response body (mobile) or cookies (native fallback)
  Future<Map<String, dynamic>> login(String email, String password) async {
    await init();
    final r = await _dio.post('/auth/login', data: {'email': email, 'password': password},
        options: Options(headers: {'X-Client': 'mobile'}));

    final body = Map<String, dynamic>.from(r.data);

    // Token from response body (X-Client: mobile triggers this)
    String? accessToken = body['accessToken'] as String?;
    String? refreshToken = body['refreshToken'] as String?;

    // Fallback: cookies (native only — web can't read HttpOnly cookies)
    if (accessToken == null && !kIsWeb) {
      final cookies = r.headers.map['set-cookie'] ?? [];
      for (final c in cookies) {
        final val = c.split(';').first;
        if (val.startsWith('signacare_access=')) {
          accessToken = val.substring('signacare_access='.length);
        } else if (val.startsWith('signacare_refresh=')) {
          refreshToken = val.substring('signacare_refresh='.length);
        }
      }
    }

    if (accessToken != null && accessToken.trim().isNotEmpty) {
      await storeTokens(accessToken: accessToken, refreshToken: refreshToken);
    }

    return body;
  }
}

final api = ApiClient.instance;
