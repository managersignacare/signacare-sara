import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/response_parsers.dart';

/// Full patient record — all demographic, contact, provider, consent fields
final _patientFullProvider =
    FutureProvider.family<Map<String, dynamic>?, String>(
        (ref, patientId) async {
  final data = await api.get('/patients/$patientId');
  return Map<String, dynamic>.from(data as Map);
});

/// Registered contacts (carers, family, support persons)
final _contactsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, patientId) async {
  final data = await api.get('/patients/$patientId/contacts');
  return readMapListEnvelope(
    data,
    preferredKeys: const ['contacts', 'data'],
  );
});

/// Healthcare providers (GP, specialists)
final _providersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, patientId) async {
  final data = await api.get('/patients/$patientId/providers');
  return readMapListEnvelope(
    data,
    preferredKeys: const ['providers', 'data'],
  );
});

class OverviewTab extends ConsumerWidget {
  final String patientId;
  const OverviewTab({super.key, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(_patientFullProvider(patientId));
    final contactsAsync = ref.watch(_contactsProvider(patientId));
    final providersAsync = ref.watch(_providersProvider(patientId));

    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async {
        ref.invalidate(_patientFullProvider(patientId));
        ref.invalidate(_contactsProvider(patientId));
        ref.invalidate(_providersProvider(patientId));
      },
      child: patientAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (_, __) => const Center(child: Text('Failed to load patient')),
        data: (p) {
          if (p == null) return const Center(child: Text('Patient not found'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Patient Details ──
              _Section(
                  icon: Icons.person_outline,
                  title: 'Patient Details',
                  children: [
                    _Row(
                        'Full Name',
                        '${p['givenName'] ?? ''} ${p['familyName'] ?? ''}'
                            .trim()),
                    if (_has(p, 'preferredName'))
                      _Row('Preferred Name', p['preferredName']),
                    if (_has(p, 'dateOfBirth'))
                      _Row('Date of Birth', _formatDob(p['dateOfBirth'])),
                    if (_has(p, 'gender')) _Row('Gender', p['gender']),
                    if (_has(p, 'pronouns')) _Row('Pronouns', p['pronouns']),
                    if (_has(p, 'emrNumber')) _Row('MRN', p['emrNumber']),
                    if (_has(p, 'status')) _Row('Status', p['status']),
                  ]),

              // ── Contact Information ──
              _Section(
                  icon: Icons.phone_outlined,
                  title: 'Contact Information',
                  children: [
                    if (_has(p, 'phoneMobile'))
                      _Row('Mobile', p['phoneMobile']),
                    if (_has(p, 'phoneHome'))
                      _Row('Home Phone', p['phoneHome']),
                    if (_has(p, 'emailPrimary'))
                      _Row('Email', p['emailPrimary']),
                    _Row('Address', _buildAddress(p)),
                  ]),

              // ── Identifiers ──
              _Section(
                  icon: Icons.badge_outlined,
                  title: 'Identifiers',
                  children: [
                    if (_has(p, 'medicareNumber'))
                      _Row('Medicare',
                          '${p['medicareNumber']}${p['medicareIrn'] != null ? ' (IRN: ${p['medicareIrn']})' : ''}'),
                    if (_has(p, 'medicareExpiry'))
                      _Row('Medicare Expiry', _formatDate(p['medicareExpiry'])),
                    if (_has(p, 'dvaNumber'))
                      _Row('DVA Number',
                          '${p['dvaNumber']}${p['dvaCardType'] != null ? ' (${p['dvaCardType']})' : ''}'),
                    if (_has(p, 'ihi')) _Row('IHI', p['ihi']),
                    if (_has(p, 'healthFundName'))
                      _Row('Health Fund',
                          '${p['healthFundName']}${_has(p, 'healthFundNumber') ? ' — ${p['healthFundNumber']}' : ''}'),
                  ]),

              // ── Interpreter ──
              if (p['interpreterRequired'] == true)
                _Section(
                    icon: Icons.translate,
                    title: 'Interpreter',
                    color: kWarning,
                    children: [
                      _Row('Required', 'Yes'),
                      if (_has(p, 'interpreterLanguage'))
                        _Row('Language', p['interpreterLanguage']),
                    ]),

              // ── ATSI Status ──
              if (_has(p, 'atsiStatus'))
                _Section(
                    icon: Icons.people_outline,
                    title: 'Indigenous Status',
                    children: [
                      _Row('ATSI Status', p['atsiStatus']),
                    ]),

              // ── Next of Kin ──
              _Section(
                  icon: Icons.family_restroom_outlined,
                  title: 'Next of Kin',
                  children: [
                    if (_has(p, 'nokName')) _Row('Name', p['nokName']),
                    if (_has(p, 'nokRelationship'))
                      _Row('Relationship', p['nokRelationship']),
                    if (_has(p, 'nokPhone')) _Row('Phone', p['nokPhone']),
                    if (!_has(p, 'nokName'))
                      const _EmptyRow('No next of kin recorded'),
                  ]),

              // ── Emergency Contact ──
              _Section(
                  icon: Icons.emergency_outlined,
                  title: 'Emergency Contact',
                  children: [
                    if (_has(p, 'emergencyContactName'))
                      _Row('Name', p['emergencyContactName']),
                    if (_has(p, 'emergencyContactRelationship'))
                      _Row('Relationship', p['emergencyContactRelationship']),
                    if (_has(p, 'emergencyContactPhone'))
                      _Row('Phone', p['emergencyContactPhone']),
                    if (!_has(p, 'emergencyContactName'))
                      const _EmptyRow('No emergency contact recorded'),
                  ]),

              // ── GP / Primary Care ──
              _Section(
                  icon: Icons.local_hospital_outlined,
                  title: 'GP / Primary Care',
                  children: [
                    if (_has(p, 'gpName')) _Row('Name', p['gpName']),
                    if (_has(p, 'gpPractice'))
                      _Row('Practice', p['gpPractice']),
                    if (_has(p, 'gpPhone')) _Row('Phone', p['gpPhone']),
                    if (_has(p, 'gpFax')) _Row('Fax', p['gpFax']),
                    if (_has(p, 'gpEmail')) _Row('Email', p['gpEmail']),
                    if (_has(p, 'gpProviderNumber'))
                      _Row('Provider No.', p['gpProviderNumber']),
                    if (_has(p, 'gpAddressStreet'))
                      _Row(
                          'Address',
                          [
                            p['gpAddressStreet'],
                            p['gpAddressSuburb'],
                            p['gpAddressState'],
                            p['gpAddressPostcode']
                          ]
                              .where(
                                  (s) => s != null && s.toString().isNotEmpty)
                              .join(', ')),
                    if (!_has(p, 'gpName')) const _EmptyRow('No GP recorded'),
                  ]),

              // ── Other Healthcare Providers ──
              _Section(
                  icon: Icons.medical_services_outlined,
                  title: 'Healthcare Providers',
                  children: [
                    ...providersAsync.when(
                      loading: () => [
                        const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                                color: kPrimary, strokeWidth: 2))
                      ],
                      error: (_, __) => [const _EmptyRow('Failed to load')],
                      data: (providers) {
                        if (providers.isEmpty)
                          return [const _EmptyRow('No other providers')];
                        return providers
                            .map((pr) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                        color: kSurface,
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              pr['providerName'] ??
                                                  pr['name'] ??
                                                  'Unknown',
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: kText)),
                                          if (pr['providerType'] != null ||
                                              pr['specialty'] != null)
                                            Text(
                                                pr['providerType'] ??
                                                    pr['specialty'] ??
                                                    '',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: kTextLight)),
                                          if (pr['phone'] != null)
                                            Text('Ph: ${pr['phone']}',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: kTextLight)),
                                          if (pr['email'] != null)
                                            Text(pr['email'],
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: kTextLight)),
                                        ]),
                                  ),
                                ))
                            .toList();
                      },
                    ),
                  ]),

              // ── Registered Contacts / Support Persons ──
              _Section(
                  icon: Icons.contacts_outlined,
                  title: 'Support Persons & Carers',
                  children: [
                    ...contactsAsync.when(
                      loading: () => [
                        const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                                color: kPrimary, strokeWidth: 2))
                      ],
                      error: (_, __) => [const _EmptyRow('Failed to load')],
                      data: (contacts) {
                        if (contacts.isEmpty)
                          return [
                            const _EmptyRow('No support persons recorded')
                          ];
                        return contacts
                            .map((c) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                        color: kSurface,
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Icon(
                                                _contactIcon(
                                                    c['relationship'] ??
                                                        c['contactType'] ??
                                                        ''),
                                                size: 16,
                                                color: kInfo),
                                            const SizedBox(width: 6),
                                            Expanded(
                                                child: Text(
                                                    c['name'] ??
                                                        c['contactName'] ??
                                                        'Unknown',
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: kText))),
                                          ]),
                                          if (c['relationship'] != null ||
                                              c['contactType'] != null)
                                            Text(
                                                c['relationship'] ??
                                                    c['contactType'] ??
                                                    '',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: kTextLight)),
                                          if (c['phone'] != null ||
                                              c['phoneNumber'] != null)
                                            Text(
                                                'Ph: ${c['phone'] ?? c['phoneNumber']}',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: kTextLight)),
                                          if (c['email'] != null)
                                            Text(c['email'],
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: kTextLight)),
                                        ]),
                                  ),
                                ))
                            .toList();
                      },
                    ),
                  ]),

              // ── Consent ──
              _Section(
                  icon: Icons.verified_user_outlined,
                  title: 'Consent',
                  children: [
                    _ConsentRow('Consent to Treatment',
                        p['consentToTreatment'] == true),
                    _ConsentRow('Consent for Research',
                        p['consentForResearch'] == true),
                    _ConsentRow(
                        'Share with GP', p['consentToShareWithGp'] == true),
                    _ConsentRow('Share with Carer',
                        p['consentToShareWithCarer'] == true),
                  ]),

              const SizedBox(height: 60),
            ],
          );
        },
      ),
    );
  }

  bool _has(Map<String, dynamic> p, String key) {
    final v = p[key];
    return v != null && v.toString().isNotEmpty;
  }

  String _buildAddress(Map<String, dynamic> p) {
    final parts = [
      p['addressStreet'],
      p['addressSuburb'],
      p['addressState'],
      p['addressPostcode']
    ]
        .where((s) => s != null && s.toString().isNotEmpty)
        .map((s) => s.toString());
    return parts.isEmpty ? 'Not recorded' : parts.join(', ');
  }

  String _formatDob(String? dob) {
    if (dob == null) return '';
    final dt = DateTime.tryParse(dob);
    if (dt == null) return dob;
    final age = DateTime.now().difference(dt).inDays ~/ 365;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ($age years)';
  }

  String _formatDate(String? d) {
    if (d == null) return '';
    final dt = DateTime.tryParse(d);
    if (dt == null) return d;
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  IconData _contactIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('carer')) return Icons.favorite_outline;
    if (t.contains('nok') || t.contains('kin')) return Icons.family_restroom;
    if (t.contains('emergency')) return Icons.emergency;
    if (t.contains('guardian')) return Icons.shield_outlined;
    return Icons.person_outline;
  }
}

// ── Section Card ──

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? color;
  final List<Widget> children;
  const _Section(
      {required this.icon,
      required this.title,
      required this.children,
      this.color});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: color != null ? color!.withAlpha(60) : kDivider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              Icon(icon, size: 16, color: color ?? const Color(0xFFF0852C)),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color ?? kText)),
            ]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children),
          ),
        ]),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: kTextLight,
                      fontWeight: FontWeight.w500))),
          Expanded(
              child: Text(value ?? '—',
                  style: const TextStyle(fontSize: 13, color: kText))),
        ]),
      );
}

class _EmptyRow extends StatelessWidget {
  final String msg;
  const _EmptyRow(this.msg);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(msg,
            style: TextStyle(
                fontSize: 12, color: kTextLight, fontStyle: FontStyle.italic)),
      );
}

class _ConsentRow extends StatelessWidget {
  final String label;
  final bool granted;
  const _ConsentRow(this.label, this.granted);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(granted ? Icons.check_circle : Icons.cancel,
              size: 16, color: granted ? kSuccess : kError),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: kText))),
          Text(granted ? 'Yes' : 'No',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: granted ? kSuccess : kError)),
        ]),
      );
}
