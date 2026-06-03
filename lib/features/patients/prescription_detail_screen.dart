import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/models/note.dart';
import '../../core/api/api_client.dart';

/// Full electronic prescription screen — launched from the prescription form
/// or tapped from an existing prescription card.
class PrescriptionDetailScreen extends ConsumerStatefulWidget {
  /// Pre-fill from an existing Prescription (view/edit mode)
  final Prescription? existing;

  /// Patient context
  final String patientId;
  final String patientName;
  final String? patientDob;
  final String? medicareNumber;

  const PrescriptionDetailScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.patientDob,
    this.medicareNumber,
    this.existing,
  });

  @override
  ConsumerState<PrescriptionDetailScreen> createState() => _PrescriptionDetailScreenState();
}

class _PrescriptionDetailScreenState extends ConsumerState<PrescriptionDetailScreen> {
  final _formKey = GlobalKey<FormState>();

  // Medication
  final _medCtrl    = TextEditingController();
  final _strengthCtrl = TextEditingController();
  final _formCtrl   = TextEditingController();
  final _quantityCtrl = TextEditingController(text: '30');
  final _repeatsCtrl  = TextEditingController(text: '5');
  final _dirCtrl    = TextEditingController();
  final _brandCtrl  = TextEditingController();

  // Prescriber
  final _prescriberCtrl  = TextEditingController();
  final _qualCtrl        = TextEditingController();
  final _ahpraCtrl       = TextEditingController();
  final _prescriberAddrCtrl = TextEditingController();
  final _authorityCtrl   = TextEditingController();

  // Clinical
  final _indicationCtrl = TextEditingController();
  final _notesCtrl      = TextEditingController();

  bool _isPbs         = true;
  bool _brandSubst    = true; // brand substitution permitted
  bool _isControlled  = false;
  bool _sendElec      = false;
  bool _saving        = false;
  String? _error;
  String? _eScriptToken;

  static const _medicationForms = [
    'Tablet', 'Capsule', 'Liquid', 'Injection', 'Cream / Ointment',
    'Patch', 'Inhaler', 'Drops', 'Suppository', 'Other',
  ];
  String _medForm = 'Tablet';

  @override
  void initState() {
    super.initState();
    final rx = widget.existing;
    if (rx != null) {
      _medCtrl.text    = rx.medicationName;
      _quantityCtrl.text = '30';
      _dirCtrl.text    = '';
      _prescriberCtrl.text = rx.prescriber ?? '';
    }
    _loadPrescriberDetails();
  }

  Future<void> _loadPrescriberDetails() async {
    // Audit Tier 4.2 (HIGH-J2) — this load was failing silently. A
    // DioException here typically means the user's session expired
    // or `/staff/me` is 500ing. Surface a snackbar + log so the
    // clinician is not confused by empty prescriber fields.
    try {
      final data = await api.get('/staff/me');
      if (!mounted || data is! Map) return;
      final given = data['givenName']?.toString() ?? '';
      final family = data['familyName']?.toString() ?? '';
      final fullName = [given, family].where((s) => s.isNotEmpty).join(' ');
      setState(() {
        if (_prescriberCtrl.text.isEmpty && fullName.isNotEmpty) {
          _prescriberCtrl.text = fullName;
        }
        if (_qualCtrl.text.isEmpty && data['qualifications'] != null) {
          _qualCtrl.text = data['qualifications'].toString();
        }
        if (_ahpraCtrl.text.isEmpty) {
          final prescriberNum = data['prescriberNumber']?.toString() ?? '';
          final ahpraNum = data['ahpraNumber']?.toString() ?? '';
          _ahpraCtrl.text = prescriberNum.isNotEmpty ? prescriberNum : ahpraNum;
        }
      });
    } on DioException catch (err) {
      developer.log(
        '_loadPrescriberDetails: /staff/me failed',
        name: 'sara.prescriptions',
        error: err.message,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not load prescriber details: '
            '${err.response?.data is Map && (err.response!.data as Map)['message'] is String ? (err.response!.data as Map)['message'] : err.message ?? 'unknown'}. '
            'Fill in Name / AHPRA manually if needed.'),
      ));
    } catch (err) {
      developer.log(
        '_loadPrescriberDetails: unexpected error',
        name: 'sara.prescriptions',
        error: err,
      );
    }
  }

  @override
  void dispose() {
    for (final c in [
      _medCtrl, _strengthCtrl, _formCtrl, _quantityCtrl, _repeatsCtrl,
      _dirCtrl, _brandCtrl, _prescriberCtrl, _qualCtrl, _ahpraCtrl,
      _prescriberAddrCtrl, _authorityCtrl, _indicationCtrl, _notesCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _savePrescription() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final data = await api.post('/medications', data: {
        'patientId': widget.patientId,
        'medicationName': _medCtrl.text.trim(),
        'dose': '${_strengthCtrl.text.trim()} ${_medForm}',
        'frequency': _dirCtrl.text.trim(),
        'prescriber': _prescriberCtrl.text.trim().isEmpty ? null : _prescriberCtrl.text.trim(),
        'notes': _buildNotes(),
        'isActive': true,
        'startDate': DateTime.now().toIso8601String().split('T')[0],
      });
      if (_sendElec) await _generateEScript(data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _error = 'Failed to save: $e'; _saving = false; });
    }
  }

  String _buildNotes() {
    final parts = <String>[];
    if (_isPbs) parts.add('PBS');
    if (_isControlled) parts.add('Controlled substance');
    if (!_brandSubst) parts.add('Brand substitution NOT permitted');
    if (_indicationCtrl.text.isNotEmpty) parts.add('Indication: ${_indicationCtrl.text.trim()}');
    if (_authorityCtrl.text.isNotEmpty) parts.add('Authority #: ${_authorityCtrl.text.trim()}');
    if (_notesCtrl.text.isNotEmpty) parts.add(_notesCtrl.text.trim());
    return parts.join(' | ');
  }

  Future<void> _generateEScript(dynamic savedData) async {
    // In a real implementation this would call the ETP (Electronic Transfer of Prescriptions) gateway.
    // For now, generate a mock token.
    final token = 'ERX-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase()}';
    setState(() => _eScriptToken = token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Electronic Prescription'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _savePrescription,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Issue', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Patient card
            _SectionCard(
              title: 'Patient',
              icon: Icons.person_outline,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _InfoTile('Name', widget.patientName),
                if (widget.patientDob != null) _InfoTile('Date of birth', widget.patientDob!),
                if (widget.medicareNumber != null) _InfoTile('Medicare', widget.medicareNumber!),
              ]),
            ),
            const SizedBox(height: 12),

            // Medication
            _SectionCard(
              title: 'Medication',
              icon: Icons.medication_outlined,
              child: Column(children: [
                TextFormField(
                  controller: _medCtrl,
                  decoration: const InputDecoration(labelText: 'Drug name *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _strengthCtrl,
                      decoration: const InputDecoration(labelText: 'Strength *', hintText: 'e.g. 10mg'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _medForm,
                      decoration: const InputDecoration(labelText: 'Form'),
                      items: _medicationForms.map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) => setState(() => _medForm = v!),
                      isExpanded: true,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextFormField(
                    controller: _quantityCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextFormField(
                    controller: _repeatsCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Repeats'),
                  )),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _dirCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Directions / Dosage instructions *',
                    alignLabelWithHint: true,
                    hintText: 'e.g. Take 1 tablet daily with food',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _brandCtrl,
                  decoration: const InputDecoration(labelText: 'Brand (optional)', hintText: 'Leave blank for generic'),
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // PBS / controls
            _SectionCard(
              title: 'Funding & Controls',
              icon: Icons.policy_outlined,
              child: Column(children: [
                _ToggleRow('PBS Prescription', 'Subsidised under Pharmaceutical Benefits Scheme', _isPbs, kPrimary, (v) => setState(() => _isPbs = v)),
                if (_isPbs) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _authorityCtrl,
                    decoration: const InputDecoration(labelText: 'Authority number (PBS)', prefixIcon: Icon(Icons.numbers, size: 18)),
                  ),
                ],
                const Divider(height: 16),
                _ToggleRow('Brand substitution permitted', 'Pharmacist may dispense generic equivalent', _brandSubst, kSuccess, (v) => setState(() => _brandSubst = v)),
                const Divider(height: 16),
                _ToggleRow('Controlled substance (Schedule 8)', 'Requires special prescription form', _isControlled, kError, (v) => setState(() => _isControlled = v)),
              ]),
            ),
            const SizedBox(height: 12),

            // Prescriber
            _SectionCard(
              title: 'Prescriber',
              icon: Icons.badge_outlined,
              child: Column(children: [
                TextFormField(
                  controller: _prescriberCtrl,
                  decoration: const InputDecoration(labelText: 'Prescriber name *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextFormField(
                    controller: _qualCtrl,
                    decoration: const InputDecoration(labelText: 'Qualifications', hintText: 'e.g. MBBS, FRANZCP'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextFormField(
                    controller: _ahpraCtrl,
                    decoration: const InputDecoration(labelText: 'AHPRA / Prescriber #'),
                  )),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _prescriberAddrCtrl,
                  decoration: const InputDecoration(labelText: 'Practice address'),
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // Clinical notes
            _SectionCard(
              title: 'Clinical',
              icon: Icons.notes_outlined,
              child: Column(children: [
                TextFormField(
                  controller: _indicationCtrl,
                  decoration: const InputDecoration(labelText: 'Indication / Diagnosis'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Additional notes', alignLabelWithHint: true),
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // Electronic prescription toggle
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _sendElec ? kPrimary.withOpacity(0.05) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _sendElec ? kPrimary.withOpacity(0.4) : kDivider),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _ToggleRow(
                  'Issue as Electronic Prescription (eRx)',
                  'Generates a QR token patient can present at any pharmacy',
                  _sendElec, kPrimary, (v) => setState(() => _sendElec = v),
                ),
                if (_eScriptToken != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: kSuccess.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: kSuccess.withOpacity(0.3))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('eScript token generated', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kSuccess)),
                      const SizedBox(height: 4),
                      SelectableText(_eScriptToken!, style: const TextStyle(fontFamily: 'Courier', fontSize: 13, color: kText)),
                      const SizedBox(height: 8),
                      const Text('Share this token or QR code with the patient. Valid at participating pharmacies.', style: TextStyle(fontSize: 11, color: kTextLight)),
                    ]),
                  ),
                ],
              ]),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: kError, fontSize: 12)),
              ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _saving ? null : _savePrescription,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.medical_services_outlined),
              label: Text(_saving ? 'Issuing…' : 'Issue Prescription'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ── Helper widgets ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kDivider)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: kPrimary),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText, letterSpacing: -0.2)),
      ]),
      const SizedBox(height: 12),
      child,
    ]),
  );
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: SignacareText.caption.copyWith(fontWeight: FontWeight.w600))),
      Expanded(child: Text(value, style: SignacareText.body.copyWith(fontSize: 13))),
    ]),
  );
}

class _ToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;
  const _ToggleRow(this.title, this.subtitle, this.value, this.color, this.onChanged);

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
      const SizedBox(height: 2),
      Text(subtitle, style: const TextStyle(fontSize: 11, color: kTextLight)),
    ])),
    Switch(value: value, activeColor: color, onChanged: onChanged),
  ]);
}
