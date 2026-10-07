// QA exploratory UI tests. Tests tagged "BUG" assert the CORRECT behaviour and
// are skipped because they currently fail; remove the skip once fixed.
import 'package:bcr_leadbook/data/lead_entry.dart';
import 'package:bcr_leadbook/data/models.dart';
import 'package:bcr_leadbook/data/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'ui_helpers.dart';

Contact mk(String companyId, String name, {String notes = ''}) => Contact(
      id: newId(),
      companyId: companyId,
      name: name,
      notes: notes,
      createdAt: DateTime(2000),
      updatedAt: DateTime(2000),
    );

void main() {
  testWidgets('BUG #5: "Open it" must not silently replace the existing company rapport notes', (t) async {
    final u = await pumpApp(t);
    final id = u.env.repo.commitEntry(LeadEntry(companyName: 'ABC Trading LLC')..rapportEdits = {'': 'Plays golf'}).companyId;
    u.app.changed();
    await t.pumpAndSettle();
    await t.tap(find.text('Add Lead / Meeting'));
    await t.pumpAndSettle();
    await t.enterText(fieldWithLabel('Company name'), 'ABC Trading');
    await t.enterText(fieldWithHintStart('Hobbies'), 'Likes tea');
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Open it'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Save').last);
    await t.pumpAndSettle();
    expect(u.env.repo.getCompany(id)!.rapportNotes, contains('Plays golf'));
  });

  testWidgets('rapport notes typed per person survive switching person met', (t) async {
    final u = await pumpApp(t);
    final e = LeadEntry(companyName: 'Two Contacts');
    final a = mk(e.companyId, 'Alice');
    final b = mk(e.companyId, 'Bob');
    e.newContacts = [a, b];
    repoCommit(u, e);
    u.app.changed();
    await t.pumpAndSettle();
    await t.tap(find.text('Leads'));
    await t.pumpAndSettle();
    await t.tap(find.text('Two Contacts'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add Meeting'));
    await t.pumpAndSettle();

    Future<void> pick(String name) async {
      await t.tap(find.byType(DropdownButtonFormField<String?>).first);
      await t.pumpAndSettle();
      await t.tap(find.text(name).last);
      await t.pumpAndSettle();
    }

    await pick('Alice');
    await t.enterText(fieldWithHintStart('Hobbies'), 'A-notes');
    await pick('Bob');
    expect(find.widgetWithText(TextField, 'A-notes'), findsNothing);
    await t.enterText(fieldWithHintStart('Hobbies'), 'B-notes');
    await pick('Alice');
    expect(find.widgetWithText(TextField, 'A-notes'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Save').last);
    await t.pumpAndSettle();
    expect(u.env.repo.getContact(a.id)!.notes, 'A-notes');
    expect(u.env.repo.getContact(b.id)!.notes, 'B-notes');
    expect(u.env.repo.meetingsFor(e.companyId).single.contactId, a.id);
  });

  testWidgets('double-tapping Save creates exactly one company', (t) async {
    final u = await pumpApp(t);
    await t.tap(find.text('Add Lead / Meeting'));
    await t.pumpAndSettle();
    await t.enterText(fieldWithLabel('Company name'), 'Once Co');
    final save = find.widgetWithText(FilledButton, 'Save').last;
    await t.tap(save);
    await t.tap(save, warnIfMissed: false);
    await t.pumpAndSettle();
    expect(u.env.repo.companyCount, 1);
  });

  testWidgets('blank form leaves without a prompt; system back on dirty form prompts', (t) async {
    final u = await pumpApp(t);
    await t.tap(find.text('Add Lead / Meeting'));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsNothing);
    expect(u.env.repo.listDrafts(), isEmpty);
    expect(find.text('Add Lead / Meeting'), findsOneWidget);
    await t.tap(find.text('Add Lead / Meeting'));
    await t.pumpAndSettle();
    await t.enterText(fieldWithLabel('Company name'), 'Typed');
    await t.pump();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Typed'), findsOneWidget);
  });

  testWidgets('removing a product added in the same form works', (t) async {
    final u = await pumpApp(t);
    await t.tap(find.text('Add Lead / Meeting'));
    await t.pumpAndSettle();
    await t.enterText(fieldWithLabel('Company name'), 'NewProd Co');
    await t.tap(find.text('Add Product'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add Another Product'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Remove this product').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Remove').last);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Save').last);
    await t.pumpAndSettle();
    final id = u.env.repo.queryLeads(const LeadQuery(), u.env.today).single.company.id;
    expect(u.env.repo.productsFor(id), hasLength(1));
  });

  testWidgets('BUG #7: expanding an EXISTING product tile in the Add Meeting form must not throw', (t) async {
    final env = TestEnv();
    final e = LeadEntry(companyName: 'Prod Co');
    e.products = [
      Product(id: 'p1', companyId: e.companyId, line: ProductLine.medical, createdAt: DateTime(2000), updatedAt: DateTime(2000))
    ];
    env.repo.commitEntry(e);
    await pumpApp(t, existing: env);
    await t.tap(find.text('Leads'));
    await t.pumpAndSettle();
    await t.tap(find.text('Prod Co'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add Meeting'));
    await t.pumpAndSettle();
    await t.tap(find.text('Medical').first);
    await t.pumpAndSettle();
    // _TypeError: 'bool' is not a subtype of 'double?' (PageStorageKey on ExpansionTile collides with
    // the inner TextField scroll position, entry_screen.dart:760)
    expect(t.takeException(), isNull);
  });

  testWidgets('BUG #9: a realistic long company location must not overflow the company page at 360px / 1x text', (t) async {
    final env = TestEnv();
    env.repo.commitEntry(LeadEntry(companyName: 'Loc Co', location: 'Office 1204, Concord Tower, Dubai Media City, Dubai, United Arab Emirates'));
    await pumpApp(t, existing: env, width: 360, height: 800);
    await t.tap(find.text('Leads'));
    await t.pumpAndSettle();
    await t.tap(find.text('Loc Co'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull); // company_screen.dart:151 Row > Text without Flexible
  });

  testWidgets('BUG #8 (low): empty state must not overflow at 320x568 with 2x text (Follow-ups > Today)', (t) async {
    final env = TestEnv();
    env.repo.commitEntry(LeadEntry(companyName: 'Short')..taskAction = 'Call'..taskDue = '2026-09-01');
    await pumpApp(t, existing: env, width: 320, height: 640, textScale: 2.0);
    await t.tap(find.text('Follow-ups'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull); // EmptyState (common.dart:113) is a non-scrolling Column
  });

  for (final screen in ['Home', 'Leads', 'Follow-ups', 'Settings', 'form', 'company']) {
    testWidgets('320px wide, 2x text, long/emoji/unbroken data: no overflow on $screen', (t) async {
      final env = TestEnv();
      final long = 'Supercalifragilisticexpialidocious' * 4;
      final e = LeadEntry(companyName: '$long 🏢', location: long)
        ..quality = LeadQuality.future
        ..targetMonth = '2027-12'
        ..summary = long * 3
        ..trivia = long
        ..taskAction = 'Call $long'
        ..taskDue = '2026-10-03';
      final ct = mk(e.companyId, 'Contact $long');
      e.newContacts = [ct];
      e.metContactId = ct.id;
      e.products = [
        Product(
            id: newId(), companyId: e.companyId, line: ProductLine.other, customLine: long,
            label: long, insurer: long, expiryDate: '2026-01-01', createdAt: DateTime(2000), updatedAt: DateTime(2000)),
        Product(id: newId(), companyId: e.companyId, expiryDate: '2026-10-20', createdAt: DateTime(2000), updatedAt: DateTime(2000)),
      ];
      env.repo.commitEntry(e);
      final u = await pumpApp(t, existing: env, width: 320, height: 640, textScale: 2.0);
      if (screen == 'Leads') {
        await t.tap(find.text('Leads'));
      } else if (screen == 'Follow-ups') {
        await t.tap(find.text('Follow-ups'));
      } else if (screen == 'Settings') {
        await t.tap(find.text('Settings'));
      } else if (screen == 'form') {
        await t.tap(find.text('Add Lead / Meeting'));
        await t.pumpAndSettle();
        await t.enterText(fieldWithLabel('Company name'), long);
        await t.pump(const Duration(milliseconds: 400));
      } else if (screen == 'company') {
        await t.tap(find.text('Leads'));
        await t.pumpAndSettle();
        await t.tap(find.textContaining('Supercali').first);
        await t.pumpAndSettle();
        for (final tab in ['Notes', 'People', 'Policies']) {
          await t.tap(find.text(tab));
          await t.pumpAndSettle();
        }
      }
      await t.pumpAndSettle();
      final ex = t.takeException();
      if (ex != null) {
        // ignore: avoid_print
        print(ex is FlutterError ? ex.toStringDeep() : ex.toString());
      }
      expect(ex, isNull);
      expect(u.app.repo.companyCount, 1);
    });
  }

  testWidgets('BUG #6 (low, debug-mode assertion): rescheduling a follow-up overdue by more than a year must not throw', (t) async {
    final u = await pumpApp(t);
    final r = u.env.repo.commitEntry(LeadEntry(companyName: 'Ancient')..taskAction = 'old'..taskDue = '2024-01-01');
    expect(r.taskId, isNotNull);
    u.app.changed();
    await t.pumpAndSettle();
    await t.tap(find.text('Follow-ups'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Overdue (1)'));
    await t.pump();
    await t.tap(find.text('Overdue (1)'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('More actions'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reschedule…'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}

void repoCommit(UiEnv u, LeadEntry e) => u.env.repo.commitEntry(e);
