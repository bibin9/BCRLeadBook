import 'package:bcr_leadbook/data/database.dart';
import 'package:bcr_leadbook/data/repository.dart';
import 'package:bcr_leadbook/services/reminder_service.dart';

/// A repository on an in-memory database with a controllable clock.
class TestEnv {
  TestEnv({DateTime? start}) : clock = start ?? DateTime(2026, 10, 3, 10, 30) {
    repo = Repository(openMemoryDatabase(), clock: () => clock);
  }
  DateTime clock;
  late final Repository repo;

  DateTime get today => DateTime(clock.year, clock.month, clock.day);

  void advance(Duration d) => clock = clock.add(d);
}

class FakeGateway implements NotificationGateway {
  bool permitted = true;
  bool willGrant = true;
  int requests = 0;
  int cancelAllCalls = 0;
  int tzRefreshes = 0;
  final Map<int, (DateTime, String, String)> scheduled = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<bool> requestPermission() async {
    requests++;
    permitted = willGrant;
    return willGrant;
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    scheduled.clear();
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    scheduled[id] = (at, title, body);
  }

  @override
  Future<void> refreshTimeZone() async {
    tzRefreshes++;
  }
}
