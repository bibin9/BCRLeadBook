import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../../services/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/task_tile.dart';

class _Buckets {
  _Buckets(this.today, this.upcoming, this.overdue, this.completed);
  final List<TaskWithCompany> today, upcoming, overdue, completed;
}

class FollowUpsScreen extends StatelessWidget {
  const FollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Live<_Buckets>(
      cacheKey: Dates.toIso(app.today),
      load: (a) {
        final pending = a.repo.tasks(pending: true);
        List<TaskWithCompany> of(FollowUpBucket b) =>
            pending.where((t) => followUpBucket(t.task.dueDate, a.today) == b).toList();
        return _Buckets(
          of(FollowUpBucket.today),
          of(FollowUpBucket.upcoming),
          of(FollowUpBucket.overdue),
          a.repo.tasks(pending: false),
        );
      },
      builder: (context, b) {
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Follow-ups'),
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFFE3F2FD),
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                tabs: [
                  Tab(text: 'Today (${b.today.length})'),
                  Tab(text: 'Upcoming (${b.upcoming.length})'),
                  Tab(text: 'Overdue (${b.overdue.length})'),
                  Tab(text: 'Completed (${b.completed.length})'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _TaskList(
                  items: b.today,
                  icon: Icons.celebration_outlined,
                  empty: 'Nothing due today',
                  hint: 'Enjoy the quiet, or add a follow-up from any company.',
                ),
                _TaskList(
                  items: b.upcoming,
                  icon: Icons.event_outlined,
                  empty: 'No upcoming follow-ups',
                  hint: 'Follow-ups you schedule for future dates appear here.',
                ),
                _TaskList(
                  items: b.overdue,
                  icon: Icons.thumb_up_alt_outlined,
                  empty: 'Nothing overdue',
                  hint: 'You are all caught up.',
                ),
                _TaskList(
                  items: b.completed,
                  icon: Icons.check_circle_outline,
                  empty: 'No completed follow-ups yet',
                  hint: 'Tick the circle beside a follow-up when it is done.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.items, required this.icon, required this.empty, required this.hint});
  final List<TaskWithCompany> items;
  final IconData icon;
  final String empty;
  final String hint;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return EmptyState(icon: icon, title: empty, message: hint);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => TaskTile(
        key: ValueKey(items[i].task.id),
        task: items[i].task,
        companyName: items[i].companyName,
      ),
    );
  }
}
