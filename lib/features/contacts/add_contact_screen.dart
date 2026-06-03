import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/response_parsers.dart';
import '../../core/services/sync_service.dart';

// Contact options provider — fetched from API (same cliniccontactoptions table as web)
final _contactOptsProvider = FutureProvider<_ContactOpts>((ref) async {
  try {
    final data = await api.get('/staff-settings/contact-options');
    final d = data is Map ? data : {};
    return _ContactOpts(
      locations: _toStrList(d['locations']),
      media: _toStrList(d['contactMediaTypes']),
      serviceRecipients: _toStrList(d['serviceRecipientTypes']),
    );
  } catch (_) {
    return _ContactOpts(
        locations: _defaultLocations,
        media: _defaultMedia,
        serviceRecipients: _defaultRecipients);
  }
});

final _episodesProvider =
    FutureProvider.family<List<_Episode>, String>((ref, patientId) async {
  final data = await api.get('/episodes/patient/$patientId');
  final list = readMapListEnvelope(
    data,
    preferredKeys: const ['data', 'episodes'],
  );
  return list
      .where((j) => j['status'] == 'open')
      .map((j) => _Episode(
          id: j['id'].toString(), title: j['title']?.toString() ?? 'Untitled'))
      .toList();
});

List<String> _toStrList(dynamic v) =>
    (v as List? ?? []).map((e) => e.toString()).toList();

class _ContactOpts {
  final List<String> locations;
  final List<String> media;
  final List<String> serviceRecipients;
  const _ContactOpts(
      {required this.locations,
      required this.media,
      required this.serviceRecipients});
}

class _Episode {
  final String id;
  final String title;
  const _Episode({required this.id, required this.title});
}

const _noteTypes = [
  ('contact', 'Contact / Face-to-face'),
  ('phone', 'Phone / Telehealth'),
  ('home_visit', 'Home Visit'),
  ('ward_round', 'Ward Round'),
  ('case_conference', 'Case Conference'),
  ('group', 'Group'),
  ('physical_health', 'Physical Health'),
  ('consumer_peer_support', 'Consumer Peer Support'),
  ('carer_peer_support', 'Carer Peer Support'),
];

const _durationPresets = [15, 30, 45, 60, 90, 120];

// PR6M fallback defaults
const _defaultLocations = [
  '1 — Centre based',
  '2 — Client\'s home',
  '3 — School',
  '4 — GP clinic / PHC',
  '5 — Hospital - inpatient',
  '6 — Hospital - outpatient',
  '7 — Mobile/outreach',
  '8 — Aged care facility',
  '99 — Other (not listed)',
];
const _defaultMedia = [
  '1 — Direct',
  '2 — Telephone',
  '3 — Teleconferencing/videoconference',
  '5 — Other Synchronous',
  '6 — Other asynchronous',
];
const _defaultRecipients = [
  '1 — Client only',
  '2 — Carer/family only',
  '3 — Client and carer/family',
  '4 — Other',
  '5 — Not applicable',
];

class AddContactScreen extends ConsumerStatefulWidget {
  final String patientId;
  const AddContactScreen({super.key, required this.patientId});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _teamCtrl = TextEditingController();
  final _providingCtrl = TextEditingController(text: '1');
  final _receivingCtrl = TextEditingController(text: '1');

  String _noteType = 'contact';
  String? _location;
  String? _contactMedium;
  String? _serviceRecipients;
  String? _episodeId;
  int? _durationMin;
  bool _isReportable = true;
  bool _didNotAttend = false;
  DateTime _contactDate = DateTime.now();
  TimeOfDay _contactTime = TimeOfDay.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _teamCtrl.dispose();
    _providingCtrl.dispose();
    _receivingCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _contactDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _contactDate = picked);
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _contactTime);
    if (picked != null) setState(() => _contactTime = picked);
  }

  Future<void> _save() async {
    if (_location == null ||
        _contactMedium == null ||
        _serviceRecipients == null) {
      setState(() =>
          _error = 'Please select Location, Medium and Service Recipients');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final dateStr =
        '${_contactDate.year}-${_contactDate.month.toString().padLeft(2, '0')}-${_contactDate.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${_contactTime.hour.toString().padLeft(2, '0')}:${_contactTime.minute.toString().padLeft(2, '0')}';

    try {
      await ref.read(syncServiceProvider).writeNote(
        patientId: widget.patientId,
        episodeId: _episodeId,
        noteType: _noteType,
        title: _titleCtrl.text.trim().isEmpty
            ? _labelFor(_noteType)
            : _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        isReportableContact: _isReportable,
        didNotAttend: _didNotAttend,
        contactMeta: {
          'contactDate': dateStr,
          'contactTime': timeStr,
          'durationMin': _durationMin,
          'location': _location,
          'contactMedium': _contactMedium,
          'serviceRecipients': [_serviceRecipients],
          'team': _teamCtrl.text.trim().isEmpty ? null : _teamCtrl.text.trim(),
          'numProvidingService': int.tryParse(_providingCtrl.text),
          'numReceivingService': int.tryParse(_receivingCtrl.text),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = 'Failed to save: $e';
        _saving = false;
      });
    }
  }

  String _labelFor(String type) {
    for (final t in _noteTypes) {
      if (t.$1 == type) return t.$2;
    }
    return type;
  }

  @override
  Widget build(BuildContext context) {
    final optsAsync = ref.watch(_contactOptsProvider);
    final episodesAsync = ref.watch(_episodesProvider(widget.patientId));

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Add Contact'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Save',
                    style: TextStyle(
                        color: kPrimary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: optsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (_, __) => const Center(
            child: Text('Unable to load contact options',
                style: TextStyle(color: kTextLight))),
        data: (opts) => _buildForm(context, opts, episodesAsync),
      ),
    );
  }

  Widget _buildForm(BuildContext context, _ContactOpts opts,
      AsyncValue<List<_Episode>> episodesAsync) {
    // Initialise location/medium/recipients from first option if not yet set
    if (_location == null && opts.locations.isNotEmpty) {
      _location = opts.locations.first;
    }
    if (_contactMedium == null && opts.media.isNotEmpty) {
      _contactMedium = opts.media.first;
    }
    if (_serviceRecipients == null && opts.serviceRecipients.isNotEmpty) {
      _serviceRecipients = opts.serviceRecipients.first;
    }

    final dateLabel =
        '${_contactDate.day.toString().padLeft(2, '0')}/${_contactDate.month.toString().padLeft(2, '0')}/${_contactDate.year}';
    final timeLabel = _contactTime.format(context);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Contact Type ---
          _SectionLabel('Contact Type'),
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
                      selectedColor: kPrimary.withOpacity(0.12),
                      backgroundColor: kSurface,
                      onSelected: (_) => setState(() => _noteType = t.$1),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),

          // --- Date & Time ---
          _SectionLabel('Date & Time'),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: _PickerCard(
                icon: Icons.calendar_today_outlined,
                label: dateLabel,
                onTap: _pickDate,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PickerCard(
                icon: Icons.access_time_outlined,
                label: timeLabel,
                onTap: _pickTime,
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // --- Duration ---
          _SectionLabel('Duration (minutes)'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _durationPresets
                .map((d) => ChoiceChip(
                      label:
                          Text('$d min', style: const TextStyle(fontSize: 11)),
                      selected: _durationMin == d,
                      selectedColor: kPrimary.withOpacity(0.12),
                      onSelected: (_) => setState(
                          () => _durationMin = _durationMin == d ? null : d),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),

          // --- Episode ---
          _SectionLabel('Episode'),
          const SizedBox(height: 6),
          episodesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, __) => Text(
              'Episodes unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
              style: const TextStyle(color: kTextLight, fontSize: 12),
            ),
            data: (episodes) {
              if (episodes.isEmpty)
                return const Text('No open episodes',
                    style: TextStyle(color: kTextLight, fontSize: 12));
              return DropdownButtonFormField<String>(
                value: _episodeId,
                decoration: const InputDecoration(
                    labelText: 'Link to episode',
                    prefixIcon: Icon(Icons.folder_outlined, size: 20)),
                items: [
                  const DropdownMenuItem(
                      value: null,
                      child: Text('None', style: TextStyle(fontSize: 13))),
                  ...episodes.map((e) => DropdownMenuItem(
                      value: e.id,
                      child:
                          Text(e.title, style: const TextStyle(fontSize: 13)))),
                ],
                onChanged: (v) => setState(() => _episodeId = v),
                isExpanded: true,
              );
            },
          ),
          const SizedBox(height: 16),

          // --- Location ---
          _SectionLabel('Service Location *'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: opts.locations.contains(_location) ? _location : null,
            decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.place_outlined, size: 20)),
            items: opts.locations
                .map((l) => DropdownMenuItem(
                      value: l,
                      child: Text(_shortLabel(l),
                          style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _location = v),
            isExpanded: true,
          ),
          const SizedBox(height: 12),

          // --- Contact Medium ---
          _SectionLabel('Service Medium *'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: opts.media.contains(_contactMedium) ? _contactMedium : null,
            decoration: const InputDecoration(
                labelText: 'Medium',
                prefixIcon: Icon(Icons.swap_horiz, size: 20)),
            items: opts.media
                .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(_shortLabel(m),
                          style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _contactMedium = v),
            isExpanded: true,
          ),
          const SizedBox(height: 12),

          // --- Service Recipients ---
          _SectionLabel('Service Recipients *'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: opts.serviceRecipients.contains(_serviceRecipients)
                ? _serviceRecipients
                : null,
            decoration: const InputDecoration(
                labelText: 'Recipients',
                prefixIcon: Icon(Icons.group_outlined, size: 20)),
            items: opts.serviceRecipients
                .map((r) => DropdownMenuItem(
                      value: r,
                      child: Text(_shortLabel(r),
                          style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _serviceRecipients = v),
            isExpanded: true,
          ),
          const SizedBox(height: 16),

          // --- Counts ---
          Row(children: [
            Expanded(
              child: TextField(
                controller: _providingCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: '# Providing service',
                    prefixIcon: Icon(Icons.person_outline, size: 20)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _receivingCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: '# Receiving service',
                    prefixIcon: Icon(Icons.people_outline, size: 20)),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // --- Team ---
          TextField(
            controller: _teamCtrl,
            decoration: const InputDecoration(
                labelText: 'Team / Program',
                prefixIcon: Icon(Icons.business_outlined, size: 20)),
          ),
          const SizedBox(height: 16),

          // --- Toggles ---
          Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kDivider)),
            child: Column(children: [
              SwitchListTile(
                title: const Text('ABF Reportable Contact',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kText)),
                subtitle: const Text(
                    'Include in activity-based funding reporting',
                    style: TextStyle(fontSize: 11, color: kTextLight)),
                value: _isReportable,
                activeColor: kPrimary,
                onChanged: (v) => setState(() => _isReportable = v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Did Not Attend (DNA)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kText)),
                subtitle: const Text('Patient did not attend this appointment',
                    style: TextStyle(fontSize: 11, color: kTextLight)),
                value: _didNotAttend,
                activeColor: kError,
                onChanged: (v) => setState(() => _didNotAttend = v),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // --- Title ---
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              labelText: 'Note title (optional)',
              hintText: _labelFor(_noteType),
              prefixIcon: const Icon(Icons.title, size: 20),
            ),
          ),
          const SizedBox(height: 10),

          // --- Content ---
          TextField(
            controller: _contentCtrl,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Clinical notes',
              alignLabelWithHint: true,
              prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 100),
                  child: Icon(Icons.notes, size: 20)),
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: const TextStyle(color: kError, fontSize: 12)),
            ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save Contact'),
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _shortLabel(String s) {
    final dashIdx = s.indexOf(' — ');
    if (dashIdx >= 0 && dashIdx < 6) return s.substring(dashIdx + 3);
    return s;
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: kTextLight,
            letterSpacing: 0.2),
      );
}

class _PickerCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickerCard(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kDivider),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: kPrimary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13, color: kText)),
          ]),
        ),
      );
}
