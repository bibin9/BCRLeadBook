import 'package:bcr_leadbook/data/lead_entry.dart';
import 'package:bcr_leadbook/data/models.dart';
import 'package:bcr_leadbook/data/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_helpers.dart';

Future<void> openAddLead(WidgetTester t) async {
  await t.tap(find.text('Add Lead / Meeting'));
  await t.pumpAndSettle();
}

Future<void> tapSave(WidgetTester t) async {
  await t.tap(find.widgetWithText(FilledButton, 'Save').last);
  await t.pumpAndSettle();
}

void expectClean(WidgetTester t) {
  final ex = t.takeException();
  if (ex != null) {
    // ignore: avoid_print
    print(ex is FlutterError ? ex.toStringDeep() : ex.toString());
  }
  expect(ex, isNull);
}

Future<void> tapTab(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text));
  await t.pump();
  await t.tap(find.text(text));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('14. welcome screen shows the exact signature; dashboard footer shows it too', (t) async {
    await pumpApp(t, welcomeSeen: false);
    expect(find.text('BCR (BibinCutRiver)'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    await t.tap(find.text('Get started'));
    await t.pumpAndSettle();
    expect(find.text('Add Lead / Meeting'), findsOneWidget);
    await t.scrollUntilVisible(find.text('BCR (BibinCutRiver)'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('BCR (BibinCutRiver)'), findsOneWidget);
  });

  testWidgets('About screen shows the exact signature', (t) async {
    await pumpApp(t);
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await t.tap(find.text('About BCR LeadBook'));
    await t.pumpAndSettle();
    expect(find.text('BCR (BibinCutRiver)'), findsOneWidget);
    expect(find.textContaining('Version 1.0.0'), findsOneWidget);
  });

  testWidgets('empty app: friendly empty states, no demo data', (t) async {
    final u = await pumpApp(t);
    expect(find.text('Ready for your first meeting'), findsOneWidget);
    expect(u.env.repo.companyCount, 0);
    await t.tap(find.text('Leads'));
    await t.pumpAndSettle();
    expect(find.text('No leads yet'), findsOneWidget);
    await t.tap(find.text('Follow-ups'));
    await t.pumpAndSettle();
    expect(find.text('Nothing due today'), findsOneWidget);
  });

  testWidgets('1. a lead saves with only a company name', (t) async {
    final u = await pumpApp(t);
    await openAddLead(t);
    await t.enterText(fieldWithLabel('Company name'), 'Solo Co');
    await tapSave(t);
    final rows = u.env.repo.queryLeads(const LeadQuery(), u.env.today);
    expect(rows.single.company.name, 'Solo Co');
    expect(rows.single.company.quality, isNull);
    expect(u.env.repo.meetingsFor(rows.single.company.id), isEmpty);
    // lands on the company page; "Saved" confirmation shown
    expect(find.text('Pre-call'), findsOneWidget);
    expect(find.textContaining('Saved'), findsWidgets);
  });

  testWidgets('saving with an empty name shows a friendly message and saves nothing', (t) async {
    final u = await pumpApp(t);
    await openAddLead(t);
    await tapSave(t);
    expect(find.text('Please enter the company name'), findsOneWidget);
    expect(u.env.repo.companyCount, 0);
  });

  testWidgets('2-4. full realistic entry through the UI', (t) async {
    final u = await pumpApp(t);
    await openAddLead(t);
    await t.enterText(fieldWithLabel('Company name'), 'ABC Trading');
    await t.tap(find.widgetWithText(ChoiceChip, 'Hot'));
    await t.pump();

    // person met
    await t.tap(find.text('Add the person you met'));
    await t.pumpAndSettle();
    await t.enterText(fieldWithLabel('Full name'), 'Sam Accountant');
    await t.enterText(fieldWithLabel('Phone / WhatsApp (optional)'), '+971 50 123 4567');
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Save')));
    await t.pumpAndSettle();

    // a different next-call decision-maker
    await t.tap(find.byType(SwitchListTile).first); // same person -> off
    await t.pumpAndSettle();
    await t.tap(find.text('Key contact for the next call'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add new person…').last);
    await t.pumpAndSettle();
    await t.enterText(fieldWithLabel('Full name'), 'Dana Director');
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Save')));
    await t.pumpAndSettle();

    // two products, different expiry
    for (final (button, line) in [('Add Product', 'Medical'), ('Add Another Product', 'Motor')]) {
      await t.tap(find.text(button));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, line).last);
      await t.pump();
      await t.tap(find.text('Unknown (tap to set)').last);
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
    }

    await t.enterText(fieldWithHintStart('Discussion points'), 'Wants 3 quotes. Worried about premiums.');
    await t.enterText(fieldWithHintStart('Hobbies'), 'Plays cricket');
    await t.enterText(fieldWithLabel('Next action required'), 'Send quotes');
    await t.tap(find.widgetWithText(ChoiceChip, 'In 3 days'));
    await t.pump();
    await tapSave(t);

    final repo = u.env.repo;
    final row = repo.queryLeads(const LeadQuery(), u.env.today).single;
    final b = repo.bundle(row.company.id)!;
    expect(b.company.quality, LeadQuality.hot);
    expect(b.products.length, 2);
    expect(b.products.map((p) => p.line).toSet(), {ProductLine.medical, ProductLine.motor});
    expect(b.products.every((p) => p.expiryDate != null), isTrue);
    expect(b.meetings.single.summary, contains('3 quotes'));
    final met = b.contacts.firstWhere((c) => c.name == 'Sam Accountant');
    final dm = b.contacts.firstWhere((c) => c.name == 'Dana Director');
    expect(b.meetings.single.contactId, met.id);
    expect(b.meetings.single.nextContactId, dm.id);
    expect(met.notes, 'Plays cricket');
    expect(b.nextTask!.action, 'Send quotes');
    expect(b.nextTask!.dueDate, '2026-10-06');
    expect(b.nextTask!.reminderTime, '09:00');
    // pre-call page shows the next-call contact and the notes
    expect(find.text('Dana Director'), findsWidgets);
    expect(find.textContaining('Wants 3 quotes'), findsWidgets);
    // reminder was scheduled on the (fake) device
    await u.app.reminders.sync();
    expect(u.gw.scheduled.length, 1);
  });

  testWidgets('7. unfinished entry is kept as a draft and can be resumed', (t) async {
    final u = await pumpApp(t);
    await openAddLead(t);
    await t.enterText(fieldWithLabel('Company name'), 'Draft Co');
    await t.enterText(fieldWithHintStart('Discussion points'), 'half typed notes');
    await t.pump(const Duration(seconds: 1)); // autosave debounce
    expect(u.env.repo.loadDraft('new'), isNotNull);

    // Back asks before throwing work away
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);
    await t.tap(find.text('Keep draft & leave'));
    await t.pumpAndSettle();

    // Dashboard offers it
    expect(find.text('Unfinished lead: Draft Co'), findsOneWidget);
    await t.tap(find.text('Unfinished lead: Draft Co'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Draft Co'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'half typed notes'), findsOneWidget);

    // Save finishes it and clears the draft
    await tapSave(t);
    expect(u.env.repo.loadDraft('new'), isNull);
    expect(u.env.repo.companyCount, 1);
  });

  testWidgets('Add Lead: starting again offers to resume; "Start fresh" discards', (t) async {
    final u = await pumpApp(t);
    u.env.repo.saveDraft('new', (LeadEntry(companyName: 'Old draft')).encode());
    await t.pumpAndSettle();
    await openAddLead(t);
    expect(find.text('Resume unfinished entry?'), findsOneWidget);
    await t.tap(find.text('Start fresh'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Old draft'), findsNothing);
    expect(u.env.repo.loadDraft('new'), isNull);
  });

  testWidgets('discarding from the back dialog deletes the draft', (t) async {
    final u = await pumpApp(t);
    await openAddLead(t);
    await t.enterText(fieldWithLabel('Company name'), 'Throwaway');
    await t.pump(const Duration(seconds: 1));
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Discard'));
    await t.pumpAndSettle();
    expect(u.env.repo.loadDraft('new'), isNull);
    expect(find.text('Ready for your first meeting'), findsOneWidget);
  });

  testWidgets('a similar company name is suggested but never forced', (t) async {
    final u = await pumpApp(t);
    u.env.repo.commitEntry(LeadEntry(companyName: 'ABC Trading LLC', summary: 'Earlier notes'));
    u.app.changed();
    await t.pumpAndSettle();
    await openAddLead(t);
    await t.enterText(fieldWithLabel('Company name'), 'ABC Trading');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Already saved? A similar company exists:'), findsOneWidget);
    expect(find.text('ABC Trading LLC'), findsOneWidget);
    // genuinely different company: dismiss, then save as a new record
    await t.tap(find.text('This is a different company'));
    await t.pump();
    expect(find.text('Already saved? A similar company exists:'), findsNothing);
    await tapSave(t);
    expect(u.env.repo.companyCount, 2);
  });

  testWidgets('"Open it" switches to the existing company and keeps typed notes', (t) async {
    final u = await pumpApp(t);
    final id = u.env.repo.commitEntry(LeadEntry(companyName: 'ABC Trading LLC', summary: 'Earlier notes')).companyId;
    u.app.changed();
    await t.pumpAndSettle();
    await openAddLead(t);
    await t.enterText(fieldWithLabel('Company name'), 'ABC Trading');
    await t.enterText(fieldWithHintStart('Discussion points'), 'Fresh notes');
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Open it'));
    await t.pumpAndSettle();
    expect(find.text('Add Meeting'), findsWidgets); // now an "Add Meeting" form
    await tapSave(t);
    final ms = u.env.repo.meetingsFor(id);
    expect(u.env.repo.companyCount, 1);
    expect(ms.map((m) => m.summary).toSet(), {'Earlier notes', 'Fresh notes'});
  });

  testWidgets('5. Add Meeting from the company page adds history and keeps the old notes', (t) async {
    final u = await pumpApp(t);
    final id = u.env.repo
        .commitEntry(LeadEntry(companyName: 'History Co', trivia: 'Opening in Oman', summary: 'First meeting notes', meetingAt: DateTime(2026, 9, 1, 9)))
        .companyId;
    u.app.changed();
    await t.pumpAndSettle();
    await t.tap(find.text('Leads'));
    await t.pumpAndSettle();
    await t.tap(find.text('History Co'));
    await t.pumpAndSettle();
    expect(find.textContaining('First meeting notes'), findsWidgets);
    await t.tap(find.text('Add Meeting'));
    await t.pumpAndSettle();
    // company context is carried into the form
    expect(find.widgetWithText(TextField, 'Opening in Oman'), findsOneWidget);
    await t.enterText(fieldWithHintStart('Discussion points'), 'Second meeting notes');
    await tapSave(t);
    final ms = u.env.repo.meetingsFor(id);
    expect(ms.length, 2);
    expect(ms.map((m) => m.summary), containsAll(['First meeting notes', 'Second meeting notes']));
    // company page now shows the newest as "last meeting"
    expect(find.textContaining('Second meeting notes'), findsWidgets);
    // history tab shows both
    await tapTab(t, 'Notes');
    expect(find.textContaining('First meeting notes'), findsOneWidget);
    expect(find.textContaining('Second meeting notes'), findsOneWidget);
    expect(find.text('Meeting history (2)'), findsOneWidget);
  });

  testWidgets('8. leads search and filters through the UI', (t) async {
    final u = await pumpApp(t);
    DemoLike.seed(u);
    await t.pumpAndSettle();
    await t.tap(find.text('Leads'));
    await t.pumpAndSettle();
    expect(find.text('3 leads'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, 'cedar');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.text('Cedar Logistics'), findsOneWidget);
    expect(find.text('Alpha Co'), findsNothing);

    await t.enterText(find.byType(TextField).first, '');
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Filters'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilterChip, 'Hot'));
    await t.pump();
    await t.tap(find.text('Show results'));
    await t.pumpAndSettle();
    expect(find.text('Alpha Co'), findsOneWidget);
    expect(find.text('Cedar Logistics'), findsNothing);
    expect(find.text('1 lead'), findsOneWidget);
    expect(find.text('Hot'), findsWidgets); // text label, not only colour
  });

  testWidgets('9. follow-ups: complete with undo, reschedule, snooze (UI)', (t) async {
    final u = await pumpApp(t);
    final repo = u.env.repo;
    final r = repo.commitEntry(LeadEntry(companyName: 'Due Co', taskAction: 'Call Due Co', taskDue: '2026-10-03'));
    repo.upsertTask(FollowUpTask(
        id: 'od',
        companyId: r.companyId,
        action: 'Old promise',
        dueDate: '2026-09-28',
        createdAt: u.env.clock,
        updatedAt: u.env.clock));
    u.app.changed();
    await t.pumpAndSettle();
    expect(find.text('Overdue follow-ups'), findsOneWidget);
    await t.tap(find.text('Follow-ups'));
    await t.pumpAndSettle();
    expect(find.text('Today (1)'), findsOneWidget);
    expect(find.text('Overdue (1)'), findsOneWidget);
    expect(find.text('Call Due Co'), findsOneWidget);

    // snooze until tomorrow -> moves to Upcoming
    await t.tap(find.byTooltip('More actions'));
    await t.pumpAndSettle();
    await t.tap(find.text('Snooze until tomorrow'));
    await t.pumpAndSettle();
    expect(find.text('Upcoming (1)'), findsOneWidget);
    expect(find.text('Today (0)'), findsOneWidget);
    expect(repo.getTask(r.taskId!)!.dueDate, '2026-10-04');

    // complete the overdue one, then undo
    await tapTab(t, 'Overdue (1)');
    await t.tap(find.byTooltip('Mark completed'));
    await t.pumpAndSettle();
    expect(repo.getTask('od')!.status, TaskStatus.completed);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(repo.getTask('od')!.status, TaskStatus.pending);
    await t.tap(find.byTooltip('Mark completed'));
    await t.pumpAndSettle();
    await tapTab(t, 'Completed (1)');
    expect(find.text('Old promise'), findsOneWidget);
  });

  testWidgets('11. notification permission denied: saving works and the due task is still shown', (t) async {
    final u = await pumpApp(t);
    u.gw.permitted = false;
    u.gw.willGrant = false;
    await openAddLead(t);
    await t.enterText(fieldWithLabel('Company name'), 'Denied Co');
    await t.enterText(fieldWithLabel('Next action required'), 'Phone them');
    await t.tap(find.widgetWithText(ChoiceChip, 'Tomorrow'));
    await t.pump();
    await tapSave(t);
    expect(u.gw.requests, 1);
    expect(u.gw.scheduled, isEmpty);
    expect(u.env.repo.companyCount, 1);
    expect(u.env.repo.tasks(pending: true).single.task.action, 'Phone them');
    // Follow-ups tab still lists it
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Follow-ups'));
    await t.pumpAndSettle();
    await tapTab(t, 'Upcoming (1)');
    expect(find.text('Phone them'), findsOneWidget);
  });

  testWidgets('delete company needs confirmation', (t) async {
    final u = await pumpApp(t);
    final id = u.env.repo.commitEntry(LeadEntry(companyName: 'Doomed Co')).companyId;
    u.app.changed();
    await t.pumpAndSettle();
    await t.tap(find.text('Leads'));
    await t.pumpAndSettle();
    await t.tap(find.text('Doomed Co'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Company options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete company…'));
    await t.pumpAndSettle();
    expect(find.text('Delete Doomed Co?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(u.env.repo.getCompany(id), isNotNull);
    await t.tap(find.byTooltip('Company options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete company…'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete everything'));
    await t.pumpAndSettle();
    expect(u.env.repo.getCompany(id), isNull);
  });

  testWidgets('expired and upcoming policies are labelled with text', (t) async {
    final u = await pumpApp(t);
    final repo = u.env.repo;
    final cid = 'x1';
    repo.saveCompany(Company(id: cid, name: 'Policy Co', createdAt: u.env.clock, updatedAt: u.env.clock));
    for (final (i, e) in [(0, '2026-09-01'), (1, '2026-10-13'), (2, null)]) {
      repo.saveProduct(Product(
          id: 'p$i',
          companyId: cid,
          line: ProductLine.values[i],
          expiryDate: e,
          createdAt: u.env.clock,
          updatedAt: u.env.clock));
    }
    u.app.changed();
    await t.pumpAndSettle();
    await t.tap(find.text('Leads'));
    await t.pumpAndSettle();
    await t.tap(find.text('Policy Co'));
    await t.pumpAndSettle();
    expect(find.text('Expired'), findsWidgets);
    expect(find.text('10 days left'), findsWidgets);
    await tapTab(t, 'Policies');
    expect(find.text('Expiry unknown'), findsOneWidget);
    expect(find.text('Expiry date: unknown'), findsOneWidget);
  });

  group('accessibility: 2x text size does not overflow', () {
    for (final tab in ['Home', 'Leads', 'Follow-ups', 'Settings']) {
      testWidgets(tab, (t) async {
        FlutterError.onError = FlutterError.dumpErrorToConsole;
        final u = await pumpApp(t, width: 360, height: 760, textScale: 2.0);
        DemoLike.seed(u);
        await t.pumpAndSettle();
        await t.tap(find.text(tab).last);
        await t.pumpAndSettle();
        expectClean(t);
      });
    }
    testWidgets('entry form + company page', (t) async {
      final u = await pumpApp(t, width: 360, height: 760, textScale: 2.0);
      DemoLike.seed(u);
      await t.pumpAndSettle();
      await t.tap(find.text('Add Lead / Meeting'));
      await t.pumpAndSettle();
      expectClean(t);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('Leads'));
      await t.pumpAndSettle();
      await t.tap(find.text('Alpha Co'));
      await t.pumpAndSettle();
      expectClean(t);
      await t.tap(find.text('Add Meeting'));
      await t.pumpAndSettle();
      expectClean(t);
    });
  });
}

class DemoLike {
  /// Three companies: Alpha (hot, product, overdue task), Beta (warm), Cedar.
  static String seed(UiEnv u) {
    final r = u.env.repo;
    final a = r.commitEntry(LeadEntry(
        companyName: 'Alpha Co',
        quality: LeadQuality.hot,
        products: [
          Product(
              id: 'pa',
              companyId: 'unused',
              line: ProductLine.medical,
              expiryDate: '2026-12-01',
              createdAt: u.env.clock,
              updatedAt: u.env.clock)
        ],
        taskAction: 'Send quote',
        taskDue: '2026-10-01'));
    r.commitEntry(LeadEntry(companyName: 'Beta Co', quality: LeadQuality.warm));
    r.commitEntry(LeadEntry(companyName: 'Cedar Logistics', taskAction: 'Later', taskDue: '2026-12-01'));
    u.app.changed();
    return a.companyId;
  }
}
