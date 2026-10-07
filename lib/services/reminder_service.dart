import '../core/dates.dart';
import '../data/repository.dart';

/// The small slice of the platform notification API the app needs. The real
/// implementation lives in `local_notifications_gateway.dart`; tests use a
/// fake, so scheduling rules are testable without a phone.
abstract class NotificationGateway {
  Future<void> initialize();
  Future<bool> hasPermission();

  /// Shows the system permission prompt (where the OS has one).
  Future<bool> requestPermission();
  Future<void> cancelAll();
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  });

  /// Re-reads the phone's current time zone (call after a zone change).
  Future<void> refreshTimeZone();
}

class PlannedReminder {
  const PlannedReminder(this.id, this.at, this.body);
  final int id;
  final DateTime at;
  final String body;
}

/// Decides *which* reminders to hand to the operating system.
class ReminderPlanner {
  ReminderPlanner._();

  /// iOS keeps at most 64 pending local notifications (the soonest are kept),
  /// and Android limits alarms per app, so only the soonest [limit] future
  /// reminders are scheduled. The rest are scheduled automatically the next
  /// time the app is opened (see ReminderService.sync).
  static const int defaultLimit = 50;

  static const String discreetBody = 'You have a follow-up due.';
  static const String title = 'BCR LeadBook';

  static List<PlannedReminder> plan(
    List<PendingReminder> pending,
    DateTime now, {
    bool showCompany = false,
    int limit = defaultLimit,
  }) {
    final out = <PlannedReminder>[];
    for (final r in pending) {
      final d = Dates.parseIso(r.dueDate);
      final t = Dates.parseTime(r.time);
      if (d == null || t == null) continue;
      // Wall-clock time in the phone's *current* zone.
      final at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      if (!at.isAfter(now)) continue; // past reminders show inside the app
      out.add(PlannedReminder(
        r.seq,
        at,
        showCompany ? 'Follow-up due: ${r.companyName}' : discreetBody,
      ));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out.length > limit ? out.sublist(0, limit) : out;
  }
}

enum ReminderPermission { granted, denied }

class ReminderService {
  ReminderService(this.repo, this.gateway);

  final Repository repo;
  final NotificationGateway gateway;

  Future<void> _chain = Future.value();

  /// Result of the last [sync]: how many reminders the OS now holds.
  int lastScheduledCount = 0;

  bool get showCompany => repo.getSetting('notif_show_company') == '1';

  /// Ask for notification permission. Called the first time the user saves a
  /// follow-up with a reminder, not at app start.
  Future<ReminderPermission> ensurePermission() async {
    try {
      if (await gateway.hasPermission()) return ReminderPermission.granted;
      final ok = await gateway.requestPermission();
      repo.setSetting('notif_asked', '1');
      return ok ? ReminderPermission.granted : ReminderPermission.denied;
    } catch (_) {
      return ReminderPermission.denied;
    }
  }

  /// Rebuilds the OS schedule from the database. Safe to call at any time;
  /// calls are queued so they never interleave. Never throws: if
  /// notifications are unavailable the app simply keeps showing due tasks
  /// in-app.
  Future<void> sync() {
    final next = _chain.then((_) => _doSync());
    _chain = next.catchError((_) {});
    return next;
  }

  Future<void> _doSync() async {
    try {
      await gateway.cancelAll();
      lastScheduledCount = 0;
      if (!await gateway.hasPermission()) return;
      final plan = ReminderPlanner.plan(
        repo.pendingReminders(),
        repo.now,
        showCompany: showCompany,
      );
      for (final p in plan) {
        await gateway.schedule(
          id: p.id,
          at: p.at,
          title: ReminderPlanner.title,
          body: p.body,
        );
        lastScheduledCount++;
      }
    } catch (_) {
      // Swallow: reminders are best-effort, data is never affected.
    }
  }
}
