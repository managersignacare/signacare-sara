import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../core/models/note.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/response_parsers.dart';

final _alertsPlansProvider =
    FutureProvider.family<_AlertsData, String>((ref, patientId) async {
  final notes = await ref.read(syncServiceProvider).fetchNotes(patientId);
  final alerts = notes
      .where((n) =>
          n.noteType == 'incident' ||
          n.noteType == 'alert' ||
          n.noteType == 'risk')
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  final plans = notes
      .where((n) =>
          n.noteType == 'care_plan' ||
          n.noteType == 'safety_plan' ||
          n.noteType == 'treatment_plan' ||
          n.noteType == 'advance_directive' ||
          n.noteType == 'recovery_plan')
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  // Also fetch clinical alerts from patient flags.
  final data = await api.get('/patients/$patientId/alerts');
  final list = readMapListEnvelope(
    data,
    preferredKeys: const ['alerts', 'data'],
  );
  final apiAlerts = list.map(_ClinicalAlert.fromJson).toList();

  return _AlertsData(
      notesAlerts: alerts, plansNotes: plans, apiAlerts: apiAlerts);
});

class _AlertsData {
  final List<Note> notesAlerts;
  final List<Note> plansNotes;
  final List<_ClinicalAlert> apiAlerts;
  const _AlertsData(
      {required this.notesAlerts,
      required this.plansNotes,
      required this.apiAlerts});
}

class _ClinicalAlert {
  final String id;
  final String type;
  final String description;
  final String severity;
  const _ClinicalAlert(
      {required this.id,
      required this.type,
      required this.description,
      required this.severity});

  factory _ClinicalAlert.fromJson(Map<String, dynamic> j) => _ClinicalAlert(
        id: j['id']?.toString() ?? '',
        type: j['type']?.toString() ?? 'alert',
        description: j['description']?.toString() ?? '',
        severity: j['severity']?.toString() ?? 'medium',
      );
}

class AlertsPlansTab extends ConsumerStatefulWidget {
  final String patientId;
  const AlertsPlansTab({super.key, required this.patientId});

  @override
  ConsumerState<AlertsPlansTab> createState() => _AlertsPlansTabState();
}

class _AlertsPlansTabState extends ConsumerState<AlertsPlansTab>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  late final TabController _innerTab;

  @override
  void initState() {
    super.initState();
    _innerTab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _innerTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dataAsync = ref.watch(_alertsPlansProvider(widget.patientId));

    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _innerTab,
            tabs: const [Tab(text: 'Alerts'), Tab(text: 'Plans')],
            labelColor: kPrimary,
            unselectedLabelColor: kTextLight,
            indicatorColor: kPrimary,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        Expanded(
          child: dataAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: kPrimary)),
            error: (_, __) => const Center(
                child: Text('Unable to load data',
                    style: TextStyle(color: kTextLight))),
            data: (data) => TabBarView(
              controller: _innerTab,
              children: [
                _AlertsView(data: data),
                _PlansView(data: data),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Alerts view ──────────────────────────────────────────────────────────────

class _AlertsView extends StatelessWidget {
  final _AlertsData data;
  const _AlertsView({required this.data});

  @override
  Widget build(BuildContext context) {
    final hasContent = data.apiAlerts.isNotEmpty || data.notesAlerts.isNotEmpty;

    if (!hasContent) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_outline, color: kSuccess, size: 48),
          SizedBox(height: 12),
          Text('No active alerts',
              style: TextStyle(color: kTextLight, fontSize: 14)),
          SizedBox(height: 4),
          Text('Alerts and risk flags will appear here',
              style: TextStyle(color: kTextLight, fontSize: 12)),
        ]),
      );
    }

    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (data.apiAlerts.isNotEmpty) ...[
            _SectionLabel('Clinical Flags'),
            const SizedBox(height: 6),
            ...data.apiAlerts.map((a) => _AlertCard(alert: a)),
            const SizedBox(height: 16),
          ],
          if (data.notesAlerts.isNotEmpty) ...[
            _SectionLabel('Incident Notes'),
            const SizedBox(height: 6),
            ...data.notesAlerts.map((n) => _IncidentNoteCard(note: n)),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final _ClinicalAlert alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(alert.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(children: [
        Icon(_severityIcon(alert.severity), color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(alert.type,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 3),
          Text(alert.description,
              style: const TextStyle(fontSize: 12, color: kText)),
        ])),
        _SeverityBadge(alert.severity),
      ]),
    );
  }

  Color _severityColor(String s) {
    switch (s.toLowerCase()) {
      case 'high':
      case 'critical':
        return kError;
      case 'medium':
        return kWarning;
      default:
        return kInfo;
    }
  }

  IconData _severityIcon(String s) {
    switch (s.toLowerCase()) {
      case 'high':
      case 'critical':
        return Icons.warning_amber_rounded;
      case 'medium':
        return Icons.info_outline;
      default:
        return Icons.flag_outlined;
    }
  }
}

class _SeverityBadge extends StatelessWidget {
  final String severity;
  const _SeverityBadge(this.severity);

  @override
  Widget build(BuildContext context) {
    final color =
        severity.toLowerCase() == 'high' || severity.toLowerCase() == 'critical'
            ? kError
            : severity.toLowerCase() == 'medium'
                ? kWarning
                : kInfo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10)),
      child: Text(severity.toUpperCase(),
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _IncidentNoteCard extends StatefulWidget {
  final Note note;
  const _IncidentNoteCard({required this.note});

  @override
  State<_IncidentNoteCard> createState() => _IncidentNoteCardState();
}

class _IncidentNoteCardState extends State<_IncidentNoteCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    final dateStr = DateFormat('d MMM y').format(n.createdAt.toLocal());
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _expanded ? kError : kDivider),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: kError),
            Expanded(
                child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(n.title.isNotEmpty ? n.title : 'Incident',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: kText))),
                      Text(dateStr, style: SignacareText.caption),
                      const SizedBox(width: 6),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                          color: kTextLight, size: 18),
                    ]),
                    if (_expanded && n.content.isNotEmpty) ...[
                      const Divider(height: 12),
                      Text(n.content,
                          style: const TextStyle(
                              fontSize: 12, color: kText, height: 1.4)),
                    ],
                  ]),
            )),
          ]),
        ),
      ),
    );
  }
}

// ── Plans view ───────────────────────────────────────────────────────────────

class _PlansView extends StatelessWidget {
  final _AlertsData data;
  const _PlansView({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.plansNotes.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.assignment_outlined, color: kTextLight, size: 48),
          const SizedBox(height: 12),
          const Text('No care plans recorded',
              style: TextStyle(color: kTextLight, fontSize: 14)),
          const SizedBox(height: 4),
          Text('Write a note with type "Care Plan" or "Safety Plan"',
              style: SignacareText.caption, textAlign: TextAlign.center),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...data.plansNotes.map((n) => _PlanCard(note: n)),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _PlanCard extends StatefulWidget {
  final Note note;
  const _PlanCard({required this.note});

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _expanded = false;

  static const _planColors = {
    'care_plan': Color(0xFF0288D1),
    'safety_plan': Color(0xFFD32F2F),
    'treatment_plan': Color(0xFF2E7D32),
    'advance_directive': Color(0xFF455A64),
    'recovery_plan': Color(0xFF6A1B9A),
  };
  static const _planLabels = {
    'care_plan': 'Care Plan',
    'safety_plan': 'Safety Plan',
    'treatment_plan': 'Treatment Plan',
    'advance_directive': 'Advance Directive',
    'recovery_plan': 'Recovery Plan',
  };

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    final color = _planColors[n.noteType] ?? kInfo;
    final label = _planLabels[n.noteType] ?? 'Plan';
    final dateStr = DateFormat('d MMM y').format(n.createdAt.toLocal());

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _expanded ? color : kDivider),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, color: color),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: color)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(n.title.isNotEmpty ? n.title : label,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: kText))),
                      Text(dateStr, style: SignacareText.caption),
                      const SizedBox(width: 4),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                          color: kTextLight, size: 18),
                    ]),
                  ),
                  if (_expanded && n.content.isNotEmpty) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: kSurface,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(n.content,
                            style: const TextStyle(
                                fontSize: 12, color: kText, height: 1.5)),
                      ),
                    ),
                  ],
                ])),
          ]),
        ),
      ),
    );
  }
}

// ── Shared helpers ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: kTextLight,
          letterSpacing: 0.3));
}
