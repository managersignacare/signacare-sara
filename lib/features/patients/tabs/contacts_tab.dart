import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/response_parsers.dart';

/// Fetches unified contacts — GET /contact-records/patient/:id/unified
/// Same API as the desktop appointments > contacts subtab
final _contactsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, patientId) async {
  try {
    final data = await api.get('/contact-records/patient/$patientId/unified');
    return readMapListEnvelope(
      data,
      preferredKeys: const ['contacts', 'data'],
    );
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    // Backward-compatible fallback only when unified endpoint is absent.
    if (status == 404 || status == 405) {
      final data = await api.get('/contact-records/patient/$patientId');
      return readMapListEnvelope(
        data,
        preferredKeys: const ['records', 'contacts', 'data'],
      );
    }
    rethrow;
  }
});

class ContactsTab extends ConsumerWidget {
  final String patientId;
  const ContactsTab({super.key, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(_contactsProvider(patientId));

    return Scaffold(
      backgroundColor: kSurface,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kPrimary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Log Contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () => _showAddContactSheet(context, ref),
      ),
      body: contactsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (err, __) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: kError, size: 36),
          const SizedBox(height: 8),
          Text(
            'Contacts unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
            style: const TextStyle(color: kTextLight),
            textAlign: TextAlign.center,
          ),
          TextButton(onPressed: () => ref.invalidate(_contactsProvider(patientId)), child: const Text('Retry')),
        ])),
        data: (contacts) {
          if (contacts.isEmpty) {
            return RefreshIndicator(
              color: kPrimary,
              onRefresh: () async => ref.invalidate(_contactsProvider(patientId)),
              child: ListView(children: [
                const SizedBox(height: 80),
                Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.contact_phone_outlined, size: 48, color: kTextLight.withAlpha(100)),
                  const SizedBox(height: 12),
                  const Text('No contacts logged', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kText)),
                  Text('Tap + to log a contact', style: TextStyle(fontSize: 12, color: kTextLight)),
                ])),
              ]),
            );
          }
          return RefreshIndicator(
            color: kPrimary,
            onRefresh: () async => ref.invalidate(_contactsProvider(patientId)),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: contacts.length,
              itemBuilder: (_, i) => _ContactCard(contact: contacts[i]),
            ),
          );
        },
      ),
    );
  }

  void _showAddContactSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _AddContactSheet(
        patientId: patientId,
        onSaved: () => ref.invalidate(_contactsProvider(patientId)),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final Map<String, dynamic> contact;
  const _ContactCard({required this.contact});

  @override
  Widget build(BuildContext context) {
    final type = (contact['contactType'] ?? contact['noteType'] ?? 'Contact').toString();
    final date = contact['contactDate'] ?? contact['createdAt'] ?? '';
    final dt = DateTime.tryParse(date.toString());
    final dateStr = dt != null ? '${dt.day}/${dt.month}/${dt.year}' : '';
    final duration = contact['durationMin'] ?? contact['durationMinutes'];
    final medium = contact['contactMedium'] ?? '';
    final source = (contact['source'] ?? '').toString();
    final isReportable = contact['isReportable'] == true;
    final status = (contact['status'] ?? '').toString();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: kDivider)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_iconForType(type), size: 18, color: kPrimary),
            const SizedBox(width: 8),
            Expanded(child: Text(_formatType(type), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText))),
            if (isReportable) Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: kSuccess.withAlpha(20), borderRadius: BorderRadius.circular(4)),
              child: const Text('ABF', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: kSuccess)),
            ),
            if (status == 'draft') ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: kWarning.withAlpha(20), borderRadius: BorderRadius.circular(4)),
                child: const Text('DRAFT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: kWarning)),
              ),
            ],
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 12, children: [
            if (dateStr.isNotEmpty) _Meta(Icons.calendar_today, dateStr),
            if (duration != null) _Meta(Icons.timer_outlined, '${duration}min'),
            if (medium.toString().isNotEmpty) _Meta(Icons.phone_in_talk, medium.toString()),
            if (source.isNotEmpty) _Meta(Icons.source_outlined, source.replaceAll('_', ' ')),
          ]),
        ]),
      ),
    );
  }

  IconData _iconForType(String type) {
    final t = type.toLowerCase();
    if (t.contains('phone') || t.contains('telephone')) return Icons.phone;
    if (t.contains('home')) return Icons.home;
    if (t.contains('group')) return Icons.groups;
    if (t.contains('video') || t.contains('telehealth')) return Icons.videocam;
    return Icons.person;
  }

  String _formatType(String type) =>
    type.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w).join(' ');
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 12, color: kTextLight),
    const SizedBox(width: 3),
    Text(text, style: TextStyle(fontSize: 11, color: kTextLight)),
  ]);
}

// ── Add Contact Sheet — POST /contact-records (syncs with desktop) ──

class _AddContactSheet extends StatefulWidget {
  final String patientId;
  final VoidCallback onSaved;
  const _AddContactSheet({required this.patientId, required this.onSaved});

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  String _contactType = 'Face to face — Individual';
  String _durationCategory = '15–30 minutes';
  bool _saving = false;
  String? _error;
  final _summaryCtrl = TextEditingController();

  static const _types = [
    'Face to face — Individual',
    'Face to face — Group',
    'Telephone',
    'Telehealth/Video',
    'Home Visit',
    'Non-face-to-face — Clinical documentation',
  ];

  static const _durations = [
    'Less than 15 minutes',
    '15–30 minutes',
    '30–45 minutes',
    '45–60 minutes',
    'More than 60 minutes',
  ];

  @override
  void dispose() { _summaryCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      // POST /contact-records — same API as desktop appointments > contacts subtab
      await api.post('/contact-records', data: {
        'patientId': widget.patientId,
        'contactType': _contactType,
        'contactDate': DateTime.now().toIso8601String().split('T')[0],
        'contactTime': '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        'durationCategory': _durationCategory,
        'isReportable': true,
        'status': 'completed',
        'briefSummary': _summaryCtrl.text.trim().isNotEmpty ? _summaryCtrl.text.trim() : null,
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact logged — visible on desktop'), backgroundColor: kSuccess),
        );
      }
    } on DioException catch (e) {
      // Audit Tier 4.2 (HIGH-J2) — surface the backend error message
      // (validation / permission / clinic-mismatch) instead of Dart's
      // raw `$e` stringification.
      final serverMessage = e.response?.data is Map && (e.response!.data as Map)['message'] is String
          ? (e.response!.data as Map)['message'] as String
          : null;
      setState(() {
        _saving = false;
        _error = serverMessage != null
            ? 'Failed to save: $serverMessage'
            : 'Failed to save: ${e.message ?? 'check your connection'}';
      });
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
            const Text('Log Contact', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kText)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(),
          const SizedBox(height: 8),

          // Contact type
          const Text('Contact Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextLight)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: _types.map((t) => ChoiceChip(
            label: Text(t, style: TextStyle(fontSize: 11, color: _contactType == t ? kPrimary : kText)),
            selected: _contactType == t,
            selectedColor: kPrimary.withAlpha(30),
            backgroundColor: kSurface,
            onSelected: (_) => setState(() => _contactType = t),
          )).toList()),
          const SizedBox(height: 14),

          // Duration
          const Text('Duration', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextLight)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: _durations.map((d) => ChoiceChip(
            label: Text(d, style: TextStyle(fontSize: 11, color: _durationCategory == d ? kPrimary : kText)),
            selected: _durationCategory == d,
            selectedColor: kPrimary.withAlpha(30),
            backgroundColor: kSurface,
            onSelected: (_) => setState(() => _durationCategory = d),
          )).toList()),
          const SizedBox(height: 14),

          // Brief summary
          TextField(
            controller: _summaryCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Brief Summary (optional)',
              alignLabelWithHint: true,
              hintText: 'Key points from this contact',
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
              : const Text('Save Contact'),
          ),
          const SizedBox(height: 6),
          Text('Syncs with desktop appointments > contacts', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: kTextLight)),
        ]),
      ),
    );
  }
}
