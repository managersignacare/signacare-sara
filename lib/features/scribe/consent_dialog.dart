import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme.dart';

/// Audit Tier 4.3 — Sara scribe recording consent dialog.
///
/// Per user direction (2026-04-19): BOTH consent modes must be
/// supported. The dialog fetches the clinic's configured mode from
/// `/scribe/consent/mode` and renders one of two paths:
///
///   - `patient_esignature` — custom Flutter signature pad that
///     captures the drawn path as a PNG and posts it alongside the
///     consent record. No external plugin dependency; rendering uses
///     the framework's `PictureRecorder` + `Picture.toImage`.
///   - `clinician_attestation` — the clinician types the patient's
///     name + ticks an attestation checkbox; the attestation string
///     is persisted to the `scribe_consents` row.
///
/// On success the dialog pops with the server's consent-record ID so
/// the caller can tag the scribe session with it. The scribe UI
/// (Tier 12.3) will block the record button until this dialog returns
/// non-null.
class ScribeConsentDialog extends StatefulWidget {
  final String patientId;
  final String? sessionId;
  const ScribeConsentDialog({
    super.key,
    required this.patientId,
    this.sessionId,
  });

  @override
  State<ScribeConsentDialog> createState() => _ScribeConsentDialogState();

  /// Convenience launcher.
  static Future<String?> show(
    BuildContext context, {
    required String patientId,
    String? sessionId,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScribeConsentDialog(patientId: patientId, sessionId: sessionId),
    );
  }
}

class _ScribeConsentDialogState extends State<ScribeConsentDialog> {
  String? _mode;
  bool _loadingMode = true;
  String? _loadError;
  bool _submitting = false;
  String? _submitError;

  // E-signature state
  final List<List<Offset>> _strokes = [];
  List<Offset>? _currentStroke;

  // Attestation state
  final _attestationCtrl = TextEditingController();
  bool _attestationChecked = false;

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  @override
  void dispose() {
    _attestationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMode() async {
    try {
      final data = await api.get('/scribe/consent/mode');
      if (!mounted) return;
      final mode = data is Map ? data['mode']?.toString() : null;
      setState(() {
        _mode = mode ?? 'clinician_attestation';
        _loadingMode = false;
      });
    } on DioException catch (err) {
      developer.log('scribe consent: failed to load mode', name: 'sara.scribe', error: err.message);
      if (!mounted) return;
      setState(() {
        _loadingMode = false;
        _loadError = err.response?.data is Map && (err.response!.data as Map)['message'] is String
            ? (err.response!.data as Map)['message'] as String
            : err.message ?? 'Could not load consent settings';
      });
    }
  }

  Future<String?> _signatureToBase64Png(Size canvasSize) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height), bg);
    final pen = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) { path.lineTo(p.dx, p.dy); }
      canvas.drawPath(path, pen);
    }
    final picture = recorder.endRecording();
    final img = await picture.toImage(canvasSize.width.toInt(), canvasSize.height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    return base64Encode(byteData.buffer.asUint8List());
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_mode == 'patient_esignature' && _strokes.isEmpty) {
      setState(() => _submitError = 'Please capture the patient\'s signature before continuing.');
      return;
    }
    if (_mode == 'clinician_attestation' && (_attestationCtrl.text.trim().isEmpty || !_attestationChecked)) {
      setState(() => _submitError = 'Enter the patient\'s name and tick the attestation checkbox.');
      return;
    }
    setState(() { _submitting = true; _submitError = null; });
    try {
      String? signaturePng;
      if (_mode == 'patient_esignature') {
        // Render at the capture box size — 320x140 is the drawing area.
        signaturePng = await _signatureToBase64Png(const Size(320, 140));
      }
      final body = <String, dynamic>{
        'patientId': widget.patientId,
        if (widget.sessionId != null) 'sessionId': widget.sessionId,
        'mode': _mode,
        if (signaturePng != null) 'patientSignaturePng': signaturePng,
        if (_mode == 'clinician_attestation')
          'clinicianAttestationText':
              'I attest that patient ${_attestationCtrl.text.trim()} has been informed that '
              'this session will be recorded for clinical documentation and has given verbal consent.',
      };
      final data = await api.post('/scribe/consent', data: body);
      if (!mounted) return;
      final id = data is Map ? data['id']?.toString() : null;
      Navigator.of(context).pop(id);
    } on DioException catch (err) {
      if (!mounted) return;
      final msg = err.response?.data is Map && (err.response!.data as Map)['message'] is String
          ? (err.response!.data as Map)['message'] as String
          : err.message ?? 'check your connection';
      setState(() {
        _submitting = false;
        _submitError = 'Could not save consent: $msg';
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = 'Unexpected error: $err';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recording Consent'),
      content: SizedBox(width: 360, child: _body()),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        if (!_loadingMode && _loadError == null)
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Consent & Start'),
          ),
      ],
    );
  }

  Widget _body() {
    if (_loadingMode) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(_loadError!, style: const TextStyle(color: kError)),
      );
    }
    if (_mode == 'patient_esignature') {
      return _esignaturePath();
    }
    return _attestationPath();
  }

  Widget _esignaturePath() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        'This consultation will be recorded for clinical documentation. '
        'Please have the patient sign below to confirm consent.',
        style: TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 12),
      GestureDetector(
        onPanStart: (d) {
          setState(() {
            _currentStroke = [d.localPosition];
            _strokes.add(_currentStroke!);
          });
        },
        onPanUpdate: (d) {
          setState(() { _currentStroke?.add(d.localPosition); });
        },
        onPanEnd: (_) { _currentStroke = null; },
        child: Container(
          height: 140,
          width: 320,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: kDivider),
            borderRadius: BorderRadius.circular(4),
          ),
          child: CustomPaint(painter: _SignaturePainter(_strokes)),
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [
        TextButton.icon(
          onPressed: _strokes.isEmpty ? null : () => setState(() => _strokes.clear()),
          icon: const Icon(Icons.clear, size: 16),
          label: const Text('Clear'),
        ),
      ]),
      if (_submitError != null)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(_submitError!, style: const TextStyle(color: kError, fontSize: 12))),
    ]);
  }

  Widget _attestationPath() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        'Verbal consent flow: enter the patient name below and tick the attestation. '
        'The patient has been informed this session will be recorded for clinical documentation.',
        style: TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _attestationCtrl,
        decoration: const InputDecoration(labelText: 'Patient name'),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Checkbox(
          value: _attestationChecked,
          onChanged: (v) => setState(() => _attestationChecked = v ?? false),
        ),
        const Expanded(
          child: Text(
            'I attest verbal consent was obtained for this recording.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ]),
      if (_submitError != null)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(_submitError!, style: const TextStyle(color: kError, fontSize: 12))),
    ]);
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) {
        if (stroke.isNotEmpty) {
          canvas.drawCircle(stroke.first, 1.25, Paint()..color = Colors.black);
        }
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) { path.lineTo(p.dx, p.dy); }
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
