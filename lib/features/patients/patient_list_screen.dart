import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/models/patient.dart';
import '../../core/services/sync_service.dart';
import 'patient_detail_screen.dart';

// Provider with search query
final _searchQueryProvider = StateProvider<String>((_) => '');
final _patientsProvider = FutureProvider.family<List<Patient>, String>((ref, query) {
  final sync = ref.read(syncServiceProvider);
  return sync.fetchPatients(search: query.isEmpty ? null : query);
});

class PatientListScreen extends ConsumerStatefulWidget {
  const PatientListScreen({super.key});

  @override
  ConsumerState<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends ConsumerState<PatientListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (value == _searchCtrl.text) {
        setState(() => _query = value.trim());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(_patientsProvider(_query));

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Patients'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Search by name or MRN…',
                hintStyle: TextStyle(color: kTextLight, fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20, color: kTextLight),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); })
                    : null,
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kDivider)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
        ),
      ),
      body: patientsAsync.when(
        loading: () => _PatientListSkeleton(),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.cloud_off, color: kTextLight, size: 48),
            const SizedBox(height: 12),
            Text('Unable to load patients', style: SignacareText.body),
            const SizedBox(height: 6),
            Text(e.toString(), style: SignacareText.caption, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => ref.invalidate(_patientsProvider), child: const Text('Retry')),
          ]),
        ),
        data: (patients) {
          if (patients.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.person_search, color: kTextLight, size: 56),
                const SizedBox(height: 12),
                Text(_query.isEmpty ? 'No patients found' : 'No results for "$_query"', style: SignacareText.body),
              ]),
            );
          }
          return RefreshIndicator(
            color: kPrimary,
            onRefresh: () async => ref.invalidate(_patientsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: patients.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _PatientCard(
                patient: patients[i],
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PatientDetailScreen(patientId: patients[i].id))),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final Patient patient;
  final VoidCallback onTap;
  const _PatientCard({required this.patient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dob = DateTime.tryParse(patient.dateOfBirth);
    final dobStr = dob != null
        ? '${dob.day.toString().padLeft(2, '0')}/${dob.month.toString().padLeft(2, '0')}/${dob.year}'
        : '—';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kDivider),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22, backgroundColor: kPrimary.withOpacity(0.12),
              child: Text(
                '${patient.givenName.isNotEmpty ? patient.givenName[0] : '?'}${patient.familyName.isNotEmpty ? patient.familyName[0] : ''}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kPrimary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(patient.fullName, style: SignacareText.title.copyWith(fontSize: 15)),
                const SizedBox(height: 3),
                Row(children: [
                  if (patient.emrNumber != null)
                    _Tag('MRN: ${patient.emrNumber!}', kInfo),
                  const SizedBox(width: 6),
                  _Tag('DOB: $dobStr', kTextLight),
                  const SizedBox(width: 6),
                  if (patient.age > 0)
                    _Tag('${patient.age}y', kTextLight),
                ]),
              ]),
            ),
            _StatusChip(patient.status),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 11, color: color));
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _PatientListSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, __) => Container(
        height: 72, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kDivider)),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: kDivider, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 13, width: 160, color: kDivider, margin: const EdgeInsets.only(bottom: 6)),
            Container(height: 10, width: 100, color: kDivider),
          ])),
        ]),
      ),
    );
  }
}
