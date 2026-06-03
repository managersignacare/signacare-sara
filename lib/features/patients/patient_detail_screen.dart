import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/models/patient.dart';
import '../../core/services/sync_service.dart';
import '../../core/api/api_client.dart';
import '../../core/api/response_parsers.dart';
import 'tabs/summary_tab.dart';
import 'tabs/messages_tab.dart';
import 'tabs/prescriptions_tab.dart';
import 'tabs/alerts_plans_tab.dart';
import 'tabs/review_91day_tab.dart';
import 'tabs/contacts_tab.dart';
import 'tabs/overview_tab.dart';
import 'tabs/tasks_tab.dart';
import 'tabs/pathology_tab.dart';
import 'tabs/episodes_tab.dart';

final patientDetailProvider =
    FutureProvider.family<Patient?, String>((ref, id) {
  return ref.read(syncServiceProvider).fetchPatient(id);
});

final _patientEpisodesProvider =
    FutureProvider.family<List<Episode>, String>((ref, patientId) async {
  final data = await api.get('/episodes/patient/$patientId');
  final list = readMapListEnvelope(
    data,
    preferredKeys: const ['data', 'episodes'],
  );
  return list
      .map((j) => Episode.fromJson(Map<String, dynamic>.from(j as Map)))
      .toList();
});

class PatientDetailScreen extends ConsumerWidget {
  final String patientId;
  const PatientDetailScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientDetailProvider(patientId));

    return patientAsync.when(
      loading: () => Scaffold(
          appBar: AppBar(),
          body:
              const Center(child: CircularProgressIndicator(color: kPrimary))),
      error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: Center(
              child: Text('Failed to load: $e', style: SignacareText.body))),
      data: (patient) {
        if (patient == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('Patient not found')));
        }
        return _PatientDashboard(patient: patient, patientId: patientId);
      },
    );
  }
}

/// Card-based patient dashboard — all key info accessible in 1-2 taps.
class _PatientDashboard extends ConsumerWidget {
  final Patient patient;
  final String patientId;
  const _PatientDashboard({required this.patient, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = patient;
    final dob = DateTime.tryParse(p.dateOfBirth);
    final topInset = MediaQuery.paddingOf(context).top;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final headerExpandedHeight =
        (topInset + (128 * textScale)).clamp(148.0, 210.0).toDouble();
    final dobStr = dob != null
        ? '${dob.day.toString().padLeft(2, '0')}/${dob.month.toString().padLeft(2, '0')}/${dob.year}'
        : '';

    return Scaffold(
      backgroundColor: kSurface,
      body: CustomScrollView(
        slivers: [
          // ── Patient Header ──
          SliverAppBar(
            pinned: true,
            toolbarHeight: 60,
            expandedHeight: headerExpandedHeight,
            title: Text(
              p.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: kText),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: LayoutBuilder(builder: (context, constraints) {
                final collapseCutoff = topInset + kToolbarHeight + 14;
                final showExpandedHeader = constraints.maxHeight > collapseCutoff;
                return Container(
                  color: Colors.white,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: showExpandedHeader ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !showExpandedHeader,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, topInset + 16, 16, 12),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor:
                                    const Color(0xFFF0852C).withAlpha(25),
                                child: Text(
                                  '${p.givenName.isNotEmpty ? p.givenName[0] : ''}${p.familyName.isNotEmpty ? p.familyName[0] : ''}',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFF0852C)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(p.fullName,
                                        style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: kText)),
                                    const SizedBox(height: 3),
                                    Wrap(spacing: 8, runSpacing: 4, children: [
                                      if (p.emrNumber != null)
                                        _Chip('MRN: ${p.emrNumber!}'),
                                      if (dobStr.isNotEmpty)
                                        _Chip('DOB: $dobStr'),
                                      if (p.age > 0) _Chip('${p.age}y'),
                                      if (p.gender != null) _Chip(p.gender!),
                                    ]),
                                  ])),
                            ]),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Section Cards — user's priority order ──
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 1. Summary — longitudinal patient history
                _SectionCard(
                  icon: Icons.summarize_outlined,
                  title: 'Summary',
                  subtitle: 'Longitudinal clinical picture',
                  color: const Color(0xFFF0852C),
                  onTap: () => _pushTab(
                      context, 'Summary', SummaryTab(patientId: patientId)),
                ),
                // 2. Overview — contacts, stakeholders, consent
                _SectionCard(
                  icon: Icons.contacts_outlined,
                  title: 'Overview',
                  subtitle: 'Contacts, stakeholders, consent',
                  color: kInfo,
                  onTap: () => _pushTab(
                      context, 'Overview', OverviewTab(patientId: patientId)),
                ),
                // 2b. Episodes & Recent Notes
                _SectionCard(
                  icon: Icons.folder_outlined,
                  title: 'Episodes & Notes',
                  subtitle: 'Episodes and recent 10 clinical notes',
                  color: const Color(0xFF5C6BC0),
                  onTap: () => _pushTab(context, 'Episodes & Notes',
                      EpisodesTab(patientId: patientId)),
                ),
                // 3. 91-Day Review — current management plan
                _SectionCard(
                  icon: Icons.event_repeat_outlined,
                  title: '91-Day Review',
                  subtitle: 'Management plan & review status',
                  color: const Color(0xFF6A1B9A),
                  onTap: () => _pushTab(context, '91-Day Review',
                      Review91DayTab(patientId: patientId)),
                ),
                // 4. Medications — current meds
                _SectionCard(
                  icon: Icons.medication_outlined,
                  title: 'Medications',
                  subtitle: 'Current prescriptions',
                  color: kSuccess,
                  onTap: () => _pushTab(context, 'Medications',
                      PrescriptionsTab(patientId: patientId)),
                ),
                // 4b. Pathology
                _SectionCard(
                  icon: Icons.science_outlined,
                  title: 'Pathology',
                  subtitle: 'Recent pathology results',
                  color: const Color(0xFF00796B),
                  onTap: () => _pushTab(
                      context, 'Pathology', PathologyTab(patientId: patientId)),
                ),
                // 5. Alerts & Plans
                _SectionCard(
                  icon: Icons.warning_amber_rounded,
                  title: 'Alerts & Plans',
                  subtitle: 'Clinical alerts, safety & care plans',
                  color: kError,
                  onTap: () => _pushTab(context, 'Alerts & Plans',
                      AlertsPlansTab(patientId: patientId)),
                ),
                // 6. Tasks
                _SectionCard(
                  icon: Icons.task_alt_outlined,
                  title: 'Tasks',
                  subtitle: 'Clinical tasks & follow-ups',
                  color: kWarning,
                  onTap: () => _pushTab(
                      context, 'Tasks', TasksTab(patientId: patientId)),
                ),
                // 7. Contacts — add contact records
                _SectionCard(
                  icon: Icons.assignment_turned_in_outlined,
                  title: 'Contacts',
                  subtitle: 'Contact events & ABF logging',
                  color: const Color(0xFF00796B),
                  onTap: () => _pushTab(
                      context, 'Contacts', ContactsTab(patientId: patientId)),
                ),
                // 8. Notes — write draft
                _SectionCard(
                  icon: Icons.edit_note_outlined,
                  title: 'Write Note',
                  subtitle: 'Create a draft clinical note',
                  color: kPrimary,
                  onTap: () => _showAddNoteSheet(context, ref),
                ),
                // 9. Messages
                _SectionCard(
                  icon: Icons.message_outlined,
                  title: 'Messages',
                  subtitle: 'Message patient or carer',
                  color: const Color(0xFF1565C0),
                  onTap: () => _pushTab(
                      context,
                      'Messages',
                      MessagesTab(
                          patientId: patientId, patientName: p.displayName)),
                ),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _pushTab(BuildContext context, String title, Widget child) {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: kSurface,
            appBar: AppBar(title: Text(title)),
            body: child,
          ),
        ));
  }

  void _showAddNoteSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddNoteSheet(
        patientId: patientId,
        onSaved: () => ref.invalidate(syncServiceProvider),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: kSurface, borderRadius: BorderRadius.circular(4)),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10, color: kTextLight, fontWeight: FontWeight.w500)),
      );
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _SectionCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kDivider),
              ),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: kText)),
                      Text(subtitle,
                          style:
                              const TextStyle(fontSize: 11, color: kTextLight)),
                    ])),
                const Icon(Icons.chevron_right, color: kTextLight, size: 20),
              ]),
            ),
          ),
        ),
      );
}

// ── Add Note Sheet ─────────────────────────────────────────────────────────────

class _AddNoteSheet extends ConsumerStatefulWidget {
  final String patientId;
  final VoidCallback onSaved;
  const _AddNoteSheet({required this.patientId, required this.onSaved});

  @override
  ConsumerState<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends ConsumerState<_AddNoteSheet> {
  final _contentCtrl = TextEditingController();
  late String _noteType;
  String? _episodeId;
  bool _saving = false;
  String? _error;

  static const _noteTypes = [
    ('progress', 'Progress Note'),
    ('consultation', 'Consultation'),
    ('assessment', 'Assessment'),
    ('intake', 'Intake'),
    ('mdt', 'MDT / Case Conference'),
    ('mse', 'MSE'),
    ('risk', 'Risk'),
    ('correspondence', 'Correspondence'),
    ('discharge_summary', 'Discharge Summary'),
    ('discharge', 'Discharge Note'),
    ('soap', 'SOAP'),
    ('other', 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _noteType = 'progress';
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_contentCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Note content is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // POST /clinical-notes — same API as desktop. Creates as draft.
      await api.post('/clinical-notes', data: {
        'patientId': widget.patientId,
        if (_episodeId != null) 'episodeId': _episodeId,
        'noteType': _noteType,
        // API CreateNoteSchema requires strict ISO-8601 UTC (`...Z`).
        // Local timestamps without timezone suffix fail validation.
        'noteDateTime': DateTime.now().toUtc().toIso8601String(),
        'content': _contentCtrl.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Draft saved — visible on desktop'),
              backgroundColor: kSuccess),
        );
      }
    } catch (e) {
      final message = readApiErrorMessage(
        e,
        fallback: 'Failed to save draft note.',
      );
      setState(() {
        _error = message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final episodesAsync = ref.watch(_patientEpisodesProvider(widget.patientId));

    return Container(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Write Draft Note',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: kText)),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Note Type',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kTextLight)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _noteTypes
                .map((t) => ChoiceChip(
                      label: Text(t.$2,
                          style: TextStyle(
                              fontSize: 11,
                              color: _noteType == t.$1 ? kPrimary : kText)),
                      selected: _noteType == t.$1,
                      selectedColor: kPrimary.withAlpha(30),
                      backgroundColor: kSurface,
                      onSelected: (_) => setState(() => _noteType = t.$1),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          episodesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (err, __) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Episodes unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
                style: const TextStyle(color: kTextLight, fontSize: 12),
              ),
            ),
            data: (episodes) {
              final open = episodes.where((e) => e.status == 'open').toList();
              if (open.isEmpty) return const SizedBox.shrink();
              return Column(children: [
                DropdownButtonFormField<String>(
                  initialValue: _episodeId,
                  decoration: const InputDecoration(
                      labelText: 'Episode (optional)',
                      prefixIcon: Icon(Icons.folder_outlined, size: 20)),
                  items: [
                    const DropdownMenuItem(
                        value: null,
                        child: Text('None', style: TextStyle(fontSize: 13))),
                    ...open.map((e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(e.title,
                            style: const TextStyle(fontSize: 13)))),
                  ],
                  onChanged: (v) => setState(() => _episodeId = v),
                  isExpanded: true,
                ),
                const SizedBox(height: 10),
              ]);
            },
          ),
          TextField(
            controller: _contentCtrl,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Clinical notes *',
              alignLabelWithHint: true,
              hintText: 'This will be saved as a draft — finalise on desktop',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: kError, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Save Draft'),
          ),
          const SizedBox(height: 8),
          const Text(
              'Drafts appear in My Drafts and can be finalised on the web app',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: kTextLight)),
        ]),
      ),
    );
  }
}
