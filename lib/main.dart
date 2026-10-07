import 'package:flutter/material.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'services/app_controller.dart';
import 'services/file_service.dart';
import 'services/local_notifications_gateway.dart';
import 'services/reminder_service.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Repository repo;
  try {
    repo = Repository(await openAppDatabase());
  } catch (e) {
    // Never fail silently: tell the user and do not touch their data.
    runApp(_StartupError(message: e is DatabaseTooNewException ? e.toString() : 'The local database could not be opened.'));
    return;
  }

  FileService.cleanupTempExports();
  final gateway = LocalNotificationsGateway();
  try {
    await gateway.initialize();
  } catch (_) {
    // Notifications unavailable: the app still works and shows due tasks.
  }
  final controller = AppController(repo: repo, reminders: ReminderService(repo, gateway))..attach();
  runApp(LeadBookApp(controller: controller));
  // Rebuild the notification schedule from the database on every launch
  // (covers reboot, app update, restore and time-zone changes).
  controller.reminders.sync();
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 56, color: Color(0xFFB3261E)),
                const SizedBox(height: 16),
                const Text('BCR LeadBook cannot start',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.4)),
                const SizedBox(height: 12),
                const Text('Your saved records have not been changed.', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
