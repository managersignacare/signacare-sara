import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/api/api_client.dart';
import '../home/home_screen.dart';
import 'mfa_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePass = true;
  bool _showUrlConfig = false;

  @override
  void initState() {
    super.initState();
    api.getBaseUrl().then((url) => _urlCtrl.text = url);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    // Use authProvider which handles login + token storage + state
    final notifier = ref.read(authProvider.notifier);

    // First call login to check MFA
    try {
      final data = await api.login(email, password);
      if (data['requiresMfa'] == true) {
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MfaScreen(tempToken: data['tempToken'] as String? ?? ''),
          ));
        }
        return;
      }
      // Login succeeded — extract user from response (tokens already stored by api.login)
      final accessToken = await api.accessToken ?? (data['accessToken'] as String? ?? '');
      final userData = (data['user'] as Map<String, dynamic>?) ?? data;
      final user = AuthUser.fromJson(Map<String, dynamic>.from(userData), accessToken);
      notifier.setUser(user);
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } catch (e) {
      // Show error via auth state
      final ok = await notifier.login(email, password);
      if (ok && mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    }
  }

  Future<void> _saveUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isNotEmpty) {
      await api.setBaseUrl(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server URL updated to $url'), backgroundColor: kSuccess));
      }
    }
    setState(() => _showUrlConfig = false);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: kSurface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                // Logo
                Center(child: SvgPicture.asset('assets/signacare-logo.svg', width: 56, height: 56, colorFilter: const ColorFilter.mode(Color(0xFF1565C0), BlendMode.srcIn))),
                const SizedBox(height: 16),
                const Center(
                  child: Text('Sara', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1565C0), letterSpacing: -0.5)),
                ),
                Center(
                  child: Text('by Signacare', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextLight)),
                ),
                const SizedBox(height: 48),

                // Email
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined, size: 20),
                  ),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 14),

                // Password
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 4) ? 'Enter your password' : null,
                ),
                const SizedBox(height: 8),

                // Error message
                if (authState.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: kError.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: kError, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(authState.error!, style: const TextStyle(color: kError, fontSize: 13))),
                      ]),
                    ),
                  ),

                const SizedBox(height: 20),

                // Login button
                ElevatedButton(
                  onPressed: authState.isLoading ? null : _login,
                  child: authState.isLoading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Sign In'),
                ),
                const SizedBox(height: 24),

                // Server URL config (for LAN / local hosting)
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showUrlConfig = !_showUrlConfig),
                    icon: Icon(_showUrlConfig ? Icons.expand_less : Icons.settings_ethernet, size: 18, color: kTextLight),
                    label: Text(_showUrlConfig ? 'Hide server config' : 'Configure server URL',
                        style: const TextStyle(color: kTextLight, fontSize: 13)),
                  ),
                ),

                if (_showUrlConfig) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kDivider),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Server API URL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextLight)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _urlCtrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          hintText: 'http://192.168.1.x:4000/api/v1',
                          helperText: 'For local network access use your server\'s LAN IP',
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _saveUrl,
                        style: ElevatedButton.styleFrom(backgroundColor: kInfo, minimumSize: const Size.fromHeight(40)),
                        child: const Text('Save URL'),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
