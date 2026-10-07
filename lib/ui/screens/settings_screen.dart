import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../data/backup_service.dart';
import '../../data/csv_export.dart';
import '../../data/demo_data.dart';
import '../../services/app_controller.dart';
import '../../services/file_service.dart';
import '../../services/reminder_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'about_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _guard(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) showInfo(context, 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Anchor for the iPad share popover.
  Rect _origin() {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 2, height: 2);
  }

  Future<void> _createBackup() => _guard(() async {
        final app = AppScope.read(context);
        final json = app.backup.createBackup();
        final name = 'bcr-leadbook-backup-${DateFormat('yyyyMMdd-HHmm').format(app.now)}.json';
        await FileService.shareTextFiles({name: json}, subject: 'BCR LeadBook backup', origin: _origin());
        app.repo.setSetting('last_backup', app.now.toIso8601String());
        app.changed(resync: false);
        if (mounted) {
          showInfo(context,
              'Choose where to keep the backup file (Files, Drive, email…). Keep it somewhere safe.');
        }
      });

  Future<void> _restore() => _guard(() async {
        final app = AppScope.read(context);
        final picked = await FileService.pickTextFile();
        if (picked == null || !mounted) return;
        BackupData data;
        try {
          data = app.backup.parse(picked.text);
        } on BackupException catch (e) {
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Cannot restore this file'),
              content: Text('${e.message}\n\nYour current data has not been changed.'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
            ),
          );
          return;
        } on FormatException {
          if (!mounted) return;
          showInfo(context, 'That file could not be read as a backup. Your data has not been changed.');
          return;
        }
        if (!mounted) return;
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Replace ALL current data?'),
            content: Text(
                'Backup file: ${picked.name}\n${data.createdAt == null ? '' : 'Made: ${Dates.displayDateTime(data.createdAt!)}\n'}Contains: ${data.summary}.\n\n'
                'This phone currently holds ${app.repo.companyCount} companies. They will be permanently replaced by the backup.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, 'backup'), child: const Text('Back up current data first')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
                onPressed: () => Navigator.pop(ctx, 'replace'),
                child: const Text('Replace with backup'),
              ),
            ],
          ),
        );
        if (choice == 'backup') {
          await _createBackup();
          if (mounted) showInfo(context, 'Now choose Restore again to continue.');
          return;
        }
        if (choice != 'replace' || !mounted) return;
        app.run(() => app.backup.restore(data));
        if (mounted) showSaved(context, 'Restored: ${data.summary}');
      });

  Future<void> _exportCsv() => _guard(() async {
        final app = AppScope.read(context);
        var includeRapport = false;
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
              title: const Text('Export to CSV'),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                    'Creates six spreadsheet files (leads overview, renewals worklist, contacts, products, meetings, follow-ups) that open in Excel or Google Sheets.'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeRapport,
                  onChanged: (v) => setS(() => includeRapport = v ?? false),
                  title: const Text('Include personal & rapport notes'),
                  subtitle: const Text('Leave unticked to keep private notes out of the file.'),
                ),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Export')),
              ],
            ),
          ),
        );
        if (go != true) return;
        final files = app.csv.build(includeRapport: includeRapport);
        await FileService.shareTextFiles({...files, 'README.txt': csvReadme}, subject: 'BCR LeadBook export', origin: _origin());
      });

  Future<void> _pickDefaultTime() async {
    final app = AppScope.read(context);
    final t = await pickTime(context, app.defaultReminderTime);
    if (t != null) app.setDefaultReminderTime(Dates.timeToString(t.hour, t.minute));
  }

  Future<void> _testPermission() async {
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final r = await app.reminders.ensurePermission();
    await app.reminders.sync();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(r == ReminderPermission.granted
            ? 'Notifications are on. ${app.reminders.lastScheduledCount} reminder(s) scheduled.'
            : 'Notifications are off. Turn them on for BCR LeadBook in your phone\'s Settings. Meanwhile, due follow-ups still show inside the app.'),
        duration: const Duration(seconds: 6),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final demo = DemoData.count(app.repo);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const SectionHeader('Reminders'),
              SwitchListTile(
                title: const Text('Remind me by default'),
                subtitle: const Text('New follow-ups start with a reminder switched on'),
                value: app.defaultReminderOn,
                onChanged: app.setDefaultReminderOn,
              ),
              ListTile(
                title: const Text('Default reminder time'),
                subtitle: const Text('Used when you set a follow-up date'),
                trailing: Text(Dates.displayTime(app.defaultReminderTime),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kBlueDark)),
                onTap: _pickDefaultTime,
              ),
              SwitchListTile(
                title: const Text('Show company name in notifications'),
                subtitle: const Text(
                    'Off by default: notifications just say "You have a follow-up due." so nothing private appears on your lock screen.'),
                value: app.showCompanyInNotification,
                onChanged: app.setShowCompanyInNotification,
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Check notification permission'),
                subtitle: const Text('Asks your phone for permission if needed'),
                onTap: _testPermission,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  'About reminders: they are scheduled on your phone and need no internet. Phones allow only a limited number of pending notifications, so the next 50 are scheduled and the rest are added automatically each time you open the app. Android may deliver a reminder a few minutes late to save battery. If you change time zone, open the app once so reminders move to the new local time. If notifications are off, due follow-ups still appear in the Follow-ups tab.',
                  style: TextStyle(fontSize: 13.5, color: kMuted, height: 1.4),
                ),
              ),
              const SectionHeader('Backup & restore'),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE9C46A)),
                ),
                child: const Text(
                  'Your records live only on this phone. If the app is uninstalled or the phone is lost, broken or reset, they are gone. Create a backup regularly (for example weekly) and keep the file somewhere safe, such as Google Drive, iCloud or email to yourself.',
                  style: TextStyle(height: 1.4),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Create backup'),
                subtitle: Text(
                    'All companies, contacts, products, meetings and follow-ups\nLast backup: ${lastBackupText(app)}'),
                onTap: _busy ? null : _createBackup,
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore from backup file'),
                subtitle: const Text('Replaces everything on this phone, after you confirm'),
                onTap: _busy ? null : _restore,
              ),
              const SectionHeader('Export'),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Export to CSV (Excel / Sheets)'),
                subtitle: const Text('You choose whether private rapport notes are included'),
                onTap: _busy ? null : _exportCsv,
              ),
              const SectionHeader('Privacy'),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'BCR LeadBook works fully offline. No account, no cloud, no analytics and no AI service: your records are never sent anywhere. The app does not write contact details or notes to any log.',
                  style: TextStyle(height: 1.4),
                ),
              ),
              const SectionHeader('Sample data'),
              ListTile(
                leading: const Icon(Icons.science_outlined),
                title: Text(demo == 0 ? 'Load demo data' : 'Remove demo data ($demo demo companies)'),
                subtitle: Text(demo == 0
                    ? 'Optional: adds a few fictional companies so you can explore the app'
                    : 'Deletes only the demo companies; your own records stay'),
                onTap: () async {
                  if (demo == 0) {
                    final ok = await confirm(context,
                        title: 'Load demo data?',
                        message:
                            'This adds 5 fictional companies to this phone. You can remove them again here at any time.',
                        confirmLabel: 'Load demo data');
                    if (ok) {
                      app.run(() => DemoData.load(app.repo));
                      if (context.mounted) showSaved(context, 'Demo data added');
                    }
                  } else {
                    final ok = await confirm(context,
                        title: 'Remove demo data?',
                        message: 'Only the demo companies and their records are deleted.',
                        confirmLabel: 'Remove',
                        destructive: true);
                    if (ok) {
                      app.run(() => DemoData.remove(app.repo));
                      if (context.mounted) showInfo(context, 'Demo data removed');
                    }
                  }
                },
              ),
              const SectionHeader('About'),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About $kAppName'),
                subtitle: const Text('Version $kAppVersion'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const AboutScreen())),
              ),
              const SizedBox(height: 24),
              const Signature(),
            ],
          ),
          if (_busy) const Positioned.fill(child: ColoredBox(color: Color(0x33FFFFFF), child: Center(child: CircularProgressIndicator()))),
        ],
      ),
    );
  }
}


/// "Never" or a readable date of the last backup this phone created.
String lastBackupText(AppController app) {
  final raw = app.repo.getSetting('last_backup');
  final d = raw == null ? null : DateTime.tryParse(raw);
  return d == null ? 'never' : Dates.displayDateTime(d);
}
