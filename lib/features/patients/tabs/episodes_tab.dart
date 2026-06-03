import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/response_parsers.dart';

/// Fetch episodes for patient
final _episodesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, patientId) async {
  final data = await api.get('/episodes/patient/$patientId');
  return readMapListEnvelope(
    data,
    preferredKeys: const ['data', 'episodes'],
  );
});

/// Fetch recent 10 notes for patient — GET /clinical-notes/patient/:id
final _recentNotesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, patientId) async {
  final data = await api
      .get('/clinical-notes/patient/$patientId', params: {'limit': '10'});
  return readMapListEnvelope(
    data,
    preferredKeys: const ['data', 'notes'],
  );
});

class EpisodesTab extends ConsumerWidget {
  final String patientId;
  const EpisodesTab({super.key, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodesAsync = ref.watch(_episodesProvider(patientId));
    final notesAsync = ref.watch(_recentNotesProvider(patientId));

    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async {
        ref.invalidate(_episodesProvider(patientId));
        ref.invalidate(_recentNotesProvider(patientId));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Episodes ──
          _Header(Icons.folder_outlined, 'Episodes'),
          const SizedBox(height: 8),
          episodesAsync.when(
            loading: () => const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: kPrimary, strokeWidth: 2))),
            error: (err, __) => _Empty(
                'Episodes unavailable: ${readApiErrorMessage(err, fallback: 'Failed to load episodes')}'),
            data: (episodes) {
              if (episodes.isEmpty) return const _Empty('No episodes');
              return Column(
                  children:
                      episodes.map((e) => _EpisodeCard(episode: e)).toList());
            },
          ),
          const SizedBox(height: 20),

          // ── Recent 10 Notes ──
          _Header(Icons.description_outlined, 'Recent Notes (last 10)'),
          const SizedBox(height: 8),
          notesAsync.when(
            loading: () => const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: kPrimary, strokeWidth: 2))),
            error: (err, __) => _Empty(
                'Notes unavailable: ${readApiErrorMessage(err, fallback: 'check access')}'),
            data: (notes) {
              if (notes.isEmpty) return const _Empty('No notes');
              return Column(
                  children: notes.map((n) => _NoteCard(note: n)).toList());
            },
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final Map<String, dynamic> episode;
  const _EpisodeCard({required this.episode});

  @override
  Widget build(BuildContext context) {
    final title = episode['title'] ?? episode['presentingProblem'] ?? 'Episode';
    final type = episode['episodeType'] ?? episode['type'] ?? '';
    final status = (episode['status'] ?? '').toString();
    final clinician = episode['primaryClinicianName'] ?? '';
    final diagnosis = episode['primaryDiagnosis'] ?? '';
    final startDate = episode['startDate'] ?? episode['createdAt'] ?? '';
    final dt = DateTime.tryParse(startDate.toString());
    final dateStr = dt != null ? '${dt.day}/${dt.month}/${dt.year}' : '';

    final isOpen = status == 'open';
    final statusColor = isOpen ? kSuccess : kTextLight;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: kDivider)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                    color: isOpen ? kPrimary : kTextLight,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title.toString(),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kText)),
                  if (type.toString().isNotEmpty)
                    Text(type.toString(),
                        style: TextStyle(fontSize: 11, color: kTextLight)),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: statusColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(status,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor)),
            ),
          ]),
          if (diagnosis.toString().isNotEmpty ||
              clinician.toString().isNotEmpty ||
              dateStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 13),
              child: Wrap(spacing: 12, runSpacing: 4, children: [
                if (diagnosis.toString().isNotEmpty)
                  _Meta(
                      Icons.medical_information_outlined, diagnosis.toString()),
                if (clinician.toString().isNotEmpty)
                  _Meta(Icons.person_outline, clinician.toString()),
                if (dateStr.isNotEmpty) _Meta(Icons.calendar_today, dateStr),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _NoteCard extends StatefulWidget {
  final Map<String, dynamic> note;
  const _NoteCard({required this.note});

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    final noteType = (n['noteType'] ?? 'progress').toString();
    final content = (n['content'] ?? n['soapAssessment'] ?? '').toString();
    final authorName = n['authorName'] ?? '';
    final status = (n['status'] ?? 'draft').toString();
    final dt = DateTime.tryParse(
        (n['noteDateTime'] ?? n['createdAt'] ?? '').toString());
    final dateStr = dt != null
        ? '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';

    final typeLabel = noteType
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
        .join(' ');
    final statusColor = status == 'signed' ? kSuccess : kWarning;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: _expanded ? kPrimary : kDivider)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: kPrimary.withAlpha(20),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(typeLabel,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kPrimary)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: statusColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(status.toUpperCase(),
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: statusColor)),
              ),
              const Spacer(),
              Text(dateStr, style: TextStyle(fontSize: 10, color: kTextLight)),
              const SizedBox(width: 4),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16, color: kTextLight),
            ]),
            if (authorName.toString().isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(authorName.toString(),
                      style: TextStyle(fontSize: 11, color: kTextLight))),
            if (_expanded && content.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: kSurface, borderRadius: BorderRadius.circular(8)),
                child: Text(content,
                    style: const TextStyle(
                        fontSize: 12, color: kText, height: 1.5)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final IconData icon;
  final String title;
  const _Header(this.icon, this.title);

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: const Color(0xFFF0852C)),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
      ]);
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta(this.icon, this.text);

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: kTextLight),
        const SizedBox(width: 3),
        Flexible(
            child: Text(text,
                style: TextStyle(fontSize: 11, color: kTextLight),
                overflow: TextOverflow.ellipsis)),
      ]);
}

class _Empty extends StatelessWidget {
  final String msg;
  const _Empty(this.msg);

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: kSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kDivider)),
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
                child: Text(msg,
                    style: TextStyle(fontSize: 12, color: kTextLight)))),
      );
}
