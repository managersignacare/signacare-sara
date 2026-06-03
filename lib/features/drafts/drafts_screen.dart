import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/response_parsers.dart';

/// Fetches draft notes — same API as desktop Drafts page (GET /clinical-notes?status=draft)
final draftsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await api.get('/clinical-notes', params: {'status': 'draft', 'limit': '100'});
  return readMapListEnvelope(
    data,
    preferredKeys: const ['data', 'notes'],
  );
});

class DraftsScreen extends ConsumerWidget {
  const DraftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftsAsync = ref.watch(draftsProvider);

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('My Drafts'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 22), onPressed: () => ref.invalidate(draftsProvider)),
        ],
      ),
      // FAB: New Draft — pick a patient first, then write note
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kPrimary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Draft', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () async {
          // Navigate to patient list — user picks a patient, then we open note sheet
          final patientId = await Navigator.push<String>(context,
            MaterialPageRoute(builder: (_) => const _PatientPickerScreen()));
          if (patientId != null && context.mounted) {
            _showNewDraftSheet(context, ref, patientId);
          }
        },
      ),
      body: draftsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (err, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 40, color: kError),
            const SizedBox(height: 12),
            Text(
              'Drafts unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
              style: const TextStyle(color: kTextLight),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => ref.invalidate(draftsProvider), child: const Text('Retry')),
          ]),
        ),
        data: (drafts) {
          if (drafts.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.drafts_outlined, size: 56, color: kTextLight.withAlpha(100)),
                const SizedBox(height: 16),
                const Text('No draft notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kText)),
                const SizedBox(height: 6),
                Text('Tap + to create a draft note', style: TextStyle(fontSize: 13, color: kTextLight)),
                const SizedBox(height: 4),
                Text('Drafts sync with the desktop app', style: TextStyle(fontSize: 11, color: kTextLight)),
              ]),
            );
          }
          return RefreshIndicator(
            color: kPrimary,
            onRefresh: () async => ref.invalidate(draftsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: drafts.length,
              itemBuilder: (context, i) => _DraftCard(
                draft: drafts[i],
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => _EditDraftScreen(draft: drafts[i])),
                ).then((_) => ref.invalidate(draftsProvider)),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showNewDraftSheet(BuildContext context, WidgetRef ref, String patientId) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _NewDraftSheet(
        patientId: patientId,
        onSaved: () => ref.invalidate(draftsProvider),
      ),
    );
  }
}

// ── Patient Picker (lightweight search → return patientId) ──

class _PatientPickerScreen extends ConsumerStatefulWidget {
  const _PatientPickerScreen();
  @override
  ConsumerState<_PatientPickerScreen> createState() => _PatientPickerState();
}

class _PatientPickerState extends ConsumerState<_PatientPickerScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  Future<void> _search(String q) async {
    if (q.trim().length < 2) return;
    setState(() => _loading = true);
    try {
      final data = await api.get('/patients', params: {'search': q.trim(), 'limit': '20'});
      final list = (data as Map)['data'] as List? ?? [];
      setState(() => _results = list.map((j) => Map<String, dynamic>.from(j as Map)).toList());
    } catch (e) {
      developer.log('patient search failed', name: 'sara.drafts', error: e);
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(title: const Text('Select Patient')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search by name or MRN...',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
            onChanged: (v) {
              if (v.length >= 2) _search(v);
            },
          ),
        ),
        if (_loading) const LinearProgressIndicator(color: kPrimary),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (_, i) {
              final p = _results[i];
              final name = '${p['givenName'] ?? ''} ${p['familyName'] ?? ''}'.trim();
              return ListTile(
                leading: CircleAvatar(
                  radius: 18, backgroundColor: kPrimary.withAlpha(25),
                  child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700)),
                ),
                title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text('MRN: ${p['emrNumber'] ?? '—'}', style: TextStyle(fontSize: 12, color: kTextLight)),
                onTap: () => Navigator.pop(context, p['id'] as String),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ── New Draft Sheet (creates via POST /clinical-notes — syncs with desktop) ──

class _NewDraftSheet extends StatefulWidget {
  final String patientId;
  final VoidCallback onSaved;
  const _NewDraftSheet({required this.patientId, required this.onSaved});

  @override
  State<_NewDraftSheet> createState() => _NewDraftSheetState();
}

class _NewDraftSheetState extends State<_NewDraftSheet> {
  final _contentCtrl = TextEditingController();
  String _noteType = 'progress_note';
  bool _saving = false;
  String? _error;

  static const _noteTypes = [
    ('progress_note', 'Progress Note'),
    ('consultation', 'Consultation'),
    ('assessment', 'Assessment'),
    ('soap', 'SOAP Note'),
    ('intake', 'Intake'),
    ('mdt', 'MDT'),
    ('mse', 'MSE'),
    ('risk', 'Risk Assessment'),
    ('discharge_summary', 'Discharge Summary'),
    ('other', 'Other'),
  ];

  @override
  void dispose() { _contentCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_contentCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Note content is required');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      // POST /clinical-notes — same API as desktop. Status defaults to 'draft' server-side.
      await api.post('/clinical-notes', data: {
        'patientId': widget.patientId,
        'noteType': _noteType,
        'noteDateTime': DateTime.now().toIso8601String(),
        'content': _contentCtrl.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved — visible on desktop'), backgroundColor: kSuccess),
        );
      }
    } catch (e) {
      setState(() { _saving = false; _error = 'Failed to save: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('New Draft Note', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kText)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Note Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextLight)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: _noteTypes.map((t) => ChoiceChip(
            label: Text(t.$2, style: TextStyle(fontSize: 11, color: _noteType == t.$1 ? kPrimary : kText)),
            selected: _noteType == t.$1,
            selectedColor: kPrimary.withAlpha(30),
            backgroundColor: kSurface,
            onSelected: (_) => setState(() => _noteType = t.$1),
          )).toList()),
          const SizedBox(height: 14),
          TextField(
            controller: _contentCtrl,
            maxLines: 8,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Clinical notes *',
              alignLabelWithHint: true,
              hintText: 'Write your notes here — will appear as draft on desktop',
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
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Save Draft'),
          ),
          const SizedBox(height: 6),
          Text('Syncs with desktop — finalise and sign on web', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: kTextLight)),
        ]),
      ),
    );
  }
}

// ── Draft Card ──

class _DraftCard extends StatelessWidget {
  final Map<String, dynamic> draft;
  final VoidCallback onTap;
  const _DraftCard({required this.draft, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final noteType = (draft['noteType'] ?? 'progress').toString();
    final patientName = draft['patientName'] ?? 'Unknown Patient';
    final emr = draft['patientEmrNumber'] ?? '';
    final content = (draft['content'] ?? draft['soapAssessment'] ?? '').toString();
    final preview = content.length > 120 ? '${content.substring(0, 120)}...' : content;
    final dt = DateTime.tryParse(draft['updatedAt'] ?? draft['createdAt'] ?? '');
    final timeStr = dt != null ? _formatRelative(dt) : '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kDivider)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: kPrimary.withAlpha(25), borderRadius: BorderRadius.circular(6)),
                child: Text(_formatType(noteType), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kPrimary)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: kWarning.withAlpha(25), borderRadius: BorderRadius.circular(4)),
                child: const Text('DRAFT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: kWarning)),
              ),
              const Spacer(),
              Text(timeStr, style: TextStyle(fontSize: 11, color: kTextLight)),
            ]),
            const SizedBox(height: 10),
            Text(patientName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
            if (emr.isNotEmpty) Text('MRN: $emr', style: TextStyle(fontSize: 11, color: kTextLight)),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(preview, style: TextStyle(fontSize: 12, color: kText.withAlpha(180), height: 1.4)),
            ],
          ]),
        ),
      ),
    );
  }

  static String _formatType(String type) =>
    type.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w).join(' ');

  static String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Edit Draft Screen ──

class _EditDraftScreen extends StatefulWidget {
  final Map<String, dynamic> draft;
  const _EditDraftScreen({required this.draft});

  @override
  State<_EditDraftScreen> createState() => _EditDraftScreenState();
}

class _EditDraftScreenState extends State<_EditDraftScreen> {
  late final TextEditingController _contentCtrl;
  late final TextEditingController _subjCtrl;
  late final TextEditingController _objCtrl;
  late final TextEditingController _assessCtrl;
  late final TextEditingController _planCtrl;
  bool _saving = false;
  String? _error;
  bool _useSoap = false;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _contentCtrl = TextEditingController(text: d['content'] ?? '');
    _subjCtrl = TextEditingController(text: d['soapSubjective'] ?? '');
    _objCtrl = TextEditingController(text: d['soapObjective'] ?? '');
    _assessCtrl = TextEditingController(text: d['soapAssessment'] ?? '');
    _planCtrl = TextEditingController(text: d['soapPlan'] ?? '');
    _useSoap = (d['soapSubjective'] ?? '').toString().isNotEmpty || (d['soapAssessment'] ?? '').toString().isNotEmpty;
  }

  @override
  void dispose() {
    _contentCtrl.dispose(); _subjCtrl.dispose(); _objCtrl.dispose();
    _assessCtrl.dispose(); _planCtrl.dispose(); super.dispose();
  }

  Future<void> _saveDraft() async {
    setState(() { _saving = true; _error = null; });
    try {
      final noteId = widget.draft['id'] as String;
      final body = <String, dynamic>{ 'content': _contentCtrl.text.trim() };
      if (_useSoap) {
        body['soapSubjective'] = _subjCtrl.text.trim();
        body['soapObjective'] = _objCtrl.text.trim();
        body['soapAssessment'] = _assessCtrl.text.trim();
        body['soapPlan'] = _planCtrl.text.trim();
      }
      // PATCH /clinical-notes/:id — same API as desktop
      await api.patch('/clinical-notes/$noteId', data: body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved'), backgroundColor: kSuccess, duration: Duration(seconds: 2)));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() { _saving = false; _error = 'Failed to save: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final patientName = d['patientName'] ?? 'Unknown';
    final noteType = _DraftCard._formatType(d['noteType'] ?? 'progress');

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Edit Draft', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _saveDraft,
            icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2))
              : const Icon(Icons.save_outlined, size: 18),
            label: Text(_saving ? 'Saving...' : 'Save', style: TextStyle(color: _saving ? kTextLight : kPrimary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Patient header
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: kDivider)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                CircleAvatar(
                  radius: 18, backgroundColor: kPrimary.withAlpha(25),
                  child: Text(patientName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join(),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(patientName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(noteType, style: TextStyle(fontSize: 12, color: kTextLight)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: kWarning.withAlpha(25), borderRadius: BorderRadius.circular(6)),
                  child: const Text('DRAFT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kWarning)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Format toggle
          Row(children: [
            const Text('Format:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kText)),
            const SizedBox(width: 12),
            ChoiceChip(label: const Text('Free text', style: TextStyle(fontSize: 12)), selected: !_useSoap,
              selectedColor: kPrimary.withAlpha(30), onSelected: (_) => setState(() => _useSoap = false)),
            const SizedBox(width: 6),
            ChoiceChip(label: const Text('SOAP', style: TextStyle(fontSize: 12)), selected: _useSoap,
              selectedColor: kPrimary.withAlpha(30), onSelected: (_) => setState(() => _useSoap = true)),
          ]),
          const SizedBox(height: 16),

          if (_error != null) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: const TextStyle(color: kError, fontSize: 12)),
          ),

          if (!_useSoap)
            TextField(controller: _contentCtrl, maxLines: 16,
              decoration: const InputDecoration(labelText: 'Clinical Notes', alignLabelWithHint: true))
          else ...[
            TextField(controller: _subjCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Subjective', alignLabelWithHint: true)),
            const SizedBox(height: 12),
            TextField(controller: _objCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Objective', alignLabelWithHint: true)),
            const SizedBox(height: 12),
            TextField(controller: _assessCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Assessment', alignLabelWithHint: true)),
            const SizedBox(height: 12),
            TextField(controller: _planCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Plan', alignLabelWithHint: true)),
          ],
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: _saving ? null : _saveDraft,
            icon: const Icon(Icons.save, color: Colors.white, size: 18),
            label: Text(_saving ? 'Saving...' : 'Save Draft'),
          )),
          const SizedBox(height: 48),
        ]),
      ),
    );
  }
}
