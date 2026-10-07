import 'package:bcr_leadbook/app.dart';
import 'package:bcr_leadbook/services/app_controller.dart';
import 'package:bcr_leadbook/services/reminder_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class UiEnv {
  UiEnv(this.env, this.gw, this.app);
  final TestEnv env;
  final FakeGateway gw;
  final AppController app;
}

/// Pumps the whole app on a tall phone-width screen so long forms are fully
/// laid out (lists build lazily).
Future<UiEnv> pumpApp(
  WidgetTester t, {
  bool welcomeSeen = true,
  double width = 412,
  double height = 6000,
  double textScale = 1.0,
  TestEnv? existing,
}) async {
  final env = existing ?? TestEnv();
  if (welcomeSeen) env.repo.setSetting('welcome_seen', '1');
  final gw = FakeGateway();
  final app = AppController(repo: env.repo, reminders: ReminderService(env.repo, gw));
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    t.view.reset();
    t.platformDispatcher.clearAllTestValues();
  });
  await t.pumpWidget(LeadBookApp(controller: app));
  await t.pumpAndSettle();
  return UiEnv(env, gw, app);
}

Finder fieldWithLabel(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
    description: 'TextField "$label"');

Finder fieldWithHintStart(String start) => find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.hintText ?? '').startsWith(start),
    description: 'TextField hint "$start..."');
