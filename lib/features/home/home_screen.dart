import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/api/api_client.dart';
import '../patients/patient_list_screen.dart';
import '../drafts/drafts_screen.dart';
import '../tasks/my_tasks_screen.dart';
import '../messaging/inbox_screen.dart';
import '../calendar/calendar_screen.dart';
import '../auth/login_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  final _pages = const [
    _DashboardPage(),
    PatientListScreen(),
    CalendarScreen(),
    DraftsScreen(),
    _ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Patients'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), activeIcon: Icon(Icons.calendar_month), label: 'Calendar'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note_outlined), activeIcon: Icon(Icons.edit_note), label: 'Drafts'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// ── Dashboard ──────────────────────────────────────────────────────────────────

class _DashboardPage extends ConsumerWidget {
  const _DashboardPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: kSurface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 110,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              title: Row(
                children: [
                  SvgPicture.asset('assets/signacare-logo.svg', width: 22, height: 22, colorFilter: const ColorFilter.mode(Color(0xFF1565C0), BlendMode.srcIn)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Good ${_greeting()}, ${user?.givenName ?? 'Clinician'}',
                          style: const TextStyle(fontSize: 12, color: kTextLight, fontWeight: FontWeight.w400, height: 1.1),
                          overflow: TextOverflow.ellipsis),
                        const Text('Sara', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1565C0), height: 1.2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Primary action — Find Patient (biggest touch target)
                _PrimaryAction(
                  icon: Icons.search,
                  label: 'Find Patient',
                  subtitle: 'Search by name, MRN, or Medicare number',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientListScreen())),
                ),
                const SizedBox(height: 16),

                // Quick actions grid — 2x2
                Row(children: [
                  Expanded(child: _ActionCard(Icons.edit_note, 'My Drafts', kWarning, () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const DraftsScreen())))),
                  const SizedBox(width: 10),
                  Expanded(child: _ActionCard(Icons.task_alt, 'My Tasks', kInfo, () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTasksScreen())))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _ActionCard(Icons.message_outlined, 'Messages', kSuccess, () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const InboxScreen())))),
                  const SizedBox(width: 10),
                  Expanded(child: _ActionCard(Icons.assignment_turned_in_outlined, 'Log Contact', const Color(0xFF6A1B9A), () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientListScreen())))),
                ]),
                const SizedBox(height: 24),

                // Info card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0852C).withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF0852C).withAlpha(30)),
                  ),
                  child: Row(children: [
                    SvgPicture.asset('assets/signacare-logo.svg', width: 28, height: 28, colorFilter: const ColorFilter.mode(Color(0xFF1565C0), BlendMode.srcIn)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Sara by Signacare', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1565C0))),
                        Text('Clinician mobile companion — key patient info on the go',
                          style: TextStyle(fontSize: 11, color: kTextLight)),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

class _PrimaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _PrimaryAction({required this.icon, required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPrimary.withAlpha(60)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: kPrimary.withAlpha(25), shape: BoxShape.circle),
            child: Icon(icon, color: kPrimary, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 12, color: kTextLight)),
          ])),
          const Icon(Icons.arrow_forward_ios, size: 16, color: kTextLight),
        ]),
      ),
    ),
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kDivider),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withAlpha(25), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    ),
  );
}

// ── Profile ────────────────────────────────────────────────────────────────────

class _ProfilePage extends ConsumerWidget {
  const _ProfilePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(children: [
              CircleAvatar(
                radius: 36, backgroundColor: const Color(0xFFF0852C),
                child: Text(
                  (user?.givenName?.substring(0, 1) ?? '?') + (user?.familyName?.substring(0, 1) ?? ''),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              Text(user?.displayName ?? 'Clinician', style: SignacareText.title),
              const SizedBox(height: 4),
              Text(user?.email ?? '', style: SignacareText.caption),
              if (user?.role != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Chip(
                    label: Text(user!.role!, style: const TextStyle(fontSize: 11, color: Color(0xFF1565C0), fontWeight: FontWeight.w600)),
                    backgroundColor: const Color(0xFFF0852C).withAlpha(20),
                    padding: EdgeInsets.zero,
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 28),
          _SettingsTile(Icons.settings_ethernet, 'Server URL', 'Configure API endpoint', onTap: () => _showUrlDialog(context, ref)),
          _SettingsTile(Icons.info_outline, 'App Version', 'Sara 1.0.0 by Signacare', onTap: () {}),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: ElevatedButton.styleFrom(backgroundColor: kError),
          ),
        ],
      ),
    );
  }

  void _showUrlDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    api.getBaseUrl().then((url) => ctrl.text = url);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'http://192.168.1.x:4000/api/v1')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async { await api.setBaseUrl(ctrl.text.trim()); if (context.mounted) Navigator.pop(context); },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SettingsTile(this.icon, this.title, this.subtitle, {required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: const Color(0xFFF0852C).withAlpha(25), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: const Color(0xFFF0852C), size: 20),
    ),
    title: Text(title, style: SignacareText.body),
    subtitle: Text(subtitle, style: SignacareText.caption),
    trailing: const Icon(Icons.chevron_right, color: kTextLight),
    onTap: onTap,
  );
}
