// BAT (business acceptance testing) as a field insurance salesperson.
// Scenarios 1, 2, 3: capture after a meeting, pre-call prep, second meeting.
import 'package:bcr_leadbook/data/lead_entry.dart';
import 'package:bcr_leadbook/data/models.dart';
import 'package:bcr_leadbook/data/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_helpers.dart';

Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<void> tapSave(WidgetTester t) async {
  await t.tap(find.widgetWithText(FilledButton, 'Save').last);
  await t.pumpAndSettle();
}

Future<void> sheetSave(WidgetTester t) async {
  await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Save')));
  await t.pumpAndSettle();
}

Future<void> pickDay(WidgetTester t, {int monthsForward = 0, required String day}) async {
  for (var i = 0; i < monthsForward; i++) {
    await t.tap(find.byTooltip('Next month'));
    await t.pumpAndSettle();
  }
  for (var i = 0; i > monthsForward; i--) {
    await t.tap(find.byTooltip('Previous month'));
    await t.pumpAndSettle();
  }
  await t.tap(find.text(day).last);
  await t.pumpAndSettle();
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('BAT1: 2-minute capture in the car (Medical 15 Mar 2027 + Motor 20 Jul 2027, Hot, call Thursday)', (t) async {
    final u = await pumpApp(t, width: 392, height: 2400);
    var taps = 0;
    Future<void> tap(Finder f) async {
      taps++;
      await t.tap(f);
      await t.pumpAndSettle();
    }

    await tap(find.text('Add Lead / Meeting'));
    await t.enterText(fieldWithLabel('Company name'), 'Al Noor Contracting');
    await tap(find.widgetWithText(ChoiceChip, 'Hot'));

    await tap(find.text('Add the person you met'));
    await t.enterText(fieldWithLabel('Full name'), 'Rashid Khan');
    await t.enterText(fieldWithLabel('Phone / WhatsApp (optional)'), '050 123 4567');
    taps += 2;
    await sheetSave(t);
    taps++;

    // Medical 15 Mar 2027
    await tap(find.text('Add Product'));
    await tap(find.widgetWithText(ChoiceChip, 'Medical').last);
    await tap(find.text('Unknown (tap to set)').last);
    await pickDay(t, monthsForward: -1, day: '15');
    taps += 2;
    // Motor 20 Jul 2027
    await tap(find.text('Add Another Product'));
    await tap(find.widgetWithText(ChoiceChip, 'Motor').last);
    await tap(find.text('Unknown (tap to set)').last);
    await pickDay(t, monthsForward: 3, day: '20');
    taps += 2;

    await reveal(t, fieldWithHintStart('Discussion points'));
    await t.enterText(fieldWithHintStart('Discussion points'), 'Wants cheaper medical for 40 staff. Rashid = "Big R" to his team.');
    await reveal(t, fieldWithLabel('Next action required'));
    await t.enterText(fieldWithLabel('Next action required'), 'Call back with quotes');
    // "Thursday" is not a quick option: must use the calendar
    expect(find.widgetWithText(ChoiceChip, 'Thursday'), findsNothing);
    await t.ensureVisible(find.text('Pick a date'));
    await tap(find.text('Pick a date'));
    await pickDay(t, day: '8'); // Thu 8 Oct 2026
    taps += 2;
    await tapSave(t);
    // ignore: avoid_print
    print('BAT1 taps (approx, excluding typing): $taps');

    final row = u.env.repo.queryLeads(const LeadQuery(), u.env.today).single;
    final b = u.env.repo.bundle(row.company.id)!;
    expect(b.company.quality, LeadQuality.hot);
    final med = b.products.firstWhere((p) => p.line == ProductLine.medical);
    final mot = b.products.firstWhere((p) => p.line == ProductLine.motor);
    expect(med.expiryDate, '2027-03-15');
    expect(mot.expiryDate, '2027-07-20');
    expect(b.nextTask!.dueDate, '2026-10-08');
    expect(b.nextTask!.reminderTime, '09:00');
    expect(b.meetings.single.summary, contains('Big R'));
    expect(find.text('Pre-call'), findsOneWidget);
  });

  testWidgets('BAT2: pre-call page has everything without hunting', (t) async {
    final u = await pumpApp(t, width: 392, height: 2400);
    final r = u.env.repo.commitEntry(LeadEntry(
      companyName: 'Al Noor Contracting',
      location: 'Sharjah',
      trivia: 'Opening Abu Dhabi branch in Q1',
      quality: LeadQuality.hot,
      summary: 'Wants cheaper medical for 40 staff',
      taskAction: 'Call back with quotes',
      taskDue: '2026-10-08',
      meetingAt: DateTime(2026, 10, 3, 9),
      products: [
        Product(id: 'm', companyId: 'x', line: ProductLine.medical, expiryDate: '2027-03-15', insurer: 'Daman', notes: '40 lives, Cat B', createdAt: u.env.clock, updatedAt: u.env.clock),
      ],
    ));
    u.app.changed();
    await t.pumpAndSettle();
    await t.tap(find.text('Leads'));
    await t.pumpAndSettle();
    await t.tap(find.text('Al Noor Contracting'));
    await t.pumpAndSettle();
    expect(find.text('Call back with quotes'), findsOneWidget);
    expect(find.textContaining('Wants cheaper medical'), findsOneWidget);
    expect(find.textContaining('Abu Dhabi branch'), findsOneWidget);
    expect(find.textContaining('Medical'), findsWidgets);
    expect(find.textContaining('15 Mar 2027'), findsWidgets);
    // Insurer / policy notes are now shown on the pre-call page (fixed).
    expect(find.textContaining('Daman'), findsWidgets, reason: 'insurer visible on Pre-call (${r.companyId})');
  });

  testWidgets('BAT3: client calls back; second meeting with a different decision-maker', (t) async {
    final u = await pumpApp(t, width: 392, height: 2400);
    final repo = u.env.repo;
    final r = repo.commitEntry(LeadEntry(
      companyName: 'Al Noor Contracting',
      summary: 'First meeting',
      meetingAt: DateTime(2026, 10, 1, 9),
      taskAction: 'Call back with quotes',
      taskDue: '2026-10-08',
      newContacts: [Contact(id: 'c1', companyId: 'x', name: 'Rashid Khan', phone: '+971501234567', createdAt: u.env.clock, updatedAt: u.env.clock)],
      metContactId: 'c1',
    ));
    u.app.changed();
    await t.pumpAndSettle();
    await t.tap(find.text('Leads'));
    await t.pumpAndSettle();
    await t.tap(find.text('Al Noor Contracting'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add Meeting'));
    await t.pumpAndSettle();
    // meet the CFO this time
    await reveal(t, find.text('Person met'));
    await t.tap(find.text('Person met'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add new person…').last);
    await t.pumpAndSettle();
    await t.enterText(fieldWithLabel('Full name'), 'Meera Iyer');
    await t.enterText(fieldWithLabel('Job title (optional)'), 'CFO');
    await sheetSave(t);
    await reveal(t, fieldWithHintStart('Discussion points'));
    await t.enterText(fieldWithHintStart('Discussion points'), 'CFO approves budget. Needs board sign-off.');
    await reveal(t, fieldWithLabel('Next action required'));
    await t.enterText(fieldWithLabel('Next action required'), 'Send board presentation');
    await t.tap(find.widgetWithText(ChoiceChip, 'Next week'));
    await t.pump();
    await tapSave(t);
    // The app asks about the still-open earlier follow-up (fixed): tick it as done.
    expect(find.text('Earlier follow-ups still open'), findsOneWidget);
    expect(find.text('Call back with quotes'), findsOneWidget);
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await t.tap(find.text('Save').last);
    await t.pumpAndSettle();
    final b = repo.bundle(r.companyId)!;
    expect(b.meetings.length, 2);
    expect(b.contacts.map((c) => c.name), containsAll(['Rashid Khan', 'Meera Iyer']));
    expect(b.meetings.first.contactId, isNotNull);
    // The old "Call back with quotes" task is still pending after the new meeting:
    // the salesperson must go and tick it off by hand.
    final pending = b.pendingTasks.map((x) => x.action).toList();
    // ignore: avoid_print
    print('BAT3 pending tasks after meeting 2: $pending');
    expect(pending, ['Send board presentation'], reason: 'old follow-up closed through the prompt');
    // ignore: avoid_print
    print('BAT3 meeting0 contact=${b.meetings.first.contactId} next=${b.meetings.first.nextContactId} nextCall=${b.nextCallContact?.name}; texts: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(25).toList()}');
    // Pre-call page: who do I call? The newest meeting lists Meera as next-call contact.
    expect(find.textContaining('Meera Iyer'), findsWidgets);
    // Rashid (the original contact) is still reachable from the pre-call page (fixed).
    expect(find.text('Other people here'), findsOneWidget);
    expect(find.textContaining('Rashid Khan'), findsWidgets);
  });
}
