import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/response_parsers.dart';

/// Provider to fetch the review status for a patient
final _reviewStatusProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, patientId) async {
  final data = await api.get('/patients/review-status');
  final map = readMapEnvelope(data, preferredKeys: const ['data']);
  final overdue = map['overdue'];
  if (overdue is Map && overdue.containsKey(patientId)) {
    final row = overdue[patientId];
    if (row is Map) return Map<String, dynamic>.from(row);
  }
  return null;
});

/// Provider to fetch review-type notes for a patient
final _reviewNotesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, patientId) async {
  final data = await api.get('/clinical-notes/patient/$patientId');
  final list = readMapListEnvelope(
    data,
    preferredKeys: const ['data', 'notes'],
  );
  return list.where((n) {
    final type = (n['noteType'] ?? n['note_type'] ?? '').toString().toLowerCase();
    return type.contains('review') || type == '91_day_review' || type == '91-day-review';
  }).toList();
});

/// Provider to fetch current medications for the review summary
final _reviewMedsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, patientId) async {
  final data = await api.get('/medications/patients/$patientId/medications');
  final list = readMapListEnvelope(
    data,
    preferredKeys: const ['medications', 'data'],
  );
  return list.where((m) => m['status'] == 'active').toList();
});

/// Provider to fetch active alerts
final _reviewAlertsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, patientId) async {
  final data = await api.get('/patients/$patientId/alerts');
  final list = readMapListEnvelope(
    data,
    preferredKeys: const ['alerts', 'data'],
  );
  return list.where((a) => a['isActive'] == true).toList();
});

class Review91DayTab extends ConsumerWidget {
  final String patientId;
  const Review91DayTab({super.key, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(_reviewStatusProvider(patientId));
    final notesAsync = ref.watch(_reviewNotesProvider(patientId));
    final medsAsync = ref.watch(_reviewMedsProvider(patientId));
    final alertsAsync = ref.watch(_reviewAlertsProvider(patientId));

    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async {
        ref.invalidate(_reviewStatusProvider(patientId));
        ref.invalidate(_reviewNotesProvider(patientId));
        ref.invalidate(_reviewMedsProvider(patientId));
        ref.invalidate(_reviewAlertsProvider(patientId));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Review Status Banner ──
          statusAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (err, __) => _ErrorCard(
              msg: 'Review status unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
            ),
            data: (status) => _ReviewStatusBanner(status: status),
          ),
          const SizedBox(height: 16),

          // ── Current Medications Summary ──
          _SectionHeader(icon: Icons.medication_outlined, title: 'Current Medications'),
          const SizedBox(height: 8),
          medsAsync.when(
            loading: () => const _LoadingCard(),
            error: (_, __) => const _ErrorCard(msg: 'Failed to load medications'),
            data: (meds) => meds.isEmpty
                ? const _EmptyCard(msg: 'No active medications')
                : Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kDivider)),
                    child: Column(
                      children: meds.map((m) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.medication, size: 18, color: kPrimary),
                        title: Text(
                          m['drugLabel'] ?? m['genericName'] ?? 'Unknown',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${m['dose'] ?? ''} ${m['route'] ?? ''} ${m['frequency'] ?? ''}'.trim(),
                          style: TextStyle(fontSize: 12, color: kTextLight),
                        ),
                      )).toList(),
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // ── Active Alerts Summary ──
          _SectionHeader(icon: Icons.warning_amber_rounded, title: 'Active Alerts'),
          const SizedBox(height: 8),
          alertsAsync.when(
            loading: () => const _LoadingCard(),
            error: (_, __) => const _ErrorCard(msg: 'Failed to load alerts'),
            data: (alerts) => alerts.isEmpty
                ? const _EmptyCard(msg: 'No active alerts')
                : Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kDivider)),
                    child: Column(
                      children: alerts.map((a) {
                        final severity = (a['severity'] ?? 'low').toString();
                        final color = severity == 'critical' || severity == 'high' ? kError : severity == 'medium' ? kWarning : kInfo;
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.flag_rounded, size: 18, color: color),
                          title: Text(a['title'] ?? 'Alert', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: a['managementPlan'] != null
                              ? Text(a['managementPlan'], style: TextStyle(fontSize: 11, color: kTextLight), maxLines: 2, overflow: TextOverflow.ellipsis)
                              : null,
                          trailing: Chip(
                            label: Text(severity, style: TextStyle(fontSize: 10, color: color)),
                            backgroundColor: color.withOpacity(0.1),
                            side: BorderSide.none,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // ── Previous Reviews ──
          _SectionHeader(icon: Icons.history_rounded, title: 'Previous Reviews'),
          const SizedBox(height: 8),
          notesAsync.when(
            loading: () => const _LoadingCard(),
            error: (_, __) => const _ErrorCard(msg: 'Failed to load reviews'),
            data: (notes) => notes.isEmpty
                ? const _EmptyCard(msg: 'No previous reviews found')
                : Column(
                    children: notes.take(10).map((n) {
                      final dt = DateTime.tryParse(n['noteDateTime'] ?? n['createdAt'] ?? '');
                      final dateStr = dt != null
                          ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
                          : '—';
                      final status = (n['status'] ?? 'draft').toString();
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kDivider)),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                          leading: Icon(
                            status == 'signed' ? Icons.verified_rounded : Icons.edit_note,
                            color: status == 'signed' ? kSuccess : kWarning,
                            size: 20,
                          ),
                          title: Text(n['noteType'] ?? 'Review', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Row(children: [
                            Text(dateStr, style: TextStyle(fontSize: 11, color: kTextLight)),
                            if (n['authorName'] != null) ...[
                              Text(' — ', style: TextStyle(fontSize: 11, color: kTextLight)),
                              Text(n['authorName'], style: TextStyle(fontSize: 11, color: kTextLight)),
                            ],
                          ]),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(
                                n['content'] ?? n['soapAssessment'] ?? 'No content',
                                style: TextStyle(fontSize: 12, color: kText, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 80), // FAB clearance
        ],
      ),
    );
  }
}

// ── Helper Widgets ──

class _ReviewStatusBanner extends StatelessWidget {
  final Map<String, dynamic>? status;
  const _ReviewStatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final daysMedical = status?['daysSinceMedical'] as int?;
    final daysClinician = status?['daysSinceClinician'] as int?;
    final medicalOverdue = status?['medical'] == true;
    final clinicianOverdue = status?['clinician'] == true;

    final isOverdue = medicalOverdue || clinicianOverdue;
    final bannerColor = isOverdue ? kError : kSuccess;
    final bannerIcon = isOverdue ? Icons.schedule_rounded : Icons.check_circle_outline;
    final bannerText = isOverdue ? 'Review Overdue' : 'Reviews Up to Date';

    return Card(
      elevation: 0,
      color: bannerColor.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(bannerIcon, color: bannerColor, size: 22),
            const SizedBox(width: 10),
            Text(bannerText, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: bannerColor)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _ReviewMetric(
              label: 'Medical Review',
              days: daysMedical,
              isOverdue: medicalOverdue,
            )),
            const SizedBox(width: 16),
            Expanded(child: _ReviewMetric(
              label: 'Clinician Review',
              days: daysClinician,
              isOverdue: clinicianOverdue,
            )),
          ]),
        ]),
      ),
    );
  }
}

class _ReviewMetric extends StatelessWidget {
  final String label;
  final int? days;
  final bool isOverdue;
  const _ReviewMetric({required this.label, this.days, required this.isOverdue});

  @override
  Widget build(BuildContext context) {
    final color = isOverdue ? kError : kSuccess;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: kTextLight, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          days != null ? '$days days ago' : 'No record',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
        ),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: kPrimary),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
    ]);
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const Card(
    elevation: 0, child: Padding(padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2))));
}

class _ErrorCard extends StatelessWidget {
  final String msg;
  const _ErrorCard({required this.msg});

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0, color: kError.withOpacity(0.05),
    child: Padding(padding: const EdgeInsets.all(16),
    child: Text(msg, style: TextStyle(fontSize: 12, color: kError))));
}

class _EmptyCard extends StatelessWidget {
  final String msg;
  const _EmptyCard({required this.msg});

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0, color: kSurface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kDivider)),
    child: Padding(padding: const EdgeInsets.all(20),
    child: Center(child: Text(msg, style: TextStyle(fontSize: 13, color: kTextLight)))));
}
