import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/response_parsers.dart';

/// Fetch recent pathology results — GET /patients/:id/pathology
final _pathologyProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, patientId) async {
  final data = await api.get('/patients/$patientId/pathology');
  return readMapListEnvelope(
    data,
    preferredKeys: const ['results', 'data', 'pathology'],
  );
});

class PathologyTab extends ConsumerWidget {
  final String patientId;
  const PathologyTab({super.key, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathAsync = ref.watch(_pathologyProvider(patientId));

    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async => ref.invalidate(_pathologyProvider(patientId)),
      child: pathAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (err, __) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: kError, size: 36),
          const SizedBox(height: 8),
          Text(
            'Pathology unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
            style: const TextStyle(color: kTextLight),
            textAlign: TextAlign.center,
          ),
          TextButton(onPressed: () => ref.invalidate(_pathologyProvider(patientId)), child: const Text('Retry')),
        ])),
        data: (results) {
          if (results.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.science_outlined, size: 48, color: kTextLight.withAlpha(100)),
                const SizedBox(height: 12),
                const Text('No pathology results', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kText)),
                Text('Results will appear here when available', style: TextStyle(fontSize: 12, color: kTextLight)),
              ])),
            ]);
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
            itemCount: results.length,
            itemBuilder: (_, i) => _PathologyCard(result: results[i]),
          );
        },
      ),
    );
  }
}

class _PathologyCard extends StatefulWidget {
  final Map<String, dynamic> result;
  const _PathologyCard({required this.result});

  @override
  State<_PathologyCard> createState() => _PathologyCardState();
}

class _PathologyCardState extends State<_PathologyCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final testName = r['testName'] ?? r['name'] ?? r['title'] ?? 'Pathology Result';
    final status = (r['status'] ?? r['resultStatus'] ?? '').toString();
    final collectedDate = r['collectedDate'] ?? r['collectedAt'] ?? r['dateCollected'] ?? '';
    final reportedDate = r['reportedDate'] ?? r['reportedAt'] ?? r['dateReported'] ?? r['createdAt'] ?? '';
    final result = r['result'] ?? r['resultValue'] ?? '';
    final units = r['units'] ?? r['resultUnits'] ?? '';
    final refRange = r['referenceRange'] ?? r['refRange'] ?? '';
    final isAbnormal = r['isAbnormal'] == true || status.toLowerCase().contains('abnormal');
    final notes = r['notes'] ?? r['comments'] ?? r['interpretation'] ?? '';
    final labName = r['labName'] ?? r['laboratory'] ?? '';
    final orderingDoctor = r['orderingDoctor'] ?? r['requestedBy'] ?? '';

    final dt = DateTime.tryParse(collectedDate.toString());
    final dateStr = dt != null ? '${dt.day}/${dt.month}/${dt.year}' : '';
    final reportDt = DateTime.tryParse(reportedDate.toString());
    final reportStr = reportDt != null ? '${reportDt.day}/${reportDt.month}/${reportDt.year}' : '';

    final statusColor = isAbnormal ? kError : status.toLowerCase() == 'final' ? kSuccess : kInfo;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isAbnormal ? kError.withAlpha(60) : kDivider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.science, size: 18, color: isAbnormal ? kError : kPrimary),
              const SizedBox(width: 8),
              Expanded(child: Text(testName.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText))),
              if (status.isNotEmpty) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withAlpha(20), borderRadius: BorderRadius.circular(4)),
                child: Text(status, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: statusColor)),
              ),
              const SizedBox(width: 4),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: kTextLight),
            ]),
            const SizedBox(height: 6),
            // Result value + date row
            Row(children: [
              if (result.toString().isNotEmpty) ...[
                Text(result.toString(), style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: isAbnormal ? kError : kText,
                )),
                if (units.toString().isNotEmpty) Text(' $units', style: TextStyle(fontSize: 11, color: kTextLight)),
                if (refRange.toString().isNotEmpty) Text('  (ref: $refRange)', style: TextStyle(fontSize: 10, color: kTextLight)),
                const Spacer(),
              ],
              if (dateStr.isNotEmpty) Text(dateStr, style: TextStyle(fontSize: 11, color: kTextLight)),
            ]),
            // Expanded details
            if (_expanded) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              if (reportStr.isNotEmpty) _Detail('Reported', reportStr),
              if (labName.toString().isNotEmpty) _Detail('Laboratory', labName.toString()),
              if (orderingDoctor.toString().isNotEmpty) _Detail('Ordered by', orderingDoctor.toString()),
              if (notes.toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(6)),
                  child: Text(notes.toString(), style: const TextStyle(fontSize: 11, color: kText, height: 1.4)),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final String label, value;
  const _Detail(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 11, color: kTextLight))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12, color: kText))),
    ]),
  );
}
