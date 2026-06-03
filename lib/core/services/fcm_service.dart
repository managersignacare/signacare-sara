// apps/mobile/lib/core/services/fcm_service.dart
//
// Phase 11B — Sara's FCM + mobile-sync glue.
//
// Three responsibilities, in order:
//
//   1. Initialise Firebase + request notification permission on the
//      first call after login. On iOS this surfaces the system
//      prompt; on Android 13+ it surfaces POST_NOTIFICATIONS. On
//      older platforms the call is a no-op.
//
//   2. Register the FCM device token with the backend via
//      POST /api/v1/mobile/fcm/register-device so the
//      notificationService.emit FCM fan-out (Phase 11A backend) has
//      a token to push to. Called once per login; token rotation
//      is handled via the onTokenRefresh stream.
//
//   3. Handle foreground + opened-from-notification messages.
//      When a push arrives while the app is foreground, FCM delivers
//      it silently by default — flutter_local_notifications renders
//      the banner so the clinician sees the alert without swiping
//      to the OS notification tray. Opening a push (foreground,
//      background, or from-terminated) parses the `action_url`
//      data field and navigates the app there.
//
// Coexistence rule: does NOT touch sync_service_native.dart or the
// existing sqflite offline-write queue. Those are Sara's write-path
// + flush-on-resume logic and are not in Phase 11B scope. This
// service is read-path only (receive pushes, refresh a delta cache).
//
// The FCM token + registration is safe to call repeatedly — the
// backend POST /fcm/register-device resurrects soft-deleted rows
// and upserts by (staff_id, device_token) so re-login doesn't
// create duplicates.
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

final fcmServiceProvider = Provider<FcmService>((ref) => FcmService._());

/// Top-level background handler — FCM requires this to be a top-level
/// or static function (NOT a closure) so it can be called from a
/// fresh isolate when the app is terminated. Keep it small: the
/// message row is durable on the backend, so all this has to do is
/// not crash. Foreground rendering happens in FcmService.initialise.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background isolate: Firebase is re-initialised automatically.
  // The bell row is already in the database (notificationService.emit
  // wrote it BEFORE the FCM dispatch), so the client doesn't need
  // to do anything here — the next foreground sync will pull it.
  debugPrint('[FCM] background message: ${message.messageId} / ${message.notification?.title}');
}

class FcmService {
  FcmService._();

  bool _initialised = false;
  String? _currentToken;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _localNotificationChannelId = 'signacare-alerts';
  static const _localNotificationChannelName = 'Signacare alerts';

  /// Called from the app once the user has logged in. Safe to call
  /// multiple times — idempotent.
  ///
  /// `onNotificationTap` routes deep links from local and FCM
  /// notifications to the Flutter Navigator. `onSyncTrigger` is
  /// called whenever a push arrives (foreground, background-opened,
  /// or cold-start from a tap) so the SyncClient can refresh the
  /// local delta cache in lockstep with the server.
  Future<void> initialise({
    void Function(String? actionUrl)? onNotificationTap,
    void Function()? onSyncTrigger,
  }) async {
    if (_initialised) return;
    // Firebase is a hard dependency on mobile; on web and desktop we
    // skip because the apps ship Flutter native-only builds. Wrap in
    // try/catch so a missing google-services.json in dev doesn't
    // brick the whole app.
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[FCM] Firebase.initializeApp failed (continuing without push): $e');
      _initialised = true;
      return;
    }

    // Permission request. iOS + Android 13+ surface a system prompt;
    // older Android versions grant by default.
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[FCM] permission status: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('[FCM] permission request failed: $e');
    }

    // Local notifications channel (Android). Required for foreground
    // notifications to render — flutter_local_notifications will not
    // show a banner otherwise.
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null) return;
        try {
          final map = json.decode(payload) as Map<String, dynamic>;
          final url = map['action_url'] as String?;
          onNotificationTap?.call(url);
        } catch (_) { /* ignore malformed payload */ }
      },
    );

    if (!kIsWeb && Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _localNotificationChannelId,
        _localNotificationChannelName,
        description: 'Patient-safety + workflow alerts from the Signacare backend',
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    // Background handler — must be registered before any FCM message
    // arrives, so do it in initialise not in a listener.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Foreground messages — render via local notifications +
    // trigger a sync refresh so the bell feed reflects the server.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      onSyncTrigger?.call();
      final title = message.notification?.title ?? 'Notification';
      final body = message.notification?.body ?? '';
      final payload = json.encode(message.data);
      _localNotifications.show(
        message.hashCode,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _localNotificationChannelId,
            _localNotificationChannelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    });

    // Notification tap from background/terminated — also routes
    // through the deep-link callback + triggers a sync pull so the
    // destination screen renders fresh data.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      onSyncTrigger?.call();
      final url = message.data['action_url'] as String?;
      onNotificationTap?.call(url);
    });
    // App cold-launched from a notification.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      onSyncTrigger?.call();
      final url = initialMessage.data['action_url'] as String?;
      onNotificationTap?.call(url);
    }

    _initialised = true;
  }

  /// Register the device token with the backend. Call after login.
  /// Re-registers idempotently on token rotation.
  Future<void> registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      _currentToken = token;
      await _postRegisterToken(token);

      // Re-register on rotation.
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        _currentToken = newToken;
        await _postRegisterToken(newToken);
      });
    } catch (e) {
      debugPrint('[FCM] registerToken failed (continuing without push): $e');
    }
  }

  /// Unregister the current token — call on logout so the backend
  /// stops pushing to a device the user no longer controls.
  Future<void> unregisterToken() async {
    if (_currentToken == null) return;
    try {
      await ApiClient.instance.delete('/mobile/fcm/register-device/${Uri.encodeComponent(_currentToken!)}');
    } catch (e) {
      debugPrint('[FCM] unregisterToken failed: $e');
    }
    _currentToken = null;
  }

  Future<void> _postRegisterToken(String token) async {
    final platform = !kIsWeb && Platform.isIOS ? 'ios' : 'android';
    await ApiClient.instance.post('/mobile/fcm/register-device', data: {
      'deviceToken': token,
      'platform': platform,
    });
  }
}
