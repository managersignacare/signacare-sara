import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/services/auth_service.dart';
import '../home/home_screen.dart';

/// MFA verification screen — shown after login when requiresMfa is true.
class MfaScreen extends ConsumerStatefulWidget {
  final String tempToken;
  const MfaScreen({super.key, required this.tempToken});

  @override
  ConsumerState<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends ConsumerState<MfaScreen> {
  final List<TextEditingController> _digitCtrls = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _digitCtrls) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    super.dispose();
  }

  String get _code => _digitCtrls.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    // Auto-submit when all 6 digits entered
    if (_code.length == 6) {
      _verify();
    }
  }

  Future<void> _verify() async {
    final code = _code;
    if (code.length != 6) {
      setState(() => _error = 'Enter all 6 digits');
      return;
    }
    setState(() { _verifying = true; _error = null; });
    try {
      final data = await api.post('/auth/mfa/verify', data: {
        'tempToken': widget.tempToken,
        'token': code,
      });
      final result = Map<String, dynamic>.from(data as Map);
      final accessTokenFromBody = (result['accessToken'] as String?)?.trim();
      final refreshTokenFromBody = result['refreshToken'] as String?;
      if (accessTokenFromBody != null && accessTokenFromBody.isNotEmpty) {
        await api.storeTokens(
          accessToken: accessTokenFromBody,
          refreshToken: refreshTokenFromBody,
        );
      }
      final accessToken = await api.accessToken ?? accessTokenFromBody ?? '';
      if (accessToken.isEmpty) {
        throw Exception('Missing access token after MFA verification');
      }
      final userData = (result['user'] as Map<String, dynamic>?) ?? result;
      final user = AuthUser.fromJson(Map<String, dynamic>.from(userData), accessToken);
      ref.read(authProvider.notifier).setUser(user);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      setState(() {
        _verifying = false;
        _error = 'Invalid code. Please try again.';
      });
      // Clear fields on error
      for (final c in _digitCtrls) { c.clear(); }
      _focusNodes[0].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Verify Identity'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: kInfo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.security_rounded, color: kInfo, size: 32),
              ),
              const SizedBox(height: 20),
              const Text('Two-Factor Authentication', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kText)),
              const SizedBox(height: 8),
              const Text(
                'Enter the 6-digit code from your authenticator app',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: kTextLight),
              ),
              const SizedBox(height: 32),

              // 6-digit code input
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) => Container(
                  width: 44, height: 52,
                  margin: EdgeInsets.only(left: i > 0 ? 8 : 0, right: i == 2 ? 8 : 0),
                  child: TextField(
                    controller: _digitCtrls[i],
                    focusNode: _focusNodes[i],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kText),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kPrimary, width: 2),
                      ),
                    ),
                    onChanged: (v) => _onDigitChanged(i, v),
                  ),
                )),
              ),
              const SizedBox(height: 16),

              if (_error != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: kError.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: kError, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: kError, fontSize: 13))),
                  ]),
                ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _verifying ? null : _verify,
                  child: _verifying
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Verify'),
                ),
              ),

              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to Login', style: TextStyle(color: kTextLight, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
