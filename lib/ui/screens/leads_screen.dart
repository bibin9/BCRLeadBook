import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../services/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/editors.dart';
import 'company_screen.dart';
import 'entry_screen.dart';

String sortLabel(LeadSort s) => switch (s) {
      LeadSort.nextFollowUp => 'Next follow-up',
      LeadSort.latestUpdate => 'Latest update',
      LeadSort.companyName => 'Company name',
      LeadSort.nearestExpiry => 'Nearest policy expiry',
    };

String followUpFilterLabel(FollowUpFilter f) => switch (f) {
      FollowUpFilter.any => 'Any',
      FollowUpFilter.overdue => 'Overdue',
      FollowUpFilter.today => 'Due today',
      FollowUpFilter.upcoming => 'Upcoming',
      FollowUpFilter.none => 'None scheduled',
    };

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  LeadQuery q = const LeadQuery();
  final search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => q = q.copyWith(text: v));
    });
    setState(() {}); // update clear button
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<LeadQuery>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _FilterSheet(initial: q),
    );
    if (result != null) setState(() => q = result);
  }

  List<Widget> _activeChips() {
    final chips = <Widget>[];
    Widget chip(String label, VoidCallback onDelete) => InputChip(
          label: Text(label),
          onDeleted: onDelete,
          deleteButtonTooltipMessage: 'Remove filter $label',
        );
    for (final x in q.qualities) {
      chips.add(chip(x.label, () => setState(() => q = q.copyWith(qualities: {...q.qualities}..remove(x)))));
    }
    if (q.unrated) chips.add(chip('Not rated', () => setState(() => q = q.copyWith(unrated: false))));
    if (q.targetMonth != null) {
      chips.add(chip('Target ${Dates.monthLabel(q.targetMonth)}',
          () => setState(() => q = q.copyWith(clearTargetMonth: true))));
    }
    if (q.line != null) {
      chips.add(chip(q.line!.label, () => setState(() => q = q.copyWith(clearLine: true))));
    }
    if (q.followUp != FollowUpFilter.any) {
      chips.add(chip('Follow-up: ${followUpFilterLabel(q.followUp)}',
          () => setState(() => q = q.copyWith(followUp: FollowUpFilter.any))));
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final chips = _activeChips();
    return Scaffold(
      appBar: AppBar(title: const Text('Leads')),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Column(
              children: [
                TextField(
                  controller: search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search company, contact, phone or notes',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              search.clear();
                              setState(() => q = q.copyWith(text: ''));
                            },
                          ),
                  ),
                  onChanged: _onSearch,
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _openFilters,
                      icon: Badge(
                        isLabelVisible: q.hasFilters,
                        smallSize: 9,
                        child: const Icon(Icons.filter_list),
                      ),
                      label: const Text('Filters'),
                    ),
                    PopupMenuButton<LeadSort>(
                      tooltip: 'Sort leads',
                      initialValue: q.sort,
                      onSelected: (s) => setState(() => q = q.copyWith(sort: s)),
                      itemBuilder: (_) => [
                        for (final s in LeadSort.values)
                          PopupMenuItem(value: s, child: Text(sortLabel(s))),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.sort, color: kBlue),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('Sort: ${sortLabel(q.sort)}',
                                style: const TextStyle(color: kBlueDark, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
                if (chips.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 8, runSpacing: 0, children: chips),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: Live<List<LeadRow>>(
              cacheKey: '${q.cacheKey}|${Dates.toIso(app.today)}',
              load: (a) => a.repo.queryLeads(q, a.today),
              builder: (context, rows) {
                if (rows.isEmpty) {
                  final any = app.repo.companyCount > 0;
                  return EmptyState(
                    icon: any ? Icons.search_off : Icons.people_outline,
                    title: any ? 'No leads match' : 'No leads yet',
                    message: any
                        ? 'Try a different word, or clear the filters.'
                        : 'Tap "Add Lead / Meeting" after your next meeting. Only the company name is required.',
                    action: any
                        ? (q.hasFilters || q.text.isNotEmpty
                            ? OutlinedButton(
                                onPressed: () {
                                  search.clear();
                                  setState(() => q = const LeadQuery());
                                },
                                child: const Text('Clear search & filters'))
                            : null)
                        : FilledButton.icon(
                            onPressed: () => startEntry(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Lead / Meeting')),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: rows.length + 1,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text('${rows.length} ${rows.length == 1 ? 'lead' : 'leads'}',
                            style: const TextStyle(color: kMuted, fontSize: 13)),
                      );
                    }
                    return LeadRowTile(row: rows[i - 1], today: app.today);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact, spreadsheet-like row.
class LeadRowTile extends StatelessWidget {
  const LeadRowTile({super.key, required this.row, required this.today});
  final LeadRow row;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = row.company;
    final summary = row.productSummary;
    final expired = row.hasExpired(today);
    final nextExpiry = row.nearestExpiry(today);
    return InkWell(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => CompanyScreen(companyId: c.id))),
      child: Container(
        color: Colors.white,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: kInk)),
                  const SizedBox(height: 2),
                  Text(
                    summary.isEmpty
                        ? 'No products yet'
                        : '$summary${nextExpiry != null ? ' · renews ${Dates.display(nextExpiry)}' : ''}${expired ? ' · has expired policy' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: kMuted),
                  ),
                  if (row.nextAction != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Next: ${row.nextAction}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, color: kInk)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Capped so very large text wraps the badges instead of
            // squeezing the company name out.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.42),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  QualityBadge(c.quality, showUnrated: true),
                  const SizedBox(height: 6),
                  if (row.nextDue != null) DuePill(row.nextDue!, today),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});
  final LeadQuery initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late LeadQuery q = widget.initial;

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(
              child: Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => setState(() => q = q.copyWith(
                    qualities: {},
                    unrated: false,
                    clearTargetMonth: true,
                    clearLine: true,
                    followUp: FollowUpFilter.any,
                  )),
              child: const Text('Clear all'),
            ),
          ]),
          _title('Lead quality'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final x in LeadQuality.values)
              FilterChip(
                label: Text(x.label),
                selected: q.qualities.contains(x),
                onSelected: (v) => setState(() {
                  final s = {...q.qualities};
                  v ? s.add(x) : s.remove(x);
                  q = q.copyWith(qualities: s);
                }),
              ),
            FilterChip(
              label: const Text('Not rated'),
              selected: q.unrated,
              onSelected: (v) => setState(() => q = q.copyWith(unrated: v)),
            ),
          ]),
          _title('Target follow-up month'),
          TargetMonthTile(
            value: q.targetMonth,
            onChanged: (m) => setState(() => q = m == null ? q.copyWith(clearTargetMonth: true) : q.copyWith(targetMonth: m)),
          ),
          _title('Insurance line'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final l in ProductLine.values)
              ChoiceChip(
                label: Text(l.label),
                selected: q.line == l,
                onSelected: (v) => setState(() => q = v ? q.copyWith(line: l) : q.copyWith(clearLine: true)),
              ),
          ]),
          _title('Follow-up status'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final f in FollowUpFilter.values)
              ChoiceChip(
                label: Text(followUpFilterLabel(f)),
                selected: q.followUp == f,
                onSelected: (_) => setState(() => q = q.copyWith(followUp: f)),
              ),
          ]),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => Navigator.pop(context, q), child: const Text('Show results')),
        ],
      ),
    );
  }
}
