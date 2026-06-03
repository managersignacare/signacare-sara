import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/response_parsers.dart';

/// Fetch message threads — GET /messages/threads (same as desktop)
final _threadsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await api.get('/messages/threads');
  return readMapListEnvelope(
    data,
    preferredKeys: const ['threads', 'data'],
  );
});

/// Fetch inbox messages — GET /messages/inbox
final _inboxProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await api.get('/messages/inbox');
  return readMapListEnvelope(
    data,
    preferredKeys: const ['messages', 'data'],
  );
});

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxAsync = ref.watch(_inboxProvider);
    final threadsAsync = ref.watch(_threadsProvider);

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 22), onPressed: () {
            ref.invalidate(_inboxProvider);
            ref.invalidate(_threadsProvider);
          }),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [
            Tab(text: 'Inbox'),
            Tab(text: 'Threads'),
          ]),
          Expanded(child: TabBarView(children: [
            // Inbox
            inboxAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
              error: (err, __) => Center(
                child: Text(
                  'Inbox unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
                  textAlign: TextAlign.center,
                ),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.inbox_outlined, size: 48, color: kTextLight.withAlpha(100)),
                    const SizedBox(height: 12),
                    const Text('No messages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kText)),
                    Text('Messages from other staff will appear here', style: TextStyle(fontSize: 12, color: kTextLight)),
                  ]));
                }
                return RefreshIndicator(
                  color: kPrimary,
                  onRefresh: () async => ref.invalidate(_inboxProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _MessageCard(message: messages[i], ref: ref),
                  ),
                );
              },
            ),
            // Threads
            threadsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
              error: (err, __) => Center(
                child: Text(
                  'Threads unavailable: ${readApiErrorMessage(err, fallback: 'check access')}',
                  textAlign: TextAlign.center,
                ),
              ),
              data: (threads) {
                if (threads.isEmpty) {
                  return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.forum_outlined, size: 48, color: kTextLight.withAlpha(100)),
                    const SizedBox(height: 12),
                    const Text('No threads', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kText)),
                    Text('Start a conversation from a patient record', style: TextStyle(fontSize: 12, color: kTextLight)),
                  ]));
                }
                return RefreshIndicator(
                  color: kPrimary,
                  onRefresh: () async => ref.invalidate(_threadsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: threads.length,
                    itemBuilder: (_, i) => _ThreadCard(thread: threads[i]),
                  ),
                );
              },
            ),
          ])),
        ]),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final Map<String, dynamic> message;
  final WidgetRef ref;
  const _MessageCard({required this.message, required this.ref});

  @override
  Widget build(BuildContext context) {
    final subject = message['subject'] ?? '(no subject)';
    final body = (message['body'] ?? '').toString();
    final preview = body.length > 80 ? '${body.substring(0, 80)}...' : body;
    final senderName = message['senderName'] ?? 'Unknown';
    final isRead = message['isRead'] == true;
    final isUrgent = message['isUrgent'] == true;
    final dt = DateTime.tryParse((message['createdAt'] ?? '').toString());
    final timeStr = dt != null ? _formatTime(dt) : '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isUrgent ? kError.withAlpha(60) : kDivider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          // Mark as read. Failure here is non-blocking (the user still
          // reads the thread) but audit Tier 4.2 requires visibility —
          // log so a systematic backend failure isn't invisible.
          if (!isRead && message['id'] != null) {
            try {
              await api.patch('/messages/${message['id']}/read', data: {});
            } on DioException catch (e) {
              developer.log(
                'mark-as-read failed for message ${message['id']}',
                name: 'sara.messaging',
                error: e.message,
              );
            }
            ref.invalidate(_inboxProvider);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (!isRead) Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle)),
              if (isUrgent) Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: kError.withAlpha(20), borderRadius: BorderRadius.circular(4)),
                child: const Text('URGENT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: kError)),
              ),
              Expanded(child: Text(senderName.toString(),
                style: TextStyle(fontSize: 12, fontWeight: isRead ? FontWeight.w400 : FontWeight.w700, color: kText))),
              Text(timeStr, style: TextStyle(fontSize: 10, color: kTextLight)),
            ]),
            const SizedBox(height: 4),
            Text(subject.toString(), style: TextStyle(fontSize: 13, fontWeight: isRead ? FontWeight.w500 : FontWeight.w700, color: kText)),
            if (preview.isNotEmpty) Text(preview, style: TextStyle(fontSize: 11, color: kTextLight, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }
}

class _ThreadCard extends StatelessWidget {
  final Map<String, dynamic> thread;
  const _ThreadCard({required this.thread});

  @override
  Widget build(BuildContext context) {
    final subject = thread['subject'] ?? '(no subject)';
    final messageCount = thread['messageCount'] ?? 0;
    final unreadCount = thread['unreadCount'] ?? 0;
    final dt = DateTime.tryParse((thread['lastMessageAt'] ?? thread['updatedAt'] ?? '').toString());
    final timeStr = dt != null ? '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}' : '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: kDivider)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          radius: 18, backgroundColor: unreadCount > 0 ? kPrimary.withAlpha(25) : kSurface,
          child: Icon(Icons.forum, size: 18, color: unreadCount > 0 ? kPrimary : kTextLight),
        ),
        title: Text(subject.toString(), style: TextStyle(fontSize: 13, fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w500, color: kText)),
        subtitle: Text('$messageCount messages · $timeStr', style: TextStyle(fontSize: 11, color: kTextLight)),
        trailing: unreadCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(10)),
              child: Text('$unreadCount', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
            )
          : null,
      ),
    );
  }
}
