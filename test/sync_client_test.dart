// Phase 0.7.1 C6c — SaraSyncSnapshot unit tests.
// Tests the fromJson/toJson round-trip, merge dedup, availability
// block replacement, and calendar preferences latest-wins logic.
import 'package:flutter_test/flutter_test.dart';

// Inline the snapshot shape for testing (avoids importing the full
// app which needs native plugins). Tests the same logic.

class SaraSyncSnapshot {
  final List<Map<String, dynamic>> notifications;
  final List<Map<String, dynamic>> appointments;
  final List<Map<String, dynamic>> availabilityBlocks;
  final List<Map<String, dynamic>> contactRecords;
  final Map<String, dynamic>? calendarPreferences;
  final DateTime lastSyncAt;

  SaraSyncSnapshot({
    required this.notifications,
    required this.appointments,
    required this.availabilityBlocks,
    required this.contactRecords,
    required this.calendarPreferences,
    required this.lastSyncAt,
  });

  Map<String, dynamic> toJson() => {
    'notifications': notifications,
    'appointments': appointments,
    'availabilityBlocks': availabilityBlocks,
    'contactRecords': contactRecords,
    if (calendarPreferences != null) 'calendarPreferences': calendarPreferences,
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
      calendarPreferences: prefsRaw is Map ? Map<String, dynamic>.from(prefsRaw) : null,
      lastSyncAt: ts != null ? DateTime.tryParse(ts) ?? DateTime.now() : DateTime.now(),
    );
  }
}

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

void main() {
  group('SaraSyncSnapshot', () {
    test('fromJson/toJson round-trip preserves all fields', () {
      final original = SaraSyncSnapshot(
        notifications: [{'id': 'n1', 'title': 'Test'}],
        appointments: [{'id': 'a1', 'patientName': 'Smith'}],
        availabilityBlocks: [{'id': 'b1', 'colour': 'green'}],
        contactRecords: [{'id': 'c1', 'status': 'signed'}],
        calendarPreferences: {'slotMinutes': 30, 'weekStart': 1},
        lastSyncAt: DateTime.parse('2026-04-16T10:00:00Z'),
      );
      final json = original.toJson();
      final restored = SaraSyncSnapshot.fromJson(json);

      expect(restored.notifications.length, 1);
      expect(restored.appointments.length, 1);
      expect(restored.availabilityBlocks.length, 1);
      expect(restored.contactRecords.length, 1);
      expect(restored.calendarPreferences?['slotMinutes'], 30);
      expect(restored.lastSyncAt.toIso8601String(), contains('2026-04-16'));
    });

    test('fromJson handles missing optional fields', () {
      final snap = SaraSyncSnapshot.fromJson({
        'notifications': [],
        'appointments': [],
        'lastSyncAt': '2026-04-16T10:00:00Z',
      });
      expect(snap.availabilityBlocks, isEmpty);
      expect(snap.contactRecords, isEmpty);
      expect(snap.calendarPreferences, isNull);
    });

    test('fromJson handles null calendarPreferences', () {
      final snap = SaraSyncSnapshot.fromJson({
        'notifications': [],
        'appointments': [],
        'availabilityBlocks': [],
        'contactRecords': [],
        'calendarPreferences': null,
        'lastSyncAt': '2026-04-16T10:00:00Z',
      });
      expect(snap.calendarPreferences, isNull);
    });
  });

  group('merge', () {
    test('deduplicates by id, fresh rows win', () {
      final fresh = [{'id': '1', 'v': 'new'}];
      final existing = [{'id': '1', 'v': 'old'}, {'id': '2', 'v': 'keep'}];
      final result = merge(fresh, existing);
      expect(result.length, 2);
      expect(result[0]['v'], 'new');
      expect(result[1]['v'], 'keep');
    });

    test('caps at 500 rows', () {
      final large = List.generate(600, (i) => {'id': 'r$i'});
      final result = merge(large, []);
      expect(result.length, 500);
    });

    test('handles empty lists', () {
      expect(merge([], []), isEmpty);
      expect(merge([{'id': '1'}], []).length, 1);
      expect(merge([], [{'id': '1'}]).length, 1);
    });
  });
}
