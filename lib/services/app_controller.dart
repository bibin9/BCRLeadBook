import 'package:flutter/widgets.dart';

import '../core/dates.dart';
import '../data/backup_service.dart';
import '../data/csv_export.dart';
import '../data/repository.dart';
import 'reminder_service.dart';

/// Application logic shared by all screens. Screens read through [repo] and
/// perform every write through [run], which refreshes listeners and
/// re-synchronises local notifications.
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({
    required this.repo,
    required this.reminders,
  })  : backup = BackupService(repo),
        csv = CsvExport(repo);

  final Repository repo;
  final ReminderService reminders;
  final BackupService backup;
  final CsvExport csv;

  /// Bumped on every write so cached lists know to reload.
  int revision = 0;

  DateTime get now => repo.now;

  /// Today's date at local midnight.
  DateTime get today => Dates.dateOnly(now);

  void attach() => WidgetsBinding.instance.addObserver(this);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Day changed or time zone changed while the app was in the background:
  /// recompute "today" lists and rebuild the notification schedule.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      reminders.gateway.refreshTimeZone().then((_) => reminders.sync());
      revision++;
      notifyListeners();
    }
  }

  /// Perform a database write, then refresh the UI and notifications.
  T run<T>(T Function() write, {bool resync = true}) {
    final r = repo.transaction(write);
    changed(resync: resync);
    return r;
  }

  void changed({bool resync = true}) {
    revision++;
    notifyListeners();
    if (resync) reminders.sync();
  }

  // ---- settings ------------------------------------------------------------

  bool get welcomeSeen => repo.getSetting('welcome_seen') == '1';
  void markWelcomeSeen() {
    repo.setSetting('welcome_seen', '1');
    notifyListeners();
  }

  String get defaultReminderTime =>
      repo.getSetting('reminder_default_time') ?? '09:00';
  bool get defaultReminderOn => repo.getSetting('reminder_default_on') != '0';
  bool get showCompanyInNotification =>
      repo.getSetting('notif_show_company') == '1';

  void setDefaultReminderTime(String hhmm) {
    repo.setSetting('reminder_default_time', hhmm);
    notifyListeners();
  }

  void setDefaultReminderOn(bool on) {
    repo.setSetting('reminder_default_on', on ? '1' : '0');
    notifyListeners();
  }

  void setShowCompanyInNotification(bool on) {
    repo.setSetting('notif_show_company', on ? '1' : '0');
    notifyListeners();
    reminders.sync();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to changes.
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
