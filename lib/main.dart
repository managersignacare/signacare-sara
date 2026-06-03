import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'core/theme.dart';
import 'core/services/auth_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/sync_client.dart';
import 'core/services/sync_service.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const ProviderScope(child: SignacareApp()));
}

class SignacareApp extends ConsumerStatefulWidget {
  const SignacareApp({super.key});

  @override
  ConsumerState<SignacareApp> createState() => _SignacareAppState();
}

class _SignacareAppState extends ConsumerState<SignacareApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Flush pending offline writes when app comes to foreground
      ref.read(syncServiceProvider).flushPendingWrites();
      // Phase 11B — also pull the latest delta so the bell reflects
      // anything that happened while the app was backgrounded. The
      // SyncClient coalesces concurrent refresh calls so this is
      // safe even if the periodic timer fires at the same instant.
      // ignore: discarded_futures
      ref.read(syncClientProvider).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Phase 11B — when auth transitions to authenticated, initialise
    // FCM, register the device token with the backend, hydrate the
    // local sync cache, and start the 60-second periodic delta
    // poll. On logout, clear the cache + stop the poll so the next
    // user never sees the previous one's data.
    ref.listen<AuthState>(authProvider, (prev, next) {
      final sync = ref.read(syncClientProvider);
      if (!next.isAuthenticated) {
        if (prev?.isAuthenticated == true) {
          // ignore: discarded_futures
          sync.clear();
        }
        return;
      }
      if (prev?.isAuthenticated == true) return;
      final fcm = ref.read(fcmServiceProvider);
      // ignore: discarded_futures
      fcm.initialise(onSyncTrigger: () => sync.refresh()).then((_) async {
        await fcm.registerToken();
        await sync.hydrate();
        await sync.refresh();
        sync.startPeriodic();
      });
    });

    return MaterialApp(
      title: 'Sara by Signacare',
      theme: signacareTheme,
      debugShowCheckedModeBanner: false,
      home: authState.isLoading
          ? const _SplashScreen()
          : authState.isAuthenticated
              ? const HomeScreen()
              : const LoginScreen(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset('assets/signacare-logo.svg', width: 64, height: 64, colorFilter: const ColorFilter.mode(Color(0xFF1565C0), BlendMode.srcIn)),
            const SizedBox(height: 20),
            const Text('Sara', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF1565C0), letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('by Signacare', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kTextLight)),
            const SizedBox(height: 48),
            const CircularProgressIndicator(color: Color(0xFF1565C0), strokeWidth: 2.5),
          ],
        ),
      ),
    );
  }
}
