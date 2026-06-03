// apps/mobile/lib/core/services/local_reminder_scheduler.dart
//
// Phase 11B — Sara's on-device reminder scheduler.
//
// Reads the `appointments` slice of the latest SaraSyncSnapshot and
// uses flutter_local_notifications to schedule pre-appointment alerts
// without a server round-trip at fire time. Two offsets by default:
// 24h before and 1h before each future appointment. The scheduler is
// idempotent across syncs — every call cancels previously-scheduled
// Sara reminders and re-schedules from the fresh snapshot.
//
// Mirror of apps/patient-app/.../local_reminder_scheduler.dart with
// different notification channel id and text so the clinician UI
// stays distinct from the patient UI.
//
// Coexistence rule: does NOT replace the FCM foreground-notification
// path in fcm_service.dart. That renders push-originated alerts;
// this schedules reminders the device fires on its own clock.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final saraLocalReminderSchedulerProvider =
    Provider<SaraLocalReminderScheduler>((ref) => SaraLocalReminderScheduler._());

class SaraLocalReminderScheduler {
  SaraLocalReminderScheduler._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'signacare-alerts';
  static const _channelName = 'Signacare alerts';

  static const int _idSalt24h = 0xaa550002;
  static const int _idSalt1h = 0xaa550003;

  int _idFor(String appointmentId, int salt) =>
      (appointmentId.hashCode ^ salt) & 0x7fffffff;

  Future<void> rescheduleFromAppointments(List<Map<String, dynamic>> appointments) async {
    try {
      await _plugin.cancelAll();
      final now = DateTime.now();
      for (final row in appointments) {
        final id = row['id']?.toString();
        if (id == null) continue;
        if (row['deleted_at'] != null) continue;
        final startRaw = row['start_time']?.toString();
        if (startRaw == null) continue;
        final start = DateTime.tryParse(startRaw);
        if (start == null || start.isBefore(now)) continue;

        final apptType = (row['appointment_type'] as String?) ?? 'Appointment';
        final location = (row['location'] as String?) ?? '';
        final title = 'Upcoming $apptType';
        final body = location.isEmpty
            ? '$apptType at ${_formatTime(start)}'
            : '$apptType at ${_formatTime(start)} — $location';

        final t24h = start.subtract(const Duration(hours: 24));
        if (t24h.isAfter(now)) {
          await _scheduleAt(_idFor(id, _idSalt24h), 'Appointment tomorrow', body, t24h);
        }
        final t1h = start.subtract(const Duration(hours: 1));
        if (t1h.isAfter(now)) {
          await _scheduleAt(_idFor(id, _idSalt1h), title, body, t1h);
        }
      }
    } catch (e) {
      debugPrint('[SaraLocalReminderScheduler] reschedule failed: $e');
    }
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('[SaraLocalReminderScheduler] cancelAll failed: $e');
    }
  }

  Future<void> _scheduleAt(int id, String title, String body, DateTime when) async {
    final delta = when.difference(DateTime.now());
    if (delta.isNegative) return;
    Timer(delta, () async {
      try {
        await _plugin.show(
          id,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      } catch (e) {
        debugPrint('[SaraLocalReminderScheduler] fire failed for $id: $e');
      }
    });
  }

  String _formatTime(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
