import 'package:bcr_leadbook/data/lead_entry.dart';
import 'package:bcr_leadbook/data/repository.dart';
import 'package:bcr_leadbook/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

PendingReminder rem(int seq, String date, String time, {String co = 'Acme'}) =>
    PendingReminder(seq: seq, taskId: 't$seq', dueDate: date, time: time, companyName: co);

void main() {
  group('ReminderPlanner', () {
    final now = DateTime(2026, 10, 3, 10, 0);

    test('only future reminders are planned, soonest first', () {
      final plan = ReminderPlanner.plan([
        rem(1, '2026-10-04', '09:00'),
        rem(2, '2026-10-03', '09:00'), // earlier today: in-app only
        rem(3, '2026-10-03', '10:00'), // exactly now: not in the future
        rem(4, '2026-10-03', '10:01'),
        rem(5, '2026-09-01', '09:00'), // long overdue
      ], now);
      expect(plan.map((p) => p.id), [4, 1]);
      expect(plan.first.at, DateTime(2026, 10, 3, 10, 1));
    });

    test('wall-clock time is used in the current zone (month/year boundary)', () {
      final plan = ReminderPlanner.plan([rem(1, '2027-01-01', '00:05')], DateTime(2026, 12, 31, 23, 0));
      expect(plan.single.at, DateTime(2027, 1, 1, 0, 5));
    });

    test('text is discreet by default; company name only if opted in', () {
      final r = [rem(1, '2026-10-05', '09:00', co: 'Secret Client LLC')];
      expect(ReminderPlanner.plan(r, now).single.body, 'You have a follow-up due.');
      expect(ReminderPlanner.plan(r, now).single.body.contains('Secret'), isFalse);
      expect(ReminderPlanner.plan(r, now, showCompany: true).single.body, 'Follow-up due: Secret Client LLC');
    });

    test('respects the OS limit: soonest N only', () {
      final many = [for (var i = 0; i < 200; i++) rem(i, '2026-11-01', '09:${(i % 50).toString().padLeft(2, '0')}')];
      final plan = ReminderPlanner.plan(many, now);
      expect(plan.length, ReminderPlanner.defaultLimit);
      expect(ReminderPlanner.defaultLimit, lessThanOrEqualTo(64), reason: 'iOS keeps 64 pending');
      expect(plan.map((p) => p.at).toList(), [...plan.map((p) => p.at)]..sort());
    });

    test('malformed rows are skipped, not fatal', () {
      expect(ReminderPlanner.plan([rem(1, 'bad', '09:00'), rem(2, '2026-10-05', '99:99')], now), isEmpty);
    });
  });

  group('10. ReminderService (fake gateway)', () {
    late TestEnv env;
    late FakeGateway gw;
    late ReminderService svc;
    setUp(() {
      env = TestEnv();
      gw = FakeGateway();
      svc = ReminderService(env.repo, gw);
    });

    String addTask(String company, String due, {String? time = '09:00'}) {
      final r = env.repo.commitEntry(LeadEntry(
          companyName: company, taskAction: 'x', taskDue: due, reminderOn: time != null, reminderTime: time ?? '09:00'));
      return r.taskId!;
    }

    int seqOf(String taskId) => env.repo.db.select('SELECT seq FROM tasks WHERE id=?', [taskId]).first['seq'] as int;

    test('creating a task schedules a reminder at its date + time', () async {
      final id = addTask('A', '2026-10-05');
      await svc.sync();
      expect(gw.scheduled.keys, [seqOf(id)]);
      expect(gw.scheduled.values.single.$1, DateTime(2026, 10, 5, 9, 0));
      expect(gw.scheduled.values.single.$2, 'BCR LeadBook');
      expect(gw.scheduled.values.single.$3, 'You have a follow-up due.');
    });

    test('a task without a reminder time schedules nothing', () async {
      addTask('A', '2026-10-05', time: null);
      await svc.sync();
      expect(gw.scheduled, isEmpty);
    });

    test('reschedule moves the notification; the old one is gone', () async {
      final id = addTask('A', '2026-10-05');
      await svc.sync();
      env.repo.rescheduleTask(id, DateTime(2026, 10, 9), reminderTime: '14:30');
      await svc.sync();
      expect(gw.scheduled.length, 1);
      expect(gw.scheduled.values.single.$1, DateTime(2026, 10, 9, 14, 30));
    });

    test('snooze until tomorrow moves it to the next day', () async {
      final id = addTask('A', '2026-10-03', time: '17:00');
      await svc.sync();
      expect(gw.scheduled.values.single.$1, DateTime(2026, 10, 3, 17, 0));
      env.repo.snoozeTaskUntilTomorrow(id, env.today);
      await svc.sync();
      expect(gw.scheduled.values.single.$1, DateTime(2026, 10, 4, 17, 0));
    });

    test('completing or deleting a task cancels its notification', () async {
      final a = addTask('A', '2026-10-05');
      final b = addTask('B', '2026-10-06');
      await svc.sync();
      expect(gw.scheduled.length, 2);
      env.repo.completeTask(a);
      await svc.sync();
      expect(gw.scheduled.keys, [seqOf(b)]);
      env.repo.deleteTask(b);
      await svc.sync();
      expect(gw.scheduled, isEmpty);
    });

    test('deleting a company cancels all of its notifications', () async {
      final r = env.repo.commitEntry(LeadEntry(companyName: 'Z', taskAction: 'x', taskDue: '2026-10-05'));
      await svc.sync();
      expect(gw.scheduled.length, 1);
      env.repo.deleteCompany(r.companyId);
      await svc.sync();
      expect(gw.scheduled, isEmpty);
    });

    test('permission is requested on demand and recorded', () async {
      gw.permitted = false;
      expect(await svc.ensurePermission(), ReminderPermission.granted);
      expect(gw.requests, 1);
      expect(env.repo.getSetting('notif_asked'), '1');
      expect(await svc.ensurePermission(), ReminderPermission.granted);
      expect(gw.requests, 1, reason: 'no second prompt once granted');
    });

    test('11. denied permission: nothing scheduled, app keeps working, due tasks still listed', () async {
      gw.permitted = false;
      gw.willGrant = false;
      expect(await svc.ensurePermission(), ReminderPermission.denied);
      addTask('Denied Co', '2026-10-03'); // due today
      await svc.sync();
      expect(gw.scheduled, isEmpty);
      // In-app due list is independent of notifications:
      final due = env.repo.tasks(pending: true);
      expect(due.single.companyName, 'Denied Co');
      // and saving more data works
      env.repo.commitEntry(LeadEntry(companyName: 'Still works'));
      expect(env.repo.companyCount, 2);
    });

    test('if the OS later grants permission, the next sync schedules everything', () async {
      gw.permitted = false;
      addTask('A', '2026-10-05');
      await svc.sync();
      expect(gw.scheduled, isEmpty);
      gw.permitted = true;
      await svc.sync();
      expect(gw.scheduled.length, 1);
    });

    test('platform errors never crash the app', () async {
      final bad = _ThrowingGateway();
      final s = ReminderService(env.repo, bad);
      addTask('A', '2026-10-05');
      await s.sync();
      expect(await s.ensurePermission(), ReminderPermission.denied);
    });

    test('time zone change: schedule is rebuilt from wall-clock time', () async {
      addTask('A', '2026-10-05');
      await svc.sync();
      final first = gw.scheduled.values.single.$1;
      // After a zone change the app re-reads the zone and re-syncs; the same
      // local 9:00 AM is requested again for the new zone.
      await gw.refreshTimeZone();
      await svc.sync();
      expect(gw.scheduled.values.single.$1, first);
      expect(gw.tzRefreshes, 1);
      expect(gw.cancelAllCalls, 2, reason: 'schedule is rebuilt, never duplicated');
    });

    test('restart / reboot: sync from the database restores every reminder', () async {
      addTask('A', '2026-10-05');
      addTask('B', '2026-10-07');
      await svc.sync();
      gw.scheduled.clear(); // OS lost them (e.g. update, restore, cleared)
      await svc.sync();
      expect(gw.scheduled.length, 2);
    });

    test('more reminders than the OS limit: only the soonest are held, rest return later', () async {
      for (var i = 0; i < 70; i++) {
        addTask('Co$i', '2026-11-${(i % 28 + 1).toString().padLeft(2, '0')}');
      }
      await svc.sync();
      expect(gw.scheduled.length, ReminderPlanner.defaultLimit);
      // once the earliest ones have fired, the next sync schedules the following ones
      env.clock = DateTime(2026, 11, 20);
      await svc.sync();
      expect(gw.scheduled.values.every((v) => v.$1.isAfter(DateTime(2026, 11, 20))), isTrue);
    });

    test('concurrent syncs are queued and never interleave', () async {
      addTask('A', '2026-10-05');
      await Future.wait([svc.sync(), svc.sync(), svc.sync()]);
      expect(gw.scheduled.length, 1);
    });

    test('opt-in to show the company name in the notification', () async {
      env.repo.setSetting('notif_show_company', '1');
      addTask('Named Co', '2026-10-05');
      await svc.sync();
      expect(gw.scheduled.values.single.$3, 'Follow-up due: Named Co');
    });
  });
}

class _ThrowingGateway extends FakeGateway {
  @override
  Future<bool> hasPermission() async => throw Exception('platform error');
  @override
  Future<void> cancelAll() async => throw Exception('platform error');
}
