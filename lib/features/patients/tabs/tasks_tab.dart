import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/response_parsers.dart';

/// Provider: tasks for a patient — uses GET /tasks?patientId=X (same API as desktop)
final _tasksProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, patientId) async {
  final data = await api.get('/tasks', params: {'patientId': patientId, 'status': 'open', 'limit': '50'});
  return readMapListEnvelope(
    data,
    preferredKeys: const ['tasks', 'data'],
  );
});

class TasksTab extends ConsumerWidget {
  final String patientId;
  const TasksTab({super.key, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(_tasksProvider(patientId));

    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async => ref.invalidate(_tasksProvider(patientId)),
      child: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (err, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 36, color: kError),
          const SizedBox(height: 8),
          Text(
            'Tasks unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
            style: const TextStyle(color: kTextLight),
            textAlign: TextAlign.center,
          ),
          TextButton(onPressed: () => ref.invalidate(_tasksProvider(patientId)), child: const Text('Retry')),
        ])),
        data: (tasks) {
          if (tasks.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.task_alt, size: 48, color: kSuccess.withAlpha(100)),
                const SizedBox(height: 12),
                const Text('No open tasks', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kText)),
                Text('All tasks completed', style: TextStyle(fontSize: 12, color: kTextLight)),
              ])),
            ]);
          }

          // Group by priority
          final urgent = tasks.where((t) => _isUrgent(t)).toList();
          final normal = tasks.where((t) => !_isUrgent(t)).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (urgent.isNotEmpty) ...[
                _SectionLabel('Urgent', kError),
                ...urgent.map((t) => _TaskCard(task: t)),
                const SizedBox(height: 16),
              ],
              if (normal.isNotEmpty) ...[
                _SectionLabel('Open Tasks', kInfo),
                ...normal.map((t) => _TaskCard(task: t)),
              ],
              const SizedBox(height: 60),
            ],
          );
        },
      ),
    );
  }

  bool _isUrgent(Map<String, dynamic> task) {
    final priority = (task['priority'] ?? '').toString().toLowerCase();
    return priority == 'urgent' || priority == 'high' || priority == 'critical';
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, this.color);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Container(width: 3, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
    ]),
  );
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final title = task['title'] ?? task['description'] ?? 'Task';
    final taskType = (task['taskType'] ?? task['type'] ?? '').toString();
    final assignee = task['assignedToName'] ?? task['assigneeName'] ?? '';
    final dueDate = task['dueAt'] ?? task['dueDate'] ?? '';
    final priority = (task['priority'] ?? 'normal').toString().toLowerCase();
    final isUrgent = priority == 'urgent' || priority == 'high' || priority == 'critical';

    final dt = DateTime.tryParse(dueDate.toString());
    final dueStr = dt != null ? '${dt.day}/${dt.month}/${dt.year}' : '';
    final isOverdue = dt != null && dt.isBefore(DateTime.now());

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isUrgent ? kError.withAlpha(60) : kDivider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
              isUrgent ? Icons.priority_high : Icons.radio_button_unchecked,
              size: 18,
              color: isUrgent ? kError : kTextLight,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText))),
          ]),
          if (taskType.isNotEmpty || assignee.isNotEmpty || dueStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 26),
              child: Wrap(spacing: 12, runSpacing: 4, children: [
                if (taskType.isNotEmpty)
                  _Meta(Icons.category_outlined, _formatType(taskType)),
                if (assignee.isNotEmpty)
                  _Meta(Icons.person_outline, assignee.toString()),
                if (dueStr.isNotEmpty)
                  _Meta(
                    isOverdue ? Icons.warning_amber : Icons.calendar_today,
                    dueStr,
                    color: isOverdue ? kError : null,
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  String _formatType(String type) =>
    type.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w).join(' ');
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _Meta(this.icon, this.text, {this.color});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 13, color: color ?? kTextLight),
    const SizedBox(width: 3),
    Text(text, style: TextStyle(fontSize: 11, color: color ?? kTextLight)),
  ]);
}
