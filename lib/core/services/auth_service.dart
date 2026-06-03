import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';

class AuthUser {
  final String id;
  final String email;
  final String? givenName;
  final String? familyName;
  final String? role;
  final String accessToken;

  const AuthUser({
    required this.id,
    required this.email,
    this.givenName,
    this.familyName,
    this.role,
    required this.accessToken,
  });

  String get displayName => [givenName, familyName].where((s) => s != null && s.isNotEmpty).join(' ');

  factory AuthUser.fromJson(Map<String, dynamic> j, String token) => AuthUser(
    id: j['id'] as String,
    email: j['email'] as String,
    givenName: j['givenName'] as String?,
    familyName: j['familyName'] as String?,
    role: j['role'] as String?,
    accessToken: token,
  );
}

class AuthState {
  final AuthUser? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isAuthenticated => user != null;
  AuthState copyWith({AuthUser? user, bool? isLoading, String? error}) =>
      AuthState(user: user ?? this.user, isLoading: isLoading ?? this.isLoading, error: error ?? this.error);
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState(isLoading: true)) {
    _checkStoredToken();
  }

  Future<void> _checkStoredToken() async {
    try {
      final token = await api.accessToken;
      if (token != null) {
        // Validate token by calling /auth/me
        final data = await api.get('/auth/me');
        final user = AuthUser.fromJson(Map<String, dynamic>.from(data as Map), token);
        state = AuthState(user: user);
      } else {
        state = const AuthState();
      }
    } catch (_) {
      state = const AuthState();
    }
  }

  Future<bool> login(String email, String password) async {
    state = const AuthState(isLoading: true);
    try {
      final data = await api.login(email, password);
      // Tokens are extracted from cookies inside api.login() — retrieve from storage
      final accessToken = await api.accessToken ?? (data['accessToken'] as String? ?? '');
      final userData = (data['user'] as Map<String, dynamic>?) ?? data;
      final user = AuthUser.fromJson(Map<String, dynamic>.from(userData), accessToken);
      state = AuthState(user: user);
      return true;
    } catch (e) {
      state = AuthState(error: _parseError(e));
      return false;
    }
  }

  /// Called by MFA screen after successful verification
  void setUser(AuthUser user) {
    state = AuthState(user: user);
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout', data: {});
    } catch (_) {}
    await api.clearTokens();
    state = const AuthState();
  }

  String _parseError(dynamic e) {
    if (e is Exception) {
      final msg = e.toString();
      if (msg.contains('401') || msg.contains('Invalid')) return 'Invalid email or password';
      if (msg.contains('SocketException') || msg.contains('connection')) return 'Cannot reach server — check network or server URL';
    }
    return 'Login failed. Please try again.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((_) => AuthNotifier());
