// apps/mobile/lib/features/calendar/calendar_screen.dart
//
// Phase 13 PR4 — Sara's clinician calendar tab.
//
// Reads everything from the SyncClient ValueNotifier — no new
// network calls. The 60-second periodic refresh in sync_client.dart
// keeps the data warm; the screen is a pure presentation layer
// over snapshot.value.
//
// Layout (mobile-first, vertical stack):
//
//   [ horizontal date strip — 7 days, today highlighted ]
//   ┌─────────────────────────────────────────────────┐
//   │  06:00 ────────────────────────────────────────  │
//   │  07:00 ┐                                          │
//   │        │ green availability bar                   │
//   │  08:00 │  ┌─────────────────────────────┐         │
//   │  09:00 ┘  │ Mr Smith — initial review   │         │
//   │           └─────────────────────────────┘         │
//   │  10:00                                            │
//   │  ...                                              │
//   └─────────────────────────────────────────────────┘
//
//   [ Today summary expansion tiles ]
//     ▸ Appointments (3)
//     ▸ Contacts completed (5)
//     ▸ DNAs (1)
//
// Tapping an appointment opens a read-only detail sheet (Sara is
// read-only for appointments today — booking happens on the web
// app via the shared AppointmentForm dialog from PR5).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/sync_client.dart';
import '../../core/theme.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();

  // 06:00–22:00 hourly grid. Sara renders coarse hour-rows so the
  // grid fits a phone screen without horizontal scroll; the web
  // grid editor is the place for fine slot painting.
  static const int _startHour = 6;
  static const int _endHour = 22;

  @override
  Widget build(BuildContext context) {
    final syncClient = ref.watch(syncClientProvider);

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => syncClient.refresh(force: true),
          ),
        ],
      ),
      body: ValueListenableBuilder<SaraSyncSnapshot?>(
        valueListenable: syncClient.snapshot,
        builder: (context, snap, _) {
          if (snap == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              _DateStrip(
                selected: _selectedDate,
                onSelect: (d) => setState(() => _selectedDate = d),
              ),
              const Divider(height: 1),
              Expanded(
                child: _DayGrid(
                  date: _selectedDate,
                  blocks: snap.availabilityBlocks,
                  appointments: snap.appointments,
                ),
              ),
              const Divider(height: 1),
              _TodaySummary(
                date: _selectedDate,
                appointments: snap.appointments,
                contacts: snap.contactRecords,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Date strip ─────────────────────────────────────────────────────

class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selected, required this.onSelect});

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 3));
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final date = DateTime(start.year, start.month, start.day + i);
          final isSelected = _sameDay(date, selected);
          final isToday = _sameDay(date, today);
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(date),
            child: Container(
              width: 52,
              decoration: BoxDecoration(
                color: isSelected ? kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? kPrimary : kDivider,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _weekdayLabels[(date.weekday - 1) % 7],
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? Colors.white : kTextLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? Colors.white
                          : (isToday ? kPrimary : kText),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Day grid ──────────────────────────────────────────────────────

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.date,
    required this.blocks,
    required this.appointments,
  });

  final DateTime date;
  final List<Map<String, dynamic>> blocks;
  final List<Map<String, dynamic>> appointments;

  @override
  Widget build(BuildContext context) {
    final dayBlocks = _filterBlocksForDate(blocks, date);
    final dayAppointments = _filterAppointmentsForDate(appointments, date);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: _CalendarScreenState._endHour - _CalendarScreenState._startHour,
      itemBuilder: (context, i) {
        final hour = _CalendarScreenState._startHour + i;
        final hourBlocks = dayBlocks.where((b) {
          final s = _parseClockHour(b['startTime'] as String?);
          final e = _parseClockHour(b['endTime'] as String?);
          return s != null && e != null && s <= hour && e > hour;
        }).toList();
        final hourAppointments = dayAppointments.where((a) {
          final start = _parseDateTime(a['startTime'] ?? a['appointment_start']);
          return start != null && start.hour == hour;
        }).toList();

        return _HourRow(
          hour: hour,
          blocks: hourBlocks,
          appointments: hourAppointments,
        );
      },
    );
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow({
    required this.hour,
    required this.blocks,
    required this.appointments,
  });

  final int hour;
  final List<Map<String, dynamic>> blocks;
  final List<Map<String, dynamic>> appointments;

  Color _bgForBlocks() {
    if (blocks.isEmpty) return Colors.transparent;
    // Highest-severity colour wins (red > yellow > green) so the
    // clinician's eye lands on the unavailable bands first.
    if (blocks.any((b) => b['colour'] == 'red')) {
      return Colors.red.withOpacity(0.16);
    }
    if (blocks.any((b) => b['colour'] == 'yellow')) {
      return Colors.amber.withOpacity(0.18);
    }
    return Colors.green.withOpacity(0.16);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bgForBlocks(),
        border: const Border(bottom: BorderSide(color: kDivider, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              '${hour.toString().padLeft(2, '0')}:00',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kTextLight,
              ),
            ),
          ),
          Expanded(
            child: appointments.isEmpty
                ? const SizedBox(height: 32)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: appointments
                        .map((a) => _AppointmentCard(data: a))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final start = _parseDateTime(data['startTime'] ?? data['appointment_start']);
    final end = _parseDateTime(data['endTime'] ?? data['appointment_end']);
    final type = (data['type'] ?? data['appointment_type'] ?? 'follow up') as String;
    final status = (data['status'] ?? 'scheduled') as String;
    final patientName = (data['patientName'] ?? '') as String;
    final isDna = status == 'no_show';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDna ? kError.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDna ? kError.withOpacity(0.3) : kPrimary.withOpacity(0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _formatRange(start, end),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kText,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _statusColour(status).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 10,
                    color: _statusColour(status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            patientName.isEmpty ? type : patientName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kText,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Today summary ──────────────────────────────────────────────────

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({
    required this.date,
    required this.appointments,
    required this.contacts,
  });

  final DateTime date;
  final List<Map<String, dynamic>> appointments;
  final List<Map<String, dynamic>> contacts;

  @override
  Widget build(BuildContext context) {
    final dayApts = _filterAppointmentsForDate(appointments, date);
    final dnas = dayApts.where((a) => a['status'] == 'no_show').toList();
    final activeApts = dayApts.where((a) => a['status'] != 'no_show').toList();
    final dayContacts = contacts.where((c) {
      final cd = (c['contact_date'] ?? c['contactDate']) as String?;
      if (cd == null || cd.length < 10) return false;
      return cd.substring(0, 10) == _formatIsoDate(date);
    }).toList();

    return Material(
      color: Colors.white,
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          'Today summary',
          style: const TextStyle(fontWeight: FontWeight.w700, color: kText),
        ),
        children: [
          _SummaryRow(
            icon: Icons.event_available,
            label: 'Appointments',
            count: activeApts.length,
            colour: kInfo,
          ),
          _SummaryRow(
            icon: Icons.assignment_turned_in_outlined,
            label: 'Contacts completed',
            count: dayContacts.length,
            colour: kSuccess,
          ),
          _SummaryRow(
            icon: Icons.event_busy,
            label: 'Did not attend',
            count: dnas.length,
            colour: kError,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.colour,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: colour),
      title: Text(label, style: const TextStyle(color: kText)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colour.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            color: colour,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _formatIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDateTime(dynamic v) {
  if (v is String) return DateTime.tryParse(v);
  return null;
}

int? _parseClockHour(String? clock) {
  if (clock == null || clock.length < 2) return null;
  return int.tryParse(clock.substring(0, 2));
}

String _formatRange(DateTime? start, DateTime? end) {
  if (start == null || end == null) return '';
  String fmt(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return '${fmt(start)} – ${fmt(end)}';
}

Color _statusColour(String status) {
  switch (status) {
    case 'completed':
      return kSuccess;
    case 'arrived':
    case 'in_session':
      return kInfo;
    case 'cancelled':
      return kWarning;
    case 'no_show':
      return kError;
    default:
      return kTextLight;
  }
}

List<Map<String, dynamic>> _filterBlocksForDate(
  List<Map<String, dynamic>> blocks,
  DateTime date,
) {
  // Sara only renders weekly recurring blocks from the synced set
  // — the backend ships the current week's grid via PR2e, so a
  // weekly block whose dayOfWeek matches the selected date applies.
  // One-off (recurrence='none') blocks are matched by specificDate.
  final isoDate = _formatIsoDate(date);
  // Postgres day_of_week: 0 = Sunday, 6 = Saturday.
  final pgDow = date.weekday % 7;
  return blocks.where((b) {
    final recurrence = b['recurrence'] as String?;
    if (recurrence == 'weekly') {
      return (b['dayOfWeek'] as num?)?.toInt() == pgDow;
    }
    if (recurrence == 'none') {
      return (b['specificDate'] as String?) == isoDate;
    }
    return false;
  }).toList();
}

List<Map<String, dynamic>> _filterAppointmentsForDate(
  List<Map<String, dynamic>> appointments,
  DateTime date,
) {
  final isoDate = _formatIsoDate(date);
  return appointments.where((a) {
    final s = a['startTime'] ?? a['appointment_start'];
    if (s is String && s.length >= 10) {
      return s.substring(0, 10) == isoDate;
    }
    return false;
  }).toList();
}
