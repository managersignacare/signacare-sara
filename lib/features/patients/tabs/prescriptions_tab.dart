import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../core/models/note.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/response_parsers.dart';
import '../prescription_detail_screen.dart';

final _prescriptionsProvider = FutureProvider.family<List<Prescription>, String>((ref, patientId) async {
  final data = await api.get('/medications/patients/$patientId/medications');
  final list = readMapListEnvelope(
    data,
    preferredKeys: const ['medications', 'data'],
  );
  return list
      .map((j) => Prescription.fromJson(Map<String, dynamic>.from(j as Map)))
      .toList();
});

const _commonMedications = [
  'Olanzapine', 'Quetiapine', 'Risperidone', 'Aripiprazole', 'Clozapine',
  'Haloperidol', 'Paliperidone', 'Ziprasidone', 'Amisulpride', 'Lurasidone',
  'Lithium Carbonate', 'Sodium Valproate', 'Lamotrigine', 'Carbamazepine',
  'Sertraline', 'Fluoxetine', 'Escitalopram', 'Venlafaxine', 'Mirtazapine',
  'Diazepam', 'Lorazepam', 'Zopiclone', 'Melatonin', 'Propranolol',
];

const _frequencies = [
  'Once daily (mane)', 'Once daily (nocte)', 'Twice daily (BD)',
  'Three times daily (TDS)', 'Four times daily (QID)', 'Weekly',
  'Fortnightly', 'Monthly (depot)', 'As required (PRN)', 'Once-off',
];

class PrescriptionsTab extends ConsumerStatefulWidget {
  final String patientId;
  const PrescriptionsTab({super.key, required this.patientId});

  @override
  ConsumerState<PrescriptionsTab> createState() => _PrescriptionsTabState();
}

class _PrescriptionsTabState extends ConsumerState<PrescriptionsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rxAsync = ref.watch(_prescriptionsProvider(widget.patientId));

    return Scaffold(
      backgroundColor: kSurface,
      body: rxAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (err, __) => Center(
          child: Text(
            'Prescriptions unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
            style: const TextStyle(color: kTextLight),
            textAlign: TextAlign.center,
          ),
        ),
        data: (rxList) {
          final active = rxList.where((r) => r.isActive).toList();
          final inactive = rxList.where((r) => !r.isActive).toList();

          return RefreshIndicator(
            color: kPrimary,
            onRefresh: () async => ref.invalidate(_prescriptionsProvider(widget.patientId)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (active.isNotEmpty) ...[
                  _SectionHeader('Current Medications (${active.length})'),
                  const SizedBox(height: 8),
                  ...active.map((r) => _RxCard(rx: r, isActive: true)),
                ],
                if (active.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kDivider)),
                    child: const Center(child: Text('No current medications on record', style: TextStyle(color: kTextLight, fontSize: 13))),
                  ),
                if (inactive.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionHeader('Historical (${inactive.length})'),
                  const SizedBox(height: 8),
                  ...inactive.map((r) => _RxCard(rx: r, isActive: false)),
                ],
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kTextLight, letterSpacing: 0.3));
}

class _RxCard extends StatelessWidget {
  final Prescription rx;
  final bool isActive;
  const _RxCard({required this.rx, required this.isActive});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: isActive ? kDivider : kDivider.withOpacity(0.5)),
    ),
    clipBehavior: Clip.antiAlias,
    child: IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(width: 3, color: isActive ? kPrimary : kTextLight),
        Expanded(child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: isActive ? kPrimary.withOpacity(0.1) : kDivider, borderRadius: BorderRadius.circular(8)),
        child: Icon(Icons.medication, color: isActive ? kPrimary : kTextLight, size: 22),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(rx.medicationName, style: SignacareText.body.copyWith(fontWeight: FontWeight.w600, fontSize: 14, color: isActive ? kText : kTextLight)),
        const SizedBox(height: 3),
        Text('${rx.dose} · ${rx.frequency}', style: SignacareText.caption),
        if (rx.prescriber != null)
          Text('Prescribed by: ${rx.prescriber!}', style: SignacareText.caption.copyWith(fontStyle: FontStyle.italic)),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isActive ? kSuccess.withOpacity(0.1) : kDivider,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(isActive ? 'Active' : 'Ceased', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isActive ? kSuccess : kTextLight)),
      ),
          ]),
        )),
      ]),
    ),
  );
}

class PrescriptionForm extends StatefulWidget {
  final String patientId;
  final VoidCallback onSaved;
  const PrescriptionForm({super.key, required this.patientId, required this.onSaved});

  @override
  State<PrescriptionForm> createState() => _PrescriptionFormState();
}

class _PrescriptionFormState extends State<PrescriptionForm> {
  final _medCtrl = TextEditingController();
  final _doseCtrl = TextEditingController();
  final _prescriberCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _frequency = 'Once daily (mane)';
  String? _selectedMed;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _medCtrl.dispose(); _doseCtrl.dispose(); _prescriberCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final med = _selectedMed ?? _medCtrl.text.trim();
    if (med.isEmpty || _doseCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Medication name and dose are required');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await api.post('/medications', data: {
        'patientId': widget.patientId,
        'medicationName': med,
        'dose': _doseCtrl.text.trim(),
        'frequency': _frequency,
        'prescriber': _prescriberCtrl.text.trim().isEmpty ? null : _prescriberCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'isActive': true,
        'startDate': DateTime.now().toIso8601String().split('T')[0],
      });
      if (mounted) { Navigator.pop(context); widget.onSaved(); }
    } catch (e) {
      setState(() { _error = 'Failed to save: $e'; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Write Prescription', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kText)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(),
          const SizedBox(height: 8),

          // Common meds chips
          const Text('Common medications', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextLight)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: _commonMedications.map((m) => ChoiceChip(
            label: Text(m, style: TextStyle(fontSize: 11, color: _selectedMed == m ? kPrimary : kText)),
            selected: _selectedMed == m,
            selectedColor: kPrimary.withOpacity(0.12),
            backgroundColor: kSurface,
            onSelected: (sel) => setState(() {
              _selectedMed = sel ? m : null;
              if (sel) _medCtrl.text = m;
            }),
          )).toList()),
          const SizedBox(height: 12),

          TextField(controller: _medCtrl, decoration: const InputDecoration(labelText: 'Medication name *', prefixIcon: Icon(Icons.medication_outlined, size: 20)),
            onChanged: (_) => setState(() => _selectedMed = null)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _doseCtrl, decoration: const InputDecoration(labelText: 'Dose *', hintText: 'e.g. 10mg'))),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _frequency,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: _frequencies.map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) => setState(() => _frequency = v!),
                isExpanded: true,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _prescriberCtrl, decoration: const InputDecoration(labelText: 'Prescriber', prefixIcon: Icon(Icons.person_outline, size: 20))),
          const SizedBox(height: 10),
          TextField(controller: _notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Clinical notes / instructions', alignLabelWithHint: true)),

          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: kError, fontSize: 12))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.medication),
                label: Text(_saving ? 'Saving…' : 'Add'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PrescriptionDetailScreen(
                      patientId: widget.patientId,
                      patientName: '',
                    )),
                  );
                },
                icon: const Icon(Icons.qr_code_2, size: 18),
                label: const Text('Issue eRx'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPrimary,
                  side: const BorderSide(color: kPrimary),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
