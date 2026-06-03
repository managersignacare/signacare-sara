import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/response_parsers.dart';

/// Fetch all open tasks assigned to the current user — GET /tasks?status=open
final _myTasksProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await api.get('/tasks', params: {'status': 'open', 'limit': '50'});
  return readMapListEnvelope(
    data,
    preferredKeys: const ['tasks', 'data'],
  );
});

class MyTasksScreen extends ConsumerWidget {
  const MyTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(_myTasksProvider);

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('My Tasks'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 22), onPressed: () => ref.invalidate(_myTasksProvider)),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (err, __) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 36, color: kError),
          const SizedBox(height: 8),
          Text(
            'Tasks unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
            style: const TextStyle(color: kTextLight),
            textAlign: TextAlign.center,
          ),
          TextButton(onPressed: () => ref.invalidate(_myTasksProvider), child: const Text('Retry')),
        ])),
        data: (tasks) {
          if (tasks.isEmpty) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.task_alt, size: 48, color: kSuccess.withAlpha(100)),
              const SizedBox(height: 12),
              const Text('All clear', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kText)),
              Text('No open tasks', style: TextStyle(fontSize: 13, color: kTextLight)),
            ]));
          }

          final urgent = tasks.where((t) => _isUrgent(t)).toList();
          final normal = tasks.where((t) => !_isUrgent(t)).toList();

          return RefreshIndicator(
            color: kPrimary,
            onRefresh: () async => ref.invalidate(_myTasksProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (urgent.isNotEmpty) ...[
                  _Label('Urgent', kError),
                  ...urgent.map((t) => _TaskTile(task: t, ref: ref)),
                  const SizedBox(height: 16),
                ],
                if (normal.isNotEmpty) ...[
                  _Label('Open', kInfo),
                  ...normal.map((t) => _TaskTile(task: t, ref: ref)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  bool _isUrgent(Map<String, dynamic> t) {
    final p = (t['priority'] ?? '').toString().toLowerCase();
    return p == 'urgent' || p == 'high' || p == 'critical';
  }
}

class _Label extends StatelessWidget {
  final String text;
  final Color color;
  const _Label(this.text, this.color);

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

class _TaskTile extends StatelessWidget {
  final Map<String, dynamic> task;
  final WidgetRef ref;
  const _TaskTile({required this.task, required this.ref});

  @override
  Widget build(BuildContext context) {
    final title = task['title'] ?? task['description'] ?? 'Task';
    final priority = (task['priority'] ?? 'medium').toString().toLowerCase();
    final isUrgent = priority == 'urgent' || priority == 'high' || priority == 'critical';
    final patientName = task['patientName'] ?? '';
    final dueDate = task['dueAt'] ?? task['dueDate'] ?? '';
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Icon(isUrgent ? Icons.priority_high : Icons.radio_button_unchecked, color: isUrgent ? kError : kTextLight, size: 20),
        title: Text(title.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
        subtitle: Wrap(spacing: 10, children: [
          if (patientName.toString().isNotEmpty) Text(patientName.toString(), style: TextStyle(fontSize: 11, color: kTextLight)),
          if (dueStr.isNotEmpty) Text(dueStr, style: TextStyle(fontSize: 11, color: isOverdue ? kError : kTextLight, fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal)),
        ]),
        trailing: IconButton(
          icon: const Icon(Icons.check_circle_outline, size: 22, color: kSuccess),
          onPressed: () async {
            // Audit Tier 4.2 (HIGH-J2) — the completion call previously
            // silently failed, leaving the clinician thinking the task
            // was closed when it wasn't.
            try {
              await api.patch('/tasks/${task['id']}', data: {'status': 'completed'});
              ref.invalidate(_myTasksProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task completed'), backgroundColor: kSuccess));
              }
            } on DioException catch (e) {
              if (context.mounted) {
                final msg = e.response?.data is Map && (e.response!.data as Map)['message'] is String
                    ? (e.response!.data as Map)['message'] as String
                    : (e.message ?? 'check your connection');
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Could not complete task: $msg'),
                  backgroundColor: kError,
                ));
              }
            }
          },
        ),
      ),
    );
  }
}
