// apps/mobile/lib/core/services/sync_client.dart
//
// Phase 11B — Sara's mobile delta sync client.
//
// Hits /api/v1/mobile/sync?since=<cursor> on three triggers:
//
//   1. Post-login bootstrap (alongside FcmService.registerToken).
//   2. FcmService.onForegroundMessage — a push arrived → refresh
//      the delta so the bell UI reflects the server state.
//   3. WidgetsBindingObserver resumed — app foregrounded after
//      being backgrounded; pull whatever arrived while we were
//      gone.
//
// Persists the response as JSON in SharedPreferences under two
// keys:
//   - 'sara_sync_cache_v1'    — the most recent full payload
//   - 'sara_sync_cursor_v1'   — lastSyncAt from the latest response
//
// JSON (not drift) was chosen for Phase 11B because it ships in a
// single file with zero codegen. The payload is small (notifications
// delta, capped 500 rows server-side), renders reactively via a
// ValueNotifier, and works offline. Drift-backed storage is the
// follow-up: a future PR swaps the cache backend without touching
// the SyncClient public surface.
//
// Coexistence rule: does NOT touch sync_service_native.dart or the
// sqflite offline-write queue. Those are Sara's WRITE-path flush
// infrastructure; this is the READ-path delta receiver. Both can
// coexist indefinitely.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'local_reminder_scheduler.dart';

const _kSyncCacheKey = 'sara_sync_cache_v1';
const _kSyncCursorKey = 'sara_sync_cursor_v1';

/// Shape the backend returns from /mobile/sync. Kept permissive
/// (dynamic) so future fields are forward-compatible — the UI
/// reads the list shapes it cares about and ignores the rest.
///
/// Phase 13 PR4 (2026-04-16) adds the three calendar fields that
/// the backend started returning in PR2e: availabilityBlocks,
/// contactRecords, calendarPreferences. Existing Sara UI that
/// doesn't read them keeps working — they're additive.
class SaraSyncSnapshot {
  const SaraSyncSnapshot({
    required this.notifications,
    required this.appointments,
    required this.availabilityBlocks,
    required this.contactRecords,
    required this.calendarPreferences,
    required this.lastSyncAt,
  });

  final List<Map<String, dynamic>> notifications;
  final List<Map<String, dynamic>> appointments;
  // Phase 13 PR4 — calendar surface
  final List<Map<String, dynamic>> availabilityBlocks;
  final List<Map<String, dynamic>> contactRecords;
  final Map<String, dynamic>? calendarPreferences;
  final DateTime lastSyncAt;

  Map<String, dynamic> toJson() => {
        'notifications': notifications,
        'appointments': appointments,
        'availabilityBlocks': availabilityBlocks,
        'contactRecords': contactRecords,
        if (calendarPreferences != null)
          'calendarPreferences': calendarPreferences,
        'lastSyncAt': lastSyncAt.toIso8601String(),
      };

  static SaraSyncSnapshot fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> toList(dynamic v) =>
        ((v as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
    final ts = j['lastSyncAt'] as String?;
    final prefsRaw = j['calendarPreferences'];
    return SaraSyncSnapshot(
      notifications: toList(j['notifications']),
      appointments: toList(j['appointments']),
      availabilityBlocks: toList(j['availabilityBlocks']),
      contactRecords: toList(j['contactRecords']),
      calendarPreferences: prefsRaw is Map
          ? Map<String, dynamic>.from(prefsRaw)
          : null,
      lastSyncAt: ts != null ? DateTime.tryParse(ts) ?? DateTime.now() : DateTime.now(),
    );
  }
}

/// Riverpod singleton.
final syncClientProvider = Provider<SyncClient>((ref) => SyncClient(
      reminderScheduler: ref.read(saraLocalReminderSchedulerProvider),
    ));

class SyncClient {
  SyncClient({required this.reminderScheduler});

  final SaraLocalReminderScheduler reminderScheduler;

  /// ValueNotifier that every UI widget can watch for live updates
  /// after a refresh. The Sara NotificationBell (future PR) reads
  /// `snapshot.value.notifications` directly.
  final ValueNotifier<SaraSyncSnapshot?> snapshot = ValueNotifier<SaraSyncSnapshot?>(null);

  bool _hydrated = false;
  bool _refreshInFlight = false;
  Timer? _periodicTimer;

  /// Load the last-known payload from SharedPreferences into the
  /// notifier so the UI has something to render before the first
  /// network refresh completes. Idempotent.
  Future<void> hydrate() async {
    if (_hydrated) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSyncCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final map = json.decode(raw) as Map<String, dynamic>;
        snapshot.value = SaraSyncSnapshot.fromJson(map);
      }
    } catch (e) {
      debugPrint('[SyncClient] hydrate failed: $e');
    } finally {
      _hydrated = true;
    }
  }

  /// Pull the delta from the backend, merge into the cache, update
  /// the ValueNotifier. Safe to call concurrently — in-flight calls
  /// coalesce so a burst of FCM wake-ups + a manual refresh don't
  /// hammer the server.
  Future<SaraSyncSnapshot?> refresh({bool force = false}) async {
    if (_refreshInFlight && !force) return snapshot.value;
    _refreshInFlight = true;
    try {
      await hydrate();

      // Build the since query from the cached cursor when present;
      // omit it on first run so the backend falls back to its
      // 30-day default lookback.
      final prefs = await SharedPreferences.getInstance();
      final cursor = prefs.getString(_kSyncCursorKey);

      final resp = await ApiClient.instance.get(
        '/mobile/sync',
        params: cursor != null ? {'since': cursor} : null,
      );
      if (resp is! Map) return snapshot.value;

      final map = Map<String, dynamic>.from(resp);
      List<Map<String, dynamic>> toList(dynamic v) =>
          ((v as List?) ?? const [])
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
      final newNotifications = toList(map['notifications']);
      final newAppointments = toList(map['appointments']);
      // Phase 13 PR4 — calendar surface fields. Availability blocks
      // are the full current set (not a delta) so we replace rather
      // than merge. Contact records ARE delta so they merge by id
      // with the existing list. Preferences is a single blob and is
      // simply replaced when present.
      final newAvailabilityBlocks = toList(map['availabilityBlocks']);
      final newContactRecords = toList(map['contactRecords']);
      final newCalendarPreferences = map['calendarPreferences'] is Map
          ? Map<String, dynamic>.from(map['calendarPreferences'] as Map)
          : null;
      final lastSyncAt = (map['lastSyncAt'] as String?) ?? DateTime.now().toIso8601String();

      // Merge by id per entity — delta responses only contain rows
      // newer than the cursor, so we prepend fresh rows to the
      // existing cached list and de-dupe by id. Cap each list at
      // 500 to match the backend's per-entity limit.
      List<Map<String, dynamic>> merge(
          List<Map<String, dynamic>> fresh, List<Map<String, dynamic>> existing) {
        final seen = <String>{};
        final merged = <Map<String, dynamic>>[];
        for (final row in [...fresh, ...existing]) {
          final id = row['id']?.toString();
          if (id == null || seen.contains(id)) continue;
          seen.add(id);
          merged.add(row);
        }
        return merged.length > 500 ? merged.sublist(0, 500) : merged;
      }

      final prev = snapshot.value;
      final fresh = SaraSyncSnapshot(
        notifications: merge(newNotifications, prev?.notifications ?? const []),
        appointments: merge(newAppointments, prev?.appointments ?? const []),
        // Availability blocks: replace (server returns the full
        // current set per CAL-MOBILE-SYNC-BLOCKS comment in
        // mobileSyncRoutes.ts). When the server omits the field
        // (e.g. mid-rollout), preserve the previous list so the
        // calendar UI doesn't blank out.
        availabilityBlocks: newAvailabilityBlocks.isNotEmpty
            ? newAvailabilityBlocks
            : (prev?.availabilityBlocks ?? const []),
        // Contact records: delta-style merge by id, capped at 500.
        contactRecords: merge(newContactRecords, prev?.contactRecords ?? const []),
        // Preferences: take the freshest non-null blob.
        calendarPreferences: newCalendarPreferences ?? prev?.calendarPreferences,
        lastSyncAt: DateTime.tryParse(lastSyncAt) ?? DateTime.now(),
      );
      snapshot.value = fresh;

      // Persist.
      await prefs.setString(_kSyncCacheKey, json.encode(fresh.toJson()));
      await prefs.setString(_kSyncCursorKey, lastSyncAt);

      // Phase 11B — reschedule on-device reminders from the freshly
      // merged appointments list. Non-fatal; the scheduler logs on
      // failure and the next sync cycle will retry.
      // ignore: discarded_futures
      reminderScheduler.rescheduleFromAppointments(fresh.appointments);

      return fresh;
    } catch (e) {
      debugPrint('[SyncClient] refresh failed (continuing with cached data): $e');
      return snapshot.value;
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Start a 60-second periodic refresh loop. Call after login.
  /// Idempotent — cancels any existing timer before starting.
  void startPeriodic() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  /// Stop the periodic loop. Call on logout.
  void stopPeriodic() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Clear the cache + cursor. Call on logout so a subsequent user
  /// on the same device never sees stale data from the previous
  /// session.
  Future<void> clear() async {
    stopPeriodic();
    snapshot.value = null;
    _hydrated = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSyncCacheKey);
      await prefs.remove(_kSyncCursorKey);
    } catch (_) { /* non-fatal */ }
    // Logout cancels any pending on-device reminders so the next
    // clinician on the same device doesn't receive the previous
    // user's alerts.
    try { await reminderScheduler.cancelAll(); } catch (_) { /* non-fatal */ }
  }
}
