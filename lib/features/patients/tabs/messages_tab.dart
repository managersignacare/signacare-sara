import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../core/models/note.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/response_parsers.dart';

final _messagesProvider = FutureProvider.family<List<Message>, String>((ref, patientId) async {
  final data = await api.get('/correspondence/patient/$patientId');
  final list = readMapListEnvelope(
    data,
    preferredKeys: const ['data', 'letters'],
  );
  return list
      .map((j) => Message.fromJson({
            ...Map<String, dynamic>.from(j as Map),
            // Correspondence rows are immutable audit records rather than
            // inbox entries with read-state transitions.
            'isRead': true,
          }))
      .toList();
});

final _patientContactsProvider = FutureProvider.family<List<_PatientContact>, String>((ref, patientId) async {
  final data = await api.get('/patients/$patientId/contacts');
  final list = readMapListEnvelope(
    data,
    preferredKeys: const ['contacts', 'data'],
  );
  return list.map((m) {
    final name = [m['givenName'], m['familyName']]
        .where((s) => s != null && s.toString().isNotEmpty)
        .join(' ');
    final rel = m['relationship']?.toString() ?? 'Support Person';
    return _PatientContact(
      name: name.isEmpty ? rel : name,
      relationship: rel,
    );
  }).toList();
});

class MessagesTab extends ConsumerStatefulWidget {
  final String patientId;
  final String? patientName;
  const MessagesTab({super.key, required this.patientId, this.patientName});

  @override
  ConsumerState<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends ConsumerState<MessagesTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  void _openCompose({String? prefillTo}) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ComposeMessageSheet(
      patientId: widget.patientId,
      patientName: widget.patientName,
      prefillTo: prefillTo,
      onSent: () => ref.invalidate(_messagesProvider(widget.patientId)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final msgsAsync = ref.watch(_messagesProvider(widget.patientId));
    final contactsAsync = ref.watch(_patientContactsProvider(widget.patientId));

    return Scaffold(
      backgroundColor: kSurface,
      body: Column(children: [
        // ── Registered contacts bar ────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Registered Contacts', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextLight, letterSpacing: 0.3)),
            const SizedBox(height: 8),
            // Patient row
            if (widget.patientName != null && widget.patientName!.isNotEmpty)
              _ContactRow(
                name: widget.patientName!,
                relationship: 'Patient',
                onMessage: () => _openCompose(prefillTo: widget.patientName),
              ),
            // Support contacts
            contactsAsync.when(
              loading: () => const SizedBox(height: 20, child: Center(child: LinearProgressIndicator())),
              error: (err, __) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Contacts unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
                  style: const TextStyle(fontSize: 11, color: kTextLight),
                ),
              ),
              data: (contacts) => contacts.isEmpty && (widget.patientName == null || widget.patientName!.isEmpty)
                ? const Text('No contacts on file', style: TextStyle(fontSize: 12, color: kTextLight))
                : Column(
                    children: contacts.map((c) => _ContactRow(
                      name: c.name,
                      relationship: c.relationship,
                      onMessage: () => _openCompose(prefillTo: c.name),
                    )).toList(),
                  ),
            ),
          ]),
        ),
        const Divider(height: 1),
        // ── Messages list ──────────────────────────────────────────────
        Expanded(
          child: msgsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
            error: (err, __) => Center(
              child: Text(
                'Messages unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
                style: const TextStyle(color: kTextLight),
                textAlign: TextAlign.center,
              ),
            ),
            data: (msgs) {
              if (msgs.isEmpty) {
                return Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.mail_outline, color: kTextLight, size: 56),
                    const SizedBox(height: 12),
                    const Text('No messages yet', style: TextStyle(color: kTextLight, fontSize: 14)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _openCompose(),
                      icon: const Icon(Icons.edit),
                      label: const Text('New Message'),
                    ),
                  ]),
                );
              }
              return RefreshIndicator(
                color: kPrimary,
                onRefresh: () async => ref.invalidate(_messagesProvider(widget.patientId)),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: msgs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _MessageCard(message: msgs[i]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _PatientContact {
  final String name;
  final String relationship;
  const _PatientContact({required this.name, required this.relationship});
}

class _ContactRow extends StatelessWidget {
  final String name;
  final String relationship;
  final VoidCallback onMessage;
  const _ContactRow({required this.name, required this.relationship, required this.onMessage});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: kPrimary.withOpacity(0.08), shape: BoxShape.circle),
        child: const Icon(Icons.person, size: 16, color: kPrimary),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
        Text(relationship, style: const TextStyle(fontSize: 11, color: kTextLight)),
      ])),
      IconButton(
        icon: const Icon(Icons.message_outlined, size: 18, color: kPrimary),
        onPressed: onMessage,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip: 'Send message',
      ),
    ]),
  );
}

class _MessageCard extends StatelessWidget {
  final Message message;
  const _MessageCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('d MMM · HH:mm').format(message.createdAt.toLocal());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kDivider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              message.subject,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kText),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(message.body, style: SignacareText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            message.recipientName?.isNotEmpty == true
                ? 'To: ${message.recipientName}'
                : (message.senderName != null ? 'From: ${message.senderName!}' : 'Patient correspondence'),
            style: SignacareText.caption.copyWith(fontStyle: FontStyle.italic),
          ),
          Text(timeStr, style: SignacareText.caption),
        ]),
      ]),
    );
  }
}

class ComposeMessageSheet extends StatefulWidget {
  final String patientId;
  final VoidCallback onSent;
  final String? patientName;
  final String? prefillTo;
  const ComposeMessageSheet({super.key, required this.patientId, required this.onSent, this.patientName, this.prefillTo});

  @override
  State<ComposeMessageSheet> createState() => _ComposeMessageSheetState();
}

class _ComposeMessageSheetState extends State<ComposeMessageSheet> {
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  List<_ContactOption> _contactOptions = [];

  @override
  void initState() {
    super.initState();
    if (widget.prefillTo != null) _toCtrl.text = widget.prefillTo!;
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final opts = <_ContactOption>[];
    if (widget.patientName != null && widget.patientName!.isNotEmpty) {
      opts.add(_ContactOption(label: widget.patientName!, value: widget.patientName!, icon: Icons.person));
    }
    try {
      final data = await api.get('/patients/${widget.patientId}/contacts');
      final list = (data is Map ? data['contacts'] ?? data['data'] ?? [] : data) as List<dynamic>;
      for (final c in list) {
        final m = c as Map;
        final name = [m['givenName'], m['familyName']].where((s) => s != null && s.toString().isNotEmpty).join(' ');
        final rel = m['relationship']?.toString() ?? 'Support';
        if (name.isNotEmpty) {
          opts.add(_ContactOption(label: '$name ($rel)', value: name, icon: Icons.people_outline));
        }
      }
    } catch (e) {
      developer.log(
        'failed to load patient contacts for compose sheet',
        name: 'sara.messages',
        error: e,
      );
    }
    if (mounted) setState(() => _contactOptions = opts);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_bodyCtrl.text.trim().isEmpty) return;
    setState(() { _sending = true; _error = null; });
    try {
      await api.post('/correspondence/letters', data: {
        'patientId': widget.patientId,
        'recipientName': _toCtrl.text.trim().isEmpty ? (widget.patientName ?? 'Patient') : _toCtrl.text.trim(),
        'letterType': 'patient_message',
        'subject': _subjectCtrl.text.trim().isEmpty ? '(no subject)' : _subjectCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
        'status': 'sent',
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onSent();
      }
    } catch (e) {
      setState(() { _error = 'Failed to send: $e'; _sending = false; });
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
            const Text('New Message', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kText)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(),
          const SizedBox(height: 8),

          // Quick-select recipient chips
          if (_contactOptions.isNotEmpty) ...[
            const Text('Quick select recipient', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kTextLight)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6, runSpacing: 4,
              children: _contactOptions.map((opt) => ActionChip(
                avatar: Icon(opt.icon, size: 14, color: kPrimary),
                label: Text(opt.label, style: const TextStyle(fontSize: 11)),
                onPressed: () => setState(() => _toCtrl.text = opt.value),
                backgroundColor: kSurface,
                side: const BorderSide(color: kDivider),
              )).toList(),
            ),
            const SizedBox(height: 10),
          ],

          TextField(controller: _toCtrl, decoration: const InputDecoration(labelText: 'Recipient', prefixIcon: Icon(Icons.person_outline, size: 20))),
          const SizedBox(height: 10),
          TextField(controller: _subjectCtrl, decoration: const InputDecoration(labelText: 'Subject', prefixIcon: Icon(Icons.subject, size: 20))),
          const SizedBox(height: 10),
          TextField(
            controller: _bodyCtrl, maxLines: 5,
            decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true, prefixIcon: Padding(padding: EdgeInsets.only(bottom: 72), child: Icon(Icons.message_outlined, size: 20))),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: kError, fontSize: 12))),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send),
            label: Text(_sending ? 'Sending…' : 'Send Message'),
          ),
        ]),
      ),
    );
  }
}

class _ContactOption {
  final String label;
  final String value;
  final IconData icon;
  const _ContactOption({required this.label, required this.value, required this.icon});
}
