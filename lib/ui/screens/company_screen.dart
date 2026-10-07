import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../services/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/editors.dart';
import '../widgets/task_tile.dart';
import 'entry_screen.dart';

class CompanyScreen extends StatelessWidget {
  const CompanyScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context) {
    return Live<CompanyBundle?>(
      load: (app) => app.repo.bundle(companyId),
      builder: (context, b) {
        if (b == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Company')),
            body: const EmptyState(
                icon: Icons.search_off, title: 'This company is no longer saved'),
          );
        }
        return _CompanyView(bundle: b);
      },
    );
  }
}

class _CompanyView extends StatelessWidget {
  const _CompanyView({required this.bundle});
  final CompanyBundle bundle;

  Company get c => bundle.company;

  Future<void> _editCompany(BuildContext context) async {
    final app = AppScope.read(context);
    final updated = await showCompanySheet(context, c);
    if (updated == null) return;
    app.run(() => app.repo.updateCompany(updated));
    if (context.mounted) showSaved(context);
  }

  Future<void> _deleteCompany(BuildContext context) async {
    final app = AppScope.read(context);
    final nav = Navigator.of(context);
    final ok = await confirm(
      context,
      title: 'Delete ${c.name}?',
      message:
          'This permanently deletes the company and its ${bundle.contacts.length} contact(s), ${bundle.products.length} product(s), ${bundle.meetings.length} meeting note(s) and ${bundle.tasks.length} follow-up(s) from this phone. This cannot be undone unless you have a backup.',
      confirmLabel: 'Delete everything',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final snapshot = bundle;
    final messenger = ScaffoldMessenger.of(context);
    app.run(() => app.repo.deleteCompany(c.id));
    nav.pop();
    showUndo(messenger, '${c.name} deleted', () => app.run(() => app.repo.restoreBundle(snapshot)));
  }

  Future<void> _mergeCompany(BuildContext context) async {
    final app = AppScope.read(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final target = await showDialog<({String id, String name})>(
      context: context,
      builder: (_) => _MergeDialog(sourceId: c.id, sourceName: c.name),
    );
    if (target == null || !context.mounted) return;
    final ok = await confirm(
      context,
      title: 'Merge into ${target.name}?',
      message:
          'All contacts, products, meeting notes and follow-ups of ${c.name} move into ${target.name}, and ${c.name} is removed. This cannot be undone.',
      confirmLabel: 'Merge',
      destructive: true,
    );
    if (!ok) return;
    app.run(() => app.repo.mergeCompanies(c.id, target.id));
    nav.pop();
    showSavedOn(messenger, 'Merged into ${target.name}');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Company options',
              onSelected: (v) => switch (v) {
                'edit' => _editCompany(context),
                'merge' => _mergeCompany(context),
                _ => _deleteCompany(context),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit company details')),
                PopupMenuItem(value: 'merge', child: Text('Merge into another company…')),
                PopupMenuItem(value: 'delete', child: Text('Delete company…')),
              ],
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFFE3F2FD),
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            tabs: [
              Tab(text: 'Pre-call'),
              Tab(text: 'Notes'),
              Tab(text: 'People'),
              Tab(text: 'Policies'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => startEntry(context, companyId: c.id),
          icon: const Icon(Icons.add),
          label: const Text('Add Meeting'),
        ),
        body: TabBarView(
          children: [
            _PreCallTab(bundle: bundle),
            _NotesTab(bundle: bundle),
            _PeopleTab(bundle: bundle),
            _PoliciesTab(bundle: bundle),
          ],
        ),
      ),
    );
  }
}

Widget _pad(List<Widget> children) => ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: children,
    );

Widget _gap([double h = 12]) => SizedBox(height: h);

// ---------------------------------------------------------------------------

class _PreCallTab extends StatelessWidget {
  const _PreCallTab({required this.bundle});
  final CompanyBundle bundle;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = bundle.company;
    final next = bundle.nextCallContact;
    final last = bundle.lastMeeting;
    final rapport = next != null && next.notes.trim().isNotEmpty
        ? next.notes
        : c.rapportNotes;
    final expiring = bundle.productsByExpiry.where((p) => p.expiryDate != null).toList();

    return _pad([
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                QualityBadge(c.quality, showUnrated: true),
                if (c.targetMonth != null)
                  Pill('Target: ${Dates.monthLabel(c.targetMonth)}', fg: kBlueDark, bg: kBlueSoft, icon: Icons.flag),
                if (c.location.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.place, size: 16, color: kMuted),
                    const SizedBox(width: 2),
                    Flexible(child: Text(c.location, style: const TextStyle(color: kMuted))),
                  ]),
              ]),
              const SizedBox(height: 6),
              Text(
                'Created ${Dates.displayDateTime(c.createdAt)} · Updated ${Dates.displayDateTime(c.updatedAt)}',
                style: const TextStyle(fontSize: 12.5, color: kMuted),
              ),
            ],
          ),
        ),
      ),
      _gap(),
      _Block(
        icon: Icons.person_pin,
        title: 'Next call with',
        child: next == null
            ? const Text('No contact chosen yet. Add one on the People tab.',
                style: TextStyle(color: kMuted))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(next.name + (next.isDecisionMaker ? '  (decision-maker)' : ''),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if (next.title.isNotEmpty) Text(next.title, style: const TextStyle(color: kMuted)),
                if (next.phone.isNotEmpty) Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(next.phone, style: const TextStyle(fontSize: 15)),
                ),
                const SizedBox(height: 10),
                ContactActions(next),
              ]),
      ),
      if (bundle.contacts.where((x) => x.id != next?.id).isNotEmpty) ...[
        _gap(),
        _Block(
          icon: Icons.groups,
          title: 'Other people here',
          child: Column(children: [
            for (final o in bundle.contacts.where((x) => x.id != next?.id))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      '${o.name}${o.title.isEmpty ? '' : ' · ${o.title}'}${o.isDecisionMaker ? ' (decision-maker)' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                  if (o.phone.isNotEmpty) Text(o.phone),
                  const SizedBox(height: 6),
                  ContactActions(o),
                ]),
              ),
          ]),
        ),
      ],
      _gap(),
      _Block(
        icon: Icons.event_available,
        title: 'Next action',
        trailing: TextButton.icon(
          onPressed: () => showTaskSheet(context,
              companyId: c.id,
              contacts: bundle.contacts,
              products: bundle.products,
              presetContactId: next?.id),
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
        child: bundle.pendingTasks.isEmpty
            ? const Text('Nothing scheduled. Add a follow-up so this lead is not forgotten.',
                style: TextStyle(color: kMuted))
            : Column(children: [
                for (final t in bundle.pendingTasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: TaskTile(task: t, openCompanyOnTap: false),
                  ),
              ]),
      ),
      _gap(),
      _Block(
        icon: Icons.history,
        title: last == null ? 'Last meeting' : 'Last meeting · ${Dates.displayDateTime(last.meetingAt)}',
        child: last == null
            ? const Text('No meetings recorded yet. Tap Add Meeting.', style: TextStyle(color: kMuted))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (bundle.contactById(last.contactId) != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('Met: ${bundle.contactById(last.contactId)!.name}',
                        style: const TextStyle(color: kMuted)),
                  ),
                SelectableText(last.summary.isEmpty ? 'No summary written.' : last.summary,
                    style: const TextStyle(fontSize: 15.5, height: 1.4)),
              ]),
      ),
      _gap(),
      _Block(
        icon: Icons.coffee,
        title: next == null ? 'Rapport reminders' : 'Rapport reminders · ${next.name}',
        child: SelectableText(
          rapport.trim().isEmpty ? 'Nothing noted yet.' : rapport,
          style: TextStyle(fontSize: 15.5, height: 1.4, color: rapport.trim().isEmpty ? kMuted : kInk),
        ),
      ),
      _gap(),
      _Block(
        icon: Icons.business_center,
        title: 'Company context',
        child: SelectableText(
          c.trivia.trim().isEmpty ? 'Nothing noted yet.' : c.trivia,
          style: TextStyle(fontSize: 15.5, height: 1.4, color: c.trivia.trim().isEmpty ? kMuted : kInk),
        ),
      ),
      _gap(),
      _Block(
        icon: Icons.shield_outlined,
        title: 'Upcoming policy expiries',
        child: expiring.isEmpty
            ? Text(
                bundle.products.isEmpty
                    ? 'No insurance products recorded.'
                    : 'No expiry dates recorded yet.',
                style: const TextStyle(color: kMuted))
            : Column(children: [
                for (final p in expiring)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text('${p.displayName} · ${Dates.display(p.expiryDate)}',
                              style: const TextStyle(fontSize: 15.5)),
                        ),
                        const SizedBox(width: 8),
                        ExpiryBadge(p.expiryDate, app.today),
                      ]),
                      if ([p.insurer, p.notes.trim()].any((x) => x.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                              [if (p.insurer.isNotEmpty) 'Insurer: ${p.insurer}', if (p.notes.trim().isNotEmpty) p.notes.trim()]
                                  .join(' · '),
                              style: const TextStyle(fontSize: 14, color: kMuted)),
                        ),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.icon, required this.title, required this.child, this.trailing});
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: kBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kBlueDark)),
                ),
              ),
              ?trailing,
            ]),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _NotesTab extends StatelessWidget {
  const _NotesTab({required this.bundle});
  final CompanyBundle bundle;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final c = bundle.company;
    return _pad([
      _Block(
        icon: Icons.business_center,
        title: 'Company Trivia & Context',
        trailing: TextButton(
          onPressed: () async {
            final u = await showCompanySheet(context, c);
            if (u == null) return;
            app.run(() => app.repo.updateCompany(u));
            if (context.mounted) showSaved(context);
          },
          child: const Text('Edit'),
        ),
        child: SelectableText(c.trivia.trim().isEmpty ? 'Nothing noted yet.' : c.trivia,
            style: TextStyle(fontSize: 15.5, height: 1.4, color: c.trivia.trim().isEmpty ? kMuted : kInk)),
      ),
      const SectionHeader('Personal & Rapport Notes', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
      if (bundle.contacts.isEmpty && c.rapportNotes.trim().isEmpty)
        const Text('Add people on the People tab to keep rapport notes about each of them.',
            style: TextStyle(color: kMuted)),
      for (final p in bundle.contacts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _Block(
            icon: Icons.person,
            title: p.name,
            trailing: TextButton(
              onPressed: () async {
                final u = await showContactSheet(context, companyId: c.id, existing: p);
                if (u == null) return;
                app.run(() => app.repo.upsertContact(u));
                if (context.mounted) showSaved(context);
              },
              child: const Text('Edit'),
            ),
            child: SelectableText(p.notes.trim().isEmpty ? 'Nothing noted yet.' : p.notes,
                style: TextStyle(fontSize: 15.5, height: 1.4, color: p.notes.trim().isEmpty ? kMuted : kInk)),
          ),
        ),
      if (c.rapportNotes.trim().isNotEmpty)
        _Block(
          icon: Icons.groups,
          title: 'General (not linked to a person)',
          child: SelectableText(c.rapportNotes, style: const TextStyle(fontSize: 15.5, height: 1.4)),
        ),
      SectionHeader('Meeting history (${bundle.meetings.length})',
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8)),
      if (bundle.meetings.isEmpty)
        const Text('No meetings recorded yet.', style: TextStyle(color: kMuted)),
      for (final m in bundle.meetings)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _MeetingCard(bundle: bundle, meeting: m),
        ),
    ]);
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({required this.bundle, required this.meeting});
  final CompanyBundle bundle;
  final Meeting meeting;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final met = bundle.contactById(meeting.contactId);
    final next = bundle.contactById(meeting.nextContactId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(Dates.displayDateTime(meeting.meetingAt),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () async {
                  final u = await showMeetingSheet(
                    context,
                    meeting: meeting,
                    contacts: bundle.contacts,
                    onDelete: () async {
                      final ok = await confirm(context,
                          title: 'Delete this meeting?',
                          message: 'The notes from ${Dates.displayDateTime(meeting.meetingAt)} will be deleted.',
                          confirmLabel: 'Delete',
                          destructive: true);
                      if (ok && context.mounted) {
                        final messenger = ScaffoldMessenger.of(context);
                        app.run(() => app.repo.deleteMeeting(meeting.id));
                        showUndo(messenger, 'Meeting deleted',
                            () => app.run(() => app.repo.upsertMeeting(meeting)));
                      }
                      return ok;
                    },
                  );
                  if (u == null) return;
                  app.run(() => app.repo.upsertMeeting(u));
                  if (context.mounted) showSaved(context);
                },
                child: const Text('Edit'),
              ),
            ]),
            if (met != null) Text('Met: ${met.name}', style: const TextStyle(color: kMuted)),
            if (next != null && next.id != met?.id)
              Text('Next call with: ${next.name}', style: const TextStyle(color: kMuted)),
            const SizedBox(height: 8),
            SelectableText(meeting.summary.isEmpty ? 'No summary written.' : meeting.summary,
                style: TextStyle(
                    fontSize: 15.5, height: 1.4, color: meeting.summary.isEmpty ? kMuted : kInk)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PeopleTab extends StatelessWidget {
  const _PeopleTab({required this.bundle});
  final CompanyBundle bundle;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final c = bundle.company;
    return _pad([
      FilledButton.icon(
        onPressed: () async {
          final n = await showContactSheet(context, companyId: c.id);
          if (n == null) return;
          app.run(() => app.repo.upsertContact(n));
          if (context.mounted) showSaved(context);
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Add contact'),
      ),
      _gap(),
      if (bundle.contacts.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('No contacts yet. Add the people you deal with at this company.',
              textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
        ),
      for (final p in bundle.contacts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                    if (p.isDecisionMaker)
                      const Pill('Decision-maker', fg: kBlueDark, bg: kBlueSoft, icon: Icons.verified),
                    IconButton(
                      tooltip: 'Edit ${p.name}',
                      onPressed: () async {
                        final u = await showContactSheet(
                          context,
                          companyId: c.id,
                          existing: p,
                          onDelete: () async {
                            final ok = await confirm(context,
                                title: 'Delete ${p.name}?',
                                message:
                                    'Their meeting history stays, but it will no longer show who was met.',
                                confirmLabel: 'Delete',
                                destructive: true);
                            if (ok && context.mounted) {
                              final messenger = ScaffoldMessenger.of(context);
                              final meetings = bundle.meetings
                                  .where((m) => m.contactId == p.id || m.nextContactId == p.id)
                                  .toList();
                              final tasks = bundle.tasks.where((t) => t.contactId == p.id).toList();
                              app.run(() => app.repo.deleteContact(p.id));
                              showUndo(messenger, '${p.name} deleted', () {
                                app.run(() {
                                  app.repo.upsertContact(p);
                                  for (final m in meetings) {
                                    app.repo.saveMeeting(m);
                                  }
                                  for (final t in tasks) {
                                    app.repo.saveTask(t);
                                  }
                                });
                              });
                            }
                            return ok;
                          },
                        );
                        if (u == null) return;
                        app.run(() => app.repo.upsertContact(u));
                        if (context.mounted) showSaved(context);
                      },
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ]),
                  if (p.title.isNotEmpty) Text(p.title, style: const TextStyle(color: kMuted)),
                  if (p.phone.isNotEmpty) Text(p.phone),
                  if (p.email.isNotEmpty) Text(p.email),
                  const SizedBox(height: 10),
                  ContactActions(p),
                ],
              ),
            ),
          ),
        ),
    ]);
  }
}

class _PoliciesTab extends StatelessWidget {
  const _PoliciesTab({required this.bundle});
  final CompanyBundle bundle;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = bundle.company;
    Future<void> edit(Product? p) async {
      final u = await showProductSheet(
        context,
        companyId: c.id,
        existing: p,
        onDelete: p == null
            ? null
            : () async {
                final ok = await confirm(context,
                    title: 'Delete ${p.displayName}?',
                    message: 'This policy entry will be removed from ${c.name}.',
                    confirmLabel: 'Delete',
                    destructive: true);
                if (ok && context.mounted) {
                  final messenger = ScaffoldMessenger.of(context);
                  final tasks = bundle.tasks.where((t) => t.productId == p.id).toList();
                  app.run(() => app.repo.deleteProduct(p.id));
                  showUndo(messenger, '${p.displayName} deleted', () {
                    app.run(() {
                      app.repo.upsertProduct(p);
                      for (final t in tasks) {
                        app.repo.saveTask(t);
                      }
                    });
                  });
                }
                return ok;
              },
      );
      if (u == null) return;
      app.run(() => app.repo.upsertProduct(u));
      if (context.mounted) showSaved(context);
    }

    return _pad([
      FilledButton.icon(
        onPressed: () => edit(null),
        icon: const Icon(Icons.add),
        label: Text(bundle.products.isEmpty ? 'Add Product' : 'Add Another Product'),
      ),
      _gap(),
      if (bundle.products.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('No insurance products yet. Add medical, motor, property and more, each with its own expiry date.',
              textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
        ),
      for (final p in bundle.productsByExpiry)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => edit(p),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(p.displayName,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                      ExpiryBadge(p.expiryDate, app.today),
                    ]),
                    const SizedBox(height: 4),
                    Text(p.expiryDate == null ? 'Expiry date: unknown' : 'Expires ${Dates.display(p.expiryDate)}'),
                    if (p.insurer.isNotEmpty) Text('Insurer: ${p.insurer}', style: const TextStyle(color: kMuted)),
                    if (p.notes.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(p.notes, style: const TextStyle(height: 1.35)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}


/// Pick the company to merge into (searchable).
class _MergeDialog extends StatefulWidget {
  const _MergeDialog({required this.sourceId, required this.sourceName});
  final String sourceId;
  final String sourceName;

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  String filter = '';

  @override
  Widget build(BuildContext context) {
    final all = AppScope.read(context)
        .repo
        .companyNames()
        .where((n) => n.id != widget.sourceId && n.name.toLowerCase().contains(filter.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text('Merge ${widget.sourceName} into…'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Search companies', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => filter = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: all.isEmpty
                ? const Center(child: Text('No other companies'))
                : ListView.builder(
                    itemCount: all.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(all[i].name),
                      onTap: () => Navigator.pop(context, all[i]),
                    ),
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
