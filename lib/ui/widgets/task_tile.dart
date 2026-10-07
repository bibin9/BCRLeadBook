import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../../services/app_controller.dart';
import '../../services/launcher.dart';
import '../screens/company_screen.dart';
import '../theme.dart';
import 'common.dart';
import 'editors.dart';

Future<void> completeTaskWithUndo(BuildContext context, FollowUpTask t) async {
  final app = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  app.run(() => app.repo.completeTask(t.id));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: const Text('Marked completed'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => app.run(() => app.repo.reopenTask(t.id)),
      ),
    ));
}

Future<void> rescheduleTaskDialog(BuildContext context, FollowUpTask t) async {
  final app = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  String? chosen = t.dueDate;
  final ok = await showFormSheet<bool>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setS) => SheetFrame(
        title: 'Reschedule follow-up',
        saveLabel: 'Move it',
        onSave: () => Navigator.pop(ctx, true),
        children: [
          Text(t.action, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 14),
          DateQuickPicker(
            value: chosen,
            today: app.today,
            label: 'New date',
            onChanged: (v) => setS(() => chosen = v),
          ),
        ],
      ),
    ),
  );
  final d = Dates.parseIso(chosen);
  if (ok != true || d == null) return;
  app.run(() => app.repo.rescheduleTask(t.id, d));
  showSavedOn(messenger, 'Moved to ${Dates.display(Dates.toIso(d))}');
}

void snoozeTaskWeek(BuildContext context, FollowUpTask t) {
  final app = AppScope.read(context);
  app.run(() => app.repo.rescheduleTask(t.id, Dates.addDays(app.today, 7)));
  showSaved(context, 'Snoozed for one week');
}

void snoozeTaskTomorrow(BuildContext context, FollowUpTask t) {
  final app = AppScope.read(context);
  app.run(() => app.repo.snoozeTaskUntilTomorrow(t.id, app.today));
  showSaved(context, 'Snoozed until tomorrow');
}

Future<void> deleteTaskConfirm(BuildContext context, FollowUpTask t) async {
  final ok = await confirm(context,
      title: 'Delete this follow-up?',
      message: '"${t.action}" will be removed and its reminder cancelled.',
      confirmLabel: 'Delete',
      destructive: true);
  if (!ok || !context.mounted) return;
  final app = AppScope.read(context);
  app.run(() => app.repo.deleteTask(t.id));
  showInfo(context, 'Follow-up deleted');
}

Future<void> editTaskSheet(BuildContext context, FollowUpTask t) {
  final app = AppScope.read(context);
  return showTaskSheet(
    context,
    companyId: t.companyId,
    existing: t,
    contacts: app.repo.contactsFor(t.companyId),
    products: app.repo.productsFor(t.companyId),
  );
}

enum _TaskMenu { edit, reschedule, snooze, snoozeWeek, reopen, delete }

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, this.companyName, this.openCompanyOnTap = true});
  final FollowUpTask task;

  /// When set, shown under the action (cross-company lists).
  final String? companyName;
  final bool openCompanyOnTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final today = app.today;
    final done = !task.isPending;
    final time = task.reminderTime == null ? null : Dates.displayTime(task.reminderTime);
    final contact = task.contactId == null ? null : app.repo.getContact(task.contactId!);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: openCompanyOnTap
            ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CompanyScreen(companyId: task.companyId)))
            : () => editTaskSheet(context, task),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                tooltip: done ? 'Mark as pending again' : 'Mark completed',
                iconSize: 28,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => done
                    ? app.run(() => app.repo.reopenTask(task.id))
                    : completeTaskWithUndo(context, task),
                icon: Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: done ? kSuccess : kBlue,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.action,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done ? kMuted : kInk,
                        ),
                      ),
                      if (companyName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(companyName!, style: const TextStyle(color: kMuted, fontSize: 14)),
                        ),
                      if (contact != null)
                        Row(children: [
                          const Icon(Icons.person, size: 16, color: kMuted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(contact.name,
                                style: const TextStyle(fontSize: 14, color: kMuted),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (!done && contact.phone.trim().isNotEmpty) ...[
                            IconButton(
                              tooltip: 'Call ${contact.name}',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                              icon: const Icon(Icons.call, size: 20, color: kBlue),
                              onPressed: () => Launcher.call(context, contact.phone),
                            ),
                            IconButton(
                              tooltip: 'WhatsApp ${contact.name}',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                              icon: const Icon(Icons.chat, size: 20, color: kBlue),
                              onPressed: () => Launcher.whatsapp(context, contact.phone),
                            ),
                          ],
                        ]),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (done)
                            Pill(
                                task.completedAt == null
                                    ? 'Completed'
                                    : 'Completed ${Dates.displayDate(task.completedAt!)}',
                                fg: kSuccess,
                                bg: kSuccessBg,
                                icon: Icons.check)
                          else
                            DuePill(task.dueDate, today),
                          if (!done && time != null)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.alarm, size: 15, color: kMuted),
                              const SizedBox(width: 3),
                              Flexible(child: Text(time, style: const TextStyle(fontSize: 13, color: kMuted))),
                            ]),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<_TaskMenu>(
                tooltip: 'More actions',
                onSelected: (m) {
                  switch (m) {
                    case _TaskMenu.edit:
                      editTaskSheet(context, task);
                    case _TaskMenu.reschedule:
                      rescheduleTaskDialog(context, task);
                    case _TaskMenu.snooze:
                      snoozeTaskTomorrow(context, task);
                    case _TaskMenu.snoozeWeek:
                      snoozeTaskWeek(context, task);
                    case _TaskMenu.reopen:
                      app.run(() => app.repo.reopenTask(task.id));
                    case _TaskMenu.delete:
                      deleteTaskConfirm(context, task);
                  }
                },
                itemBuilder: (_) => [
                  if (!done) ...const [
                    PopupMenuItem(value: _TaskMenu.reschedule, child: Text('Reschedule…')),
                    PopupMenuItem(value: _TaskMenu.snooze, child: Text('Snooze until tomorrow')),
                    PopupMenuItem(value: _TaskMenu.snoozeWeek, child: Text('Snooze for a week')),
                    PopupMenuItem(value: _TaskMenu.edit, child: Text('Edit')),
                  ] else
                    const PopupMenuItem(value: _TaskMenu.reopen, child: Text('Mark as pending')),
                  const PopupMenuItem(value: _TaskMenu.delete, child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
