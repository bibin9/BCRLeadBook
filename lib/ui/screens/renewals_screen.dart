import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../../services/app_controller.dart';
import '../widgets/common.dart';
import 'dashboard_screen.dart';

enum _Range { next90, allUpcoming, expired }

/// Every policy with a known expiry date, one row per product, so two
/// policies of one company appear separately.
class RenewalsScreen extends StatefulWidget {
  const RenewalsScreen({super.key});

  @override
  State<RenewalsScreen> createState() => _RenewalsScreenState();
}

class _RenewalsScreenState extends State<RenewalsScreen> {
  _Range range = _Range.next90;
  ProductLine? line;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Renewals')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: const Text('Next 90 days'),
                  selected: range == _Range.next90,
                  onSelected: (_) => setState(() => range = _Range.next90)),
              ChoiceChip(
                  label: const Text('All upcoming'),
                  selected: range == _Range.allUpcoming,
                  onSelected: (_) => setState(() => range = _Range.allUpcoming)),
              ChoiceChip(
                  label: const Text('Expired'),
                  selected: range == _Range.expired,
                  onSelected: (_) => setState(() => range = _Range.expired)),
            ]),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: const Text('All lines'),
                      selected: line == null,
                      onSelected: (_) => setState(() => line = null)),
                ),
                for (final l in ProductLine.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                        label: Text(l.label),
                        selected: line == l,
                        onSelected: (_) => setState(() => line = l)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Live<List<ProductWithCompany>>(
              cacheKey: '${range.name}|${line?.db}|${Dates.toIso(app.today)}',
              load: (a) {
                final t = Dates.toIso(a.today);
                switch (range) {
                  case _Range.next90:
                    return a.repo.renewals(from: t, to: Dates.toIso(Dates.addDays(a.today, 90)), line: line);
                  case _Range.allUpcoming:
                    return a.repo.renewals(from: t, line: line);
                  case _Range.expired:
                    final y = Dates.toIso(Dates.addDays(a.today, -1));
                    return a.repo.renewals(to: y, line: line).reversed.toList();
                }
              },
              builder: (context, items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.shield_outlined,
                    title: 'No policies here',
                    message: 'Policies with a known expiry date appear in this list.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: items.length,
                  itemBuilder: (_, i) => RenewalLine(item: items[i], today: app.today),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
