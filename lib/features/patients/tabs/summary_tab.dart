import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../core/models/note.dart';
import '../../../core/models/patient.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/response_parsers.dart';

final _notesProvider =
    FutureProvider.family<List<Note>, String>((ref, patientId) {
  return ref.read(syncServiceProvider).fetchNotes(patientId);
});

final _episodesProvider =
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

/// Fetch full patient record including AI summary fields
final _patientFullProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
        (ref, patientId) async {
  final data = await api.get('/patients/$patientId');
  return readMapEnvelope(
    data,
    preferredKeys: const ['data', 'patient'],
  );
});

/// Fetch diagnoses
final _diagnosesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, patientId) async {
  final data = await api.get('/patients/$patientId/diagnoses');
  return readMapListEnvelope(
    data,
    preferredKeys: const ['diagnoses', 'data'],
  );
});

const _noteTypeLabels = {
  'progress': 'Progress Note',
  'ward_round': 'Ward Round',
  'intake': 'Intake',
  'lai': 'LAI Admin',
  'clozapine': 'Clozapine',
  'review': 'Review',
  'collateral': 'Collateral',
  'phone': 'Phone/Telehealth',
  'home_visit': 'Home Visit',
  'case_conference': 'Case Conference',
  'group': 'Group',
  'contact': 'Contact',
  'physical_health': 'Physical Health',
  'incident': 'Incident',
  'consumer_peer_support': 'Consumer Peer Support',
  'carer_peer_support': 'Carer Peer Support',
  'progress_note': 'Progress Note',
  'consultation': 'Consultation',
  'assessment': 'Assessment',
  'soap': 'SOAP',
  'mdt': 'MDT',
  'mse': 'MSE',
  'risk': 'Risk',
  'discharge_summary': 'Discharge',
};

const _noteTypeColors = {
  'progress': Color(0xFF327C8D),
  'ward_round': Color(0xFF5C6BC0),
  'intake': Color(0xFFF0852C),
  'lai': Color(0xFFD32F2F),
  'clozapine': Color(0xFF7B1FA2),
  'review': Color(0xFF0288D1),
  'collateral': Color(0xFF455A64),
  'phone': Color(0xFF00838F),
  'home_visit': Color(0xFF558B2F),
  'case_conference': Color(0xFFE65100),
  'group': Color(0xFFAD1457),
  'contact': Color(0xFF327C8D),
  'physical_health': Color(0xFF2E7D32),
  'incident': Color(0xFFB71C1C),
  'progress_note': Color(0xFF327C8D),
  'consultation': Color(0xFF0288D1),
  'assessment': Color(0xFF6A1B9A),
  'soap': Color(0xFF00796B),
  'mdt': Color(0xFF5C6BC0),
  'mse': Color(0xFF00838F),
  'risk': Color(0xFFB71C1C),
};

class SummaryTab extends ConsumerStatefulWidget {
  final String patientId;
  const SummaryTab({super.key, required this.patientId});

  @override
  ConsumerState<SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends ConsumerState<SummaryTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final patientAsync = ref.watch(_patientFullProvider(widget.patientId));
    final notesAsync = ref.watch(_notesProvider(widget.patientId));
    final episodesAsync = ref.watch(_episodesProvider(widget.patientId));
    final diagnosesAsync = ref.watch(_diagnosesProvider(widget.patientId));

    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async {
        ref.invalidate(_patientFullProvider(widget.patientId));
        ref.invalidate(_notesProvider(widget.patientId));
        ref.invalidate(_episodesProvider(widget.patientId));
        ref.invalidate(_diagnosesProvider(widget.patientId));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── AI Clinical Summary (from desktop Smart Summary) ──
          patientAsync.when(
            loading: () => const _Skeleton(height: 60),
            error: (err, __) => Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: kWarning.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Summary unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
                style: const TextStyle(fontSize: 12, color: kTextLight),
              ),
            ),
            data: (p) {
              final aiSummary = p['aiSummary'] as String?;
              final formulation = p['clinicalFormulation'] as String?;
              final hasContent = (aiSummary != null && aiSummary.isNotEmpty) ||
                  (formulation != null && formulation.isNotEmpty);
              if (!hasContent) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: kWarning.withAlpha(15),
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.auto_awesome, size: 18, color: kWarning),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            'AI summary not yet generated. Generate from the desktop Smart Summary tab.',
                            style: TextStyle(fontSize: 12, color: kTextLight))),
                  ]),
                );
              }
              return Column(children: [
                if (aiSummary != null && aiSummary.isNotEmpty)
                  _AiSummaryCard(
                      title: 'AI Clinical Summary', content: aiSummary),
                if (formulation != null && formulation.isNotEmpty)
                  _AiSummaryCard(
                      title: 'Clinical Formulation', content: formulation),
                const SizedBox(height: 4),
              ]);
            },
          ),

          // ── Diagnoses ──
          diagnosesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (err, __) => Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: kWarning.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Diagnoses unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
                style: const TextStyle(fontSize: 12, color: kTextLight),
              ),
            ),
            data: (diagnoses) {
              if (diagnoses.isEmpty) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kDivider)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.medical_information_outlined,
                            size: 15, color: kPrimary),
                        SizedBox(width: 6),
                        Text('Diagnoses',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: kTextLight)),
                      ]),
                      const SizedBox(height: 8),
                      ...diagnoses.map((d) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('  •  ',
                                      style: TextStyle(
                                          color: kPrimary,
                                          fontWeight: FontWeight.w700)),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(
                                            d['diagnosisName'] ??
                                                d['name'] ??
                                                d['primaryDiagnosis'] ??
                                                'Unknown',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: kText,
                                                fontWeight: FontWeight.w500)),
                                        if (d['icd10Code'] != null)
                                          Text('ICD-10: ${d['icd10Code']}',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: kTextLight)),
                                      ])),
                                ]),
                          )),
                    ]),
              );
            },
          ),

          // ── Active Episodes ──
          episodesAsync.when(
            loading: () => const _Skeleton(height: 80),
            error: (err, __) => Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: kWarning.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Episodes unavailable: ${readApiErrorMessage(err, fallback: 'unable to load')}',
                style: const TextStyle(fontSize: 12, color: kTextLight),
              ),
            ),
            data: (episodes) {
              final active = episodes.where((e) => e.status == 'open').toList();
              if (active.isEmpty) return const SizedBox.shrink();
              return _EpisodesCard(episodes: active);
            },
          ),
          const SizedBox(height: 12),

          // ── Stats row ──
          notesAsync.when(
            loading: () => const _Skeleton(height: 60),
            error: (err, __) => Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: kWarning.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Notes unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
                style: const TextStyle(fontSize: 12, color: kTextLight),
              ),
            ),
            data: (notes) => _StatsRow(notes: notes),
          ),
          const SizedBox(height: 16),

          // ── Recent Encounters (longitudinal timeline) ──
          const _SectionHeader('Clinical Timeline'),
          const SizedBox(height: 8),
          notesAsync.when(
            loading: () => const _Skeleton(height: 200),
            error: (e, _) =>
                Text('Error loading notes: $e', style: SignacareText.caption),
            data: (notes) {
              final recent = notes
                  .where((n) => !n.didNotAttend)
                  .take(15)
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              if (recent.isEmpty) {
                return Center(
                    child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text('No encounters recorded',
                      style: SignacareText.caption),
                ));
              }
              return Column(
                  children:
                      recent.map((n) => _NoteTimelineCard(note: n)).toList());
            },
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

// ── AI Summary Card ──

class _AiSummaryCard extends StatefulWidget {
  final String title;
  final String content;
  const _AiSummaryCard({required this.title, required this.content});

  @override
  State<_AiSummaryCard> createState() => _AiSummaryCardState();
}

class _AiSummaryCardState extends State<_AiSummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.content.length > 200
        ? '${widget.content.substring(0, 200)}...'
        : widget.content;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0852C).withAlpha(40)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.auto_awesome,
                  size: 16, color: const Color(0xFFF0852C)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kText))),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20, color: kTextLight),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Text(
            _expanded ? widget.content : preview,
            style: const TextStyle(fontSize: 12, color: kText, height: 1.5),
          ),
        ),
      ]),
    );
  }
}

// ── Episodes Card ──

class _EpisodesCard extends StatelessWidget {
  final List<Episode> episodes;
  const _EpisodesCard({required this.episodes});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kDivider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Active Episodes',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kTextLight)),
          const SizedBox(height: 8),
          ...episodes.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(
                      width: 3,
                      height: 36,
                      color: kPrimary,
                      margin: const EdgeInsets.only(right: 10)),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(e.title,
                            style: SignacareText.body.copyWith(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                            '${e.episodeType} · ${e.primaryClinicianName ?? 'No clinician'}',
                            style: SignacareText.caption),
                        if (e.primaryDiagnosis != null)
                          Text(e.primaryDiagnosis!,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: kTextLight,
                                  fontStyle: FontStyle.italic)),
                      ])),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: kSuccess.withAlpha(25),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Text('Open',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: kSuccess)),
                  ),
                ]),
              )),
        ]),
      );
}

// ── Stats Row ──

class _StatsRow extends StatelessWidget {
  final List<Note> notes;
  const _StatsRow({required this.notes});

  @override
  Widget build(BuildContext context) {
    final total = notes.where((n) => !n.didNotAttend).length;
    final abf =
        notes.where((n) => n.isReportableContact && !n.didNotAttend).length;
    final dna = notes.where((n) => n.didNotAttend).length;
    return Row(children: [
      Expanded(child: _StatCard('$total', 'Encounters', kPrimary)),
      const SizedBox(width: 8),
      Expanded(child: _StatCard('$abf', 'ABF', kSuccess)),
      const SizedBox(width: 8),
      Expanded(child: _StatCard('$dna', 'DNA', kError)),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatCard(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kDivider)),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: kTextLight)),
        ]),
      );
}

// ── Note Timeline Card ──

class _NoteTimelineCard extends StatefulWidget {
  final Note note;
  const _NoteTimelineCard({required this.note});

  @override
  State<_NoteTimelineCard> createState() => _NoteTimelineCardState();
}

class _NoteTimelineCardState extends State<_NoteTimelineCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    final color = _noteTypeColors[n.noteType] ?? kInfo;
    final label =
        _noteTypeLabels[n.noteType] ?? n.noteType.replaceAll('_', ' ');
    final dateStr =
        DateFormat('EEE d MMM y · HH:mm').format(n.createdAt.toLocal());

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _expanded ? color : kDivider),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: color),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Flexible(
                                  child: Text(
                                      n.title.isNotEmpty ? n.title : label,
                                      style: SignacareText.body.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 6),
                              _MiniChip(label, color),
                              if (n.status == 'signed') ...[
                                const SizedBox(width: 4),
                                _MiniChip('Signed', kSuccess)
                              ],
                              if (n.status == 'draft') ...[
                                const SizedBox(width: 4),
                                _MiniChip('Draft', kWarning)
                              ],
                              // Audit Tier 5.4 — AI-DRAFT chip on the note row.
                              if (n.showAiDraftBanner) ...[
                                const SizedBox(width: 4),
                                _MiniChip('AI-DRAFT', kWarning)
                              ],
                            ]),
                            const SizedBox(height: 3),
                            Text(dateStr, style: SignacareText.caption),
                            if (n.authorName != null)
                              Text(n.authorName!, style: SignacareText.caption),
                          ])),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                          color: kTextLight, size: 20),
                    ]),
                  ),
                  if (_expanded) ...[
                    const Divider(height: 1),
                    if (n.showAiDraftBanner)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        color: kWarning.withAlpha(30),
                        child: const Text(
                          'AI-DRAFT — Pending clinician review. Verify facts '
                          'against the source record before acting on this note.',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: kText,
                              height: 1.4),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: kSurface,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(
                            n.content.isNotEmpty ? n.content : 'No content',
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

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniChip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: color)),
      );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: kTextLight));
}

class _Skeleton extends StatelessWidget {
  final double height;
  const _Skeleton({required this.height});
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
            color: kDivider, borderRadius: BorderRadius.circular(12)),
      );
}
