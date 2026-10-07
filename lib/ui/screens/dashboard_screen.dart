import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/lead_entry.dart';
import '../../data/models.dart';
import '../../services/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/task_tile.dart';
import 'company_screen.dart';
import 'entry_screen.dart';
import 'renewals_screen.dart';

class DashData {
  DashData({
    required this.overdue,
    required this.today,
    required this.hot,
    required this.hotCount,
    required this.renewals,
    required this.recent,
    required this.drafts,
    required this.companyCount,
    required this.lastBackup,
  });
  final List<TaskWithCompany> overdue, today;
  final List<Company> hot, recent;
  final int hotCount, companyCount;
  final DateTime? lastBackup;
  final List<ProductWithCompany> renewals;
  final List<({String key, String label, DateTime at})> drafts;
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.goToTab});

  /// 0 Home, 1 Leads, 2 Follow-ups, 3 Settings
  final void Function(int index) goToTab;

  static DashData load(AppController a) {
    final pending = a.repo.tasks(pending: true);
    List<TaskWithCompany> of(FollowUpBucket b) =>
        pending.where((t) => followUpBucket(t.task.dueDate, a.today) == b).toList();
    final from = Dates.toIso(a.today);
    final to = Dates.toIso(Dates.addDays(a.today, 90));

    final drafts = <({String key, String label, DateTime at})>[];
    for (final d in a.repo.listDrafts()) {
      final raw = a.repo.loadDraft(d.key);
      final e = raw == null ? null : LeadEntry.tryDecode(raw);
      if (e == null || !e.hasContent) continue;
      final name = e.companyName.trim().isEmpty ? 'a new lead' : e.companyName.trim();
      drafts.add((
        key: d.key,
        label: d.key == 'new' ? 'Unfinished lead: $name' : 'Unfinished meeting: $name',
        at: d.updatedAt,
      ));
    }
    return DashData(
      overdue: of(FollowUpBucket.overdue),
      today: of(FollowUpBucket.today),
      hot: a.repo.hotLeads(5),
      hotCount: a.repo.countHot(),
      renewals: a.repo.renewals(from: from, to: to),
      recent: a.repo.recentCompanies(5),
      drafts: drafts,
      companyCount: a.repo.companyCount,
      lastBackup: DateTime.tryParse(a.repo.getSetting('last_backup') ?? ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(kAppName)),
      body: Live<DashData>(
        cacheKey: Dates.toIso(app.today),
        load: load,
        builder: (context, d) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: FilledButton.icon(
                  onPressed: () => startEntry(context),
                  icon: const Icon(Icons.add_circle_outline, size: 26),
                  label: const Text('Add Lead / Meeting',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                ),
              ),
              if (d.companyCount > 0 &&
                  (d.lastBackup == null || app.now.difference(d.lastBackup!).inDays >= 30))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Card(
                    color: const Color(0xFFFFF6E0),
                    child: ListTile(
                      leading: const Icon(Icons.backup_outlined, color: Color(0xFF8A3B00)),
                      title: const Text('Back up your data'),
                      subtitle: Text(d.lastBackup == null
                          ? 'You have not made a backup yet. If this phone is lost, your records are gone.'
                          : 'Last backup: ${Dates.displayDate(d.lastBackup!)}. Time for a fresh one.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => goToTab(3),
                    ),
                  ),
                ),
              for (final dr in d.drafts)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Card(
                    color: const Color(0xFFFFF6E0),
                    child: ListTile(
                      leading: const Icon(Icons.edit_note, color: Color(0xFF8A3B00)),
                      title: Text(dr.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Saved ${Dates.displayDateTime(dr.at)}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Discard draft',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await confirm(context,
                                title: 'Discard this draft?',
                                message: 'The unfinished entry will be deleted.',
                                confirmLabel: 'Discard',
                                destructive: true);
                            if (ok) app.run(() => app.repo.deleteDraft(dr.key), resync: false);
                          },
                        ),
                        const Icon(Icons.chevron_right),
                      ]),
                      onTap: () => startEntry(context,
                          companyId: dr.key == 'new' ? null : dr.key.substring(3), resume: true),
                    ),
                  ),
                ),
              if (d.companyCount == 0) ...[
                const SizedBox(height: 24),
                const EmptyState(
                  icon: Icons.rocket_launch_outlined,
                  title: 'Ready for your first meeting',
                  message:
                      'After a client meeting, tap Add Lead / Meeting and type what you remember. Only the company name is required, and everything else can wait.',
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(children: [
                    _Stat('Overdue', d.overdue.length, const Color(0xFFB71C1C), () => goToTab(2)),
                    const SizedBox(width: 8),
                    _Stat('Due today', d.today.length, const Color(0xFF8A3B00), () => goToTab(2)),
                    const SizedBox(width: 8),
                    _Stat('Hot leads', d.hotCount, kBlueDark, () => goToTab(1)),
                  ]),
                ),
                if (d.overdue.isNotEmpty) ...[
                  SectionHeader('Overdue follow-ups',
                      trailing: TextButton(onPressed: () => goToTab(2), child: const Text('See all'))),
                  _taskList(d.overdue.take(5)),
                ],
                SectionHeader('Follow-ups due today'),
                if (d.today.isEmpty)
                  const _Muted('Nothing due today.')
                else
                  _taskList(d.today.take(8)),
                SectionHeader('Hot leads'),
                if (d.hot.isEmpty)
                  const _Muted('No hot leads yet. Mark a lead as Hot to see it here.')
                else
                  for (final c in d.hot) _CompanyLine(c),
                SectionHeader('Upcoming renewals (next 90 days)',
                    trailing: TextButton(
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const RenewalsScreen())),
                        child: const Text('See all'))),
                if (d.renewals.isEmpty)
                  const _Muted('No policies expire in the next 90 days.')
                else
                  for (final r in d.renewals.take(6)) RenewalLine(item: r, today: app.today),
                SectionHeader('Recently updated'),
                for (final c in d.recent) _CompanyLine(c),
              ],
              const SizedBox(height: 28),
              const Signature(),
            ],
          );
        },
      ),
    );
  }

  Widget _taskList(Iterable<TaskWithCompany> items) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(children: [
          for (final t in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TaskTile(key: ValueKey(t.task.id), task: t.task, companyName: t.companyName),
            ),
        ]),
      );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(text, style: const TextStyle(color: kMuted, fontSize: 15)),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color, this.onTap);
  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: '$label: $value',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueGrey.shade100),
            ),
            child: Column(children: [
              Text('$value', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: kMuted, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CompanyLine extends StatelessWidget {
  const _CompanyLine(this.c);
  final Company c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Card(
        child: ListTile(
          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Updated ${Dates.displayDateTime(c.updatedAt)}'),
          trailing: QualityBadge(c.quality, showUnrated: true),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => CompanyScreen(companyId: c.id))),
        ),
      ),
    );
  }
}

class RenewalLine extends StatelessWidget {
  const RenewalLine({super.key, required this.item, required this.today});
  final ProductWithCompany item;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final p = item.product;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Card(
        child: ListTile(
          title: Text(item.companyName, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${p.displayName} · ${Dates.display(p.expiryDate)}'),
          trailing: ExpiryBadge(p.expiryDate, today),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => CompanyScreen(companyId: p.companyId))),
        ),
      ),
    );
  }
}
