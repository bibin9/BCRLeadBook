// Renders real app screens to PNG using Flutter's own engine (no phone needed).
// Run: flutter test tool/screenshots_test.dart   -> docs/screens/*.png
// These are rendered from the actual widgets with Roboto, not photos of a device.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bcr_leadbook/app.dart';
import 'package:bcr_leadbook/data/demo_data.dart';
import 'package:bcr_leadbook/services/app_controller.dart';
import 'package:bcr_leadbook/services/reminder_service.dart';
import 'package:bcr_leadbook/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/helpers.dart';

const fontDir = r'C:\Bibin\_tools\flutter\bin\cache\artifacts\material_fonts';

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.view(File('$fontDir\\$f').readAsBytesSync().buffer)));
  }
  await l.load();
}

ThemeData _theme() {
  final t = buildTheme();
  return t.copyWith(
    chipTheme: t.chipTheme.copyWith(
      labelStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 14, color: kInk),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

void main() {
  testWidgets('screenshots', (t) async {
    await loadFont('Roboto', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']);
    // Text styles without an explicit family fall back to the test font 'FlutterTest'; point it at Roboto.
    await loadFont('FlutterTest', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']);
    await loadFont('MaterialIcons', ['materialicons-regular.otf']);
    Directory('docs/screens').createSync(recursive: true);

    final env = TestEnv(start: DateTime(2026, 10, 4, 10, 30));
    final gw = FakeGateway();
    final app = AppController(repo: env.repo, reminders: ReminderService(env.repo, gw));
    t.view.physicalSize = const Size(1080, 2200);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    debugDisableShadows = false; // test mode draws shadows as solid black otherwise
    final key = GlobalKey();
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;

    Future<void> shot(String name) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.runAsync(() async {
        final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1.0);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('docs/screens/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    await t.pumpWidget(RepaintBoundary(key: key, child: LeadBookApp(controller: app, theme: _theme())));
    await shot('01_welcome');
    await t.tap(find.text('Get started'));
    await t.pumpAndSettle();
    DemoData.load(env.repo);
    app.changed();
    await shot('02_home');

    // Add Lead / Meeting form
    await t.tap(find.text('Add Lead / Meeting'));
    await t.pumpAndSettle();
    await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Company name'), 'Gulf Marine Services');
    await t.tap(find.widgetWithText(ChoiceChip, 'Hot'));
    await t.pumpAndSettle();
    await shot('03_form_top');
    final summary = find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Discussion points'));
    await t.ensureVisible(summary);
    await t.enterText(summary, 'Wants 3 medical quotes. Worried about premium increase. Promised comparison by Thursday.');
    await t.pumpAndSettle();
    await shot('04_form_notes');
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Discard'));
    await t.pumpAndSettle();

    // Pre-call page
    await t.tap(find.text('Leads'));
    await t.pumpAndSettle();
    await shot('05_leads');
    await t.tap(find.text('ABC Trading (demo)'));
    await t.pumpAndSettle();
    await shot('06_precall');
    await t.pageBack();
    await t.pumpAndSettle();

    await t.tap(find.text('Follow-ups'));
    await t.pumpAndSettle();
    await shot('07_followups');
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await shot('08_settings');
    debugDisableShadows = true; // restore before the test's invariant checks
  });
}
