// QA exploratory tests (data layer). Tests tagged "BUG" assert the CORRECT
// behaviour and are skipped because they currently fail; remove the skip once
// the defect is fixed.
import 'dart:convert';

import 'package:bcr_leadbook/core/dates.dart';
import 'package:bcr_leadbook/data/backup_service.dart';
import 'package:bcr_leadbook/data/csv_export.dart';
import 'package:bcr_leadbook/data/demo_data.dart';
import 'package:bcr_leadbook/data/lead_entry.dart';
import 'package:bcr_leadbook/data/models.dart';
import 'package:bcr_leadbook/data/repository.dart';
import 'package:bcr_leadbook/services/app_controller.dart';
import 'package:bcr_leadbook/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Contact mk(String companyId, String name, {String notes = '', String phone = ''}) => Contact(
      id: newId(),
      companyId: companyId,
      name: name,
      notes: notes,
      phone: phone,
      createdAt: DateTime(2000),
      updatedAt: DateTime(2000),
    );

/// Minimal RFC-4180 parser (handles quotes, commas, CRLF inside quotes).
List<List<String>> parseCsv(String text) {
  if (text.startsWith('\u{FEFF}')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final f = StringBuffer();
  var q = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (q) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          f.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        f.write(c);
      }
    } else if (c == '"') {
      q = true;
    } else if (c == ',') {
      row.add(f.toString());
      f.clear();
    } else if (c == '\r') {
    } else if (c == '\n') {
      row.add(f.toString());
      f.clear();
      rows.add(row);
      row = [];
    } else {
      f.write(c);
    }
  }
  return rows;
}

void main() {
  late TestEnv env;
  late Repository repo;
  setUp(() {
    env = TestEnv();
    repo = env.repo;
  });

  group('entry commit edge cases', () {
    test('BUG #1: a stale "person met" id (contact deleted after draft was saved) must not block saving', () {
      final e0 = LeadEntry(companyName: 'Acme');
      final c = mk(e0.companyId, 'Alice');
      e0.newContacts = [c];
      e0.metContactId = c.id;
      repo.commitEntry(e0);
      // user starts an "Add Meeting" draft that picks Alice ...
      final draft = LeadEntry(companyId: e0.companyId, companyName: 'Acme', addingToExisting: true)
        ..metContactId = c.id
        ..summary = 'important notes';
      final restored = LeadEntry.tryDecode(draft.encode())!;
      // ... Alice is deleted from the company page, then the draft is resumed.
      repo.deleteContact(c.id);
      expect(() => repo.commitEntry(restored), returnsNormally,
          reason: 'FOREIGN KEY failure blocks the whole save; dropdown shows "Not selected" so user cannot see why');
    });

    test('default follow-up date is tomorrow across month, year and leap boundaries', () {
      for (final (now, want) in [
        (DateTime(2026, 1, 31, 23, 59), '2026-02-01'),
        (DateTime(2026, 12, 31, 23, 59), '2027-01-01'),
        (DateTime(2028, 2, 28, 12), '2028-02-29'),
        (DateTime(2027, 2, 28, 12), '2027-03-01'),
        (DateTime(2026, 3, 28, 0, 0), '2026-03-29'), // EU DST change night
        (DateTime(2026, 10, 24, 23, 30), '2026-10-25'),
      ]) {
        final t = TestEnv(start: now);
        final r = t.repo.commitEntry(LeadEntry(companyName: 'X')..taskAction = 'call');
        expect(t.repo.getTask(r.taskId!)!.dueDate, want, reason: '$now');
      }
    });

    test('Dates arithmetic: addDays/daysBetween/addMonths consistent for every day 2024..2031', () {
      var d = DateTime(2024, 1, 1);
      final end = DateTime(2031, 12, 31);
      while (!d.isAfter(end)) {
        final n = Dates.addDays(d, 1);
        expect(Dates.daysBetween(d, n), 1, reason: '$d');
        expect(Dates.parseIso(Dates.toIso(d)), d);
        final m = Dates.addMonths(d, 1);
        expect(m.day, lessThanOrEqualTo(d.day));
        expect(Dates.daysBetween(d, Dates.addMonths(d, 12)) >= 365, isTrue);
        d = n;
      }
      expect(Dates.addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(Dates.addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
      expect(Dates.addMonths(DateTime(2026, 12, 31), 2), DateTime(2027, 2, 28));
      expect(Dates.addMonths(DateTime(2026, 3, 31), -1), DateTime(2026, 2, 28));
    });

    test('created date is never overwritten by any write path', () {
      final e = LeadEntry(companyName: 'Acme')..location = 'Dubai';
      final c = mk(e.companyId, 'Alice');
      e.newContacts = [c];
      e.metContactId = c.id;
      e.products = [
        Product(id: newId(), companyId: e.companyId, createdAt: DateTime(2000), updatedAt: DateTime(2000))
      ];
      repo.commitEntry(e);
      final created = repo.getCompany(e.companyId)!.createdAt;
      final cc = repo.getContact(c.id)!.createdAt;
      env.advance(const Duration(days: 40));
      // Add Meeting form
      final e2 = LeadEntry(companyId: e.companyId, companyName: 'Acme Renamed', addingToExisting: true)
        ..products = repo.productsFor(e.companyId)
        ..loadedProductIds = repo.productsFor(e.companyId).map((p) => p.id).toSet()
        ..rapportEdits = {c.id: 'new rapport'}
        ..metContactId = c.id
        ..summary = 's';
      repo.commitEntry(e2);
      repo.updateCompany(repo.getCompany(e.companyId)!.copyWith(name: 'Z'));
      repo.upsertContact(repo.getContact(c.id)!.copyWith(name: 'Alice 2'));
      expect(repo.getCompany(e.companyId)!.createdAt, created);
      expect(repo.getContact(c.id)!.createdAt, cc);
      expect(repo.getCompany(e.companyId)!.updatedAt.isAfter(created), isTrue);
      // restore keeps it
      final json = BackupService(repo).createBackup();
      final env2 = TestEnv();
      final svc = BackupService(env2.repo);
      svc.restore(svc.parse(json));
      expect(env2.repo.getCompany(e.companyId)!.createdAt, created);
    });

    test('target month and follow-up date are independent in every path', () {
      final e = LeadEntry(companyName: 'Acme')
        ..targetMonth = '2027-03'
        ..taskAction = 'call'
        ..taskDue = '2026-10-05';
      final r = repo.commitEntry(e);
      repo.rescheduleTask(r.taskId!, DateTime(2028, 1, 1));
      repo.snoozeTaskUntilTomorrow(r.taskId!, env.today);
      repo.completeTask(r.taskId!);
      repo.reopenTask(r.taskId!);
      expect(repo.getCompany(e.companyId)!.targetMonth, '2027-03');
      // Changing target month does not touch tasks.
      final due = repo.getTask(r.taskId!)!.dueDate;
      repo.updateCompany(repo.getCompany(e.companyId)!.copyWith(targetMonth: '2029-12'));
      expect(repo.getTask(r.taskId!)!.dueDate, due);
      // Add Meeting without touching target month keeps it.
      final e2 = LeadEntry(companyId: e.companyId, companyName: 'Acme', addingToExisting: true, targetMonth: '2029-12')
        ..summary = 'x';
      repo.commitEntry(e2);
      expect(repo.getCompany(e.companyId)!.targetMonth, '2029-12');
    });

    test('rapport notes are stored per contact; company-level only when nobody chosen', () {
      final e = LeadEntry(companyName: 'Acme');
      final a = mk(e.companyId, 'Alice', notes: 'orig A');
      final b = mk(e.companyId, 'Bob');
      e.newContacts = [a, b];
      e.metContactId = a.id;
      e.rapportEdits = {a.id: 'A edited', b.id: 'B typed'};
      repo.commitEntry(e);
      expect(repo.getContact(a.id)!.notes, 'A edited');
      expect(repo.getContact(b.id)!.notes, 'B typed');
      expect(repo.getCompany(e.companyId)!.rapportNotes, '');
      final e2 = LeadEntry(companyId: e.companyId, companyName: 'Acme', addingToExisting: true)
        ..rapportEdits = {'': 'company level'};
      repo.commitEntry(e2);
      expect(repo.getCompany(e.companyId)!.rapportNotes, 'company level');
      expect(repo.getContact(a.id)!.notes, 'A edited');
    });

    test('removing a product only affects its own company; task link is nulled', () {
      final e = LeadEntry(companyName: 'A');
      final p = Product(id: newId(), companyId: e.companyId, createdAt: DateTime(2000), updatedAt: DateTime(2000));
      e.products = [p];
      repo.commitEntry(e);
      final other = LeadEntry(companyName: 'B');
      other.products = [
        Product(id: newId(), companyId: other.companyId, createdAt: DateTime(2000), updatedAt: DateTime(2000))
      ];
      repo.commitEntry(other);
      final t = FollowUpTask(
          id: newId(), companyId: e.companyId, productId: p.id, action: 'q', dueDate: '2026-10-10',
          createdAt: DateTime(2000), updatedAt: DateTime(2000));
      repo.upsertTask(t);
      // maliciously/by accident remove B's product id from A's form
      final e2 = LeadEntry(companyId: e.companyId, companyName: 'A', addingToExisting: true)
        ..removedProductIds = {other.products.first.id, p.id};
      repo.commitEntry(e2);
      expect(repo.productsFor(other.companyId), hasLength(1));
      expect(repo.productsFor(e.companyId), isEmpty);
      expect(repo.getTask(t.id)!.productId, isNull);
    });

    test('whitespace-only names are rejected; odd text is stored verbatim', () {
      expect(() => repo.commitEntry(LeadEntry(companyName: '   \n\t ')), throwsArgumentError);
      expect(repo.companyCount, 0);
      final long = 'x' * 200000;
      final e = LeadEntry(companyName: '  Café 🏢 العربية 株式会社  ')
        ..summary = long
        ..trivia = '👨‍👩‍👧‍👦 ' * 5000
        ..taskAction = 'Ring 📞\nsecond line';
      repo.commitEntry(e);
      final c = repo.getCompany(e.companyId)!;
      expect(c.name, 'Café 🏢 العربية 株式会社');
      expect(repo.meetingsFor(c.id).single.summary.length, 200000);
      expect(repo.queryLeads(const LeadQuery(text: '🏢'), env.today), hasLength(1));
      expect(repo.queryLeads(const LeadQuery(text: 'العربية'), env.today), hasLength(1));
    });

    test('draft json: emoji round-trip, truncated json ignored, missing meetingAt ignored', () {
      final e = LeadEntry(companyName: '🏢')..summary = '\u0000nul?';
      expect(LeadEntry.tryDecode(e.encode())!.companyName, '🏢');
      expect(LeadEntry.tryDecode(e.encode().substring(0, 40)), isNull);
      expect(LeadEntry.tryDecode('{"companyName":"x"}'), isNull);
      expect(LeadEntry.tryDecode('[]'), isNull);
      expect(LeadEntry.tryDecode('{"companyName":5,"meetingAt":1}'), isNull);
    });

    test('BUG #2: deleting a company must also delete its saved "Add Meeting" draft', () {
      final e = LeadEntry(companyName: 'Acme');
      repo.commitEntry(e);
      repo.saveDraft('co:${e.companyId}', LeadEntry(companyId: e.companyId, companyName: 'Acme', addingToExisting: true)
          .encode());
      repo.deleteCompany(e.companyId);
      expect(repo.loadDraft('co:${e.companyId}'), isNull,
          reason: 'orphan draft stays on dashboard ("Unfinished meeting: Acme") and resurrects the company if resumed');
    });
  });

  group('search / filter / sort', () {
    setUp(() {
      Contact c(String co, String n, String phone) => mk(co, n, phone: phone);
      for (final (name, phone) in [
        ('Alpha 100% Organic', '+971 50 123 4567'),
        ('Beta_Corp', '(0)50-999 1111'),
        ("O'Brien & Sons", '+44 20 7946 0958'),
        ('back\\slash Ltd', ''),
        ('Émile Zola SA', ''),
      ]) {
        final e = LeadEntry(companyName: name);
        if (phone.isNotEmpty) {
          final ct = c(e.companyId, 'P $name', phone);
          e.newContacts = [ct];
          e.metContactId = ct.id;
        }
        repo.commitEntry(e);
      }
    });

    test('wildcards and quotes are literal', () {
      List<String> s(String t) =>
          repo.queryLeads(LeadQuery(text: t), env.today).map((r) => r.company.name).toList();
      expect(s('100%'), ['Alpha 100% Organic']);
      expect(s('%'), ['Alpha 100% Organic']);
      expect(s('_'), ['Beta_Corp']);
      expect(s("O'Brien"), ["O'Brien & Sons"]);
      expect(s('\\'), ['back\\slash Ltd']);
      expect(s('"; DROP TABLE companies; --'), isEmpty);
      expect(repo.companyCount, 5);
      expect(s('   '), hasLength(5));
      expect(s('& sons'), ["O'Brien & Sons"]);
    });

    test('phone search ignores punctuation', () {
      List<String> s(String t) =>
          repo.queryLeads(LeadQuery(text: t), env.today).map((r) => r.company.name).toList();
      expect(s('971501234567'), ['Alpha 100% Organic']);
      expect(s('+971 50 123'), ['Alpha 100% Organic']);
      expect(s('7946 0958'), ["O'Brien & Sons"]);
    });

    test('BUG #3 (low): local-format number (leading 0) finds the +971 contact', () {
      final r = repo.queryLeads(const LeadQuery(text: '0501234567'), env.today);
      expect(r.map((x) => x.company.name), ['Alpha 100% Organic']);
    });

    test('LIKE is case-insensitive for non-ASCII too (accented names)', () {
      expect(repo.queryLeads(const LeadQuery(text: 'ÉMILE'), env.today), hasLength(1));
      expect(repo.queryLeads(const LeadQuery(text: 'émile'), env.today), hasLength(1));
      expect(repo.queryLeads(const LeadQuery(text: 'émile'), env.today).length, 1);
    }, skip: 'known limitation (documented): SQLite LIKE only folds ASCII; "émile" does not match "Émile"');
  });

  group('sort & follow-up filters', () {
    test('next follow-up uses the EARLIEST pending task; none/completed handled; nulls last; ties by name', () {
      LeadEntry mkc(String n, {String? due}) {
        final e = LeadEntry(companyName: n);
        if (due != null) {
          e
            ..taskAction = 'a'
            ..taskDue = due;
        }
        repo.commitEntry(e);
        return e;
      }

      final a = mkc('Bravo', due: '2026-10-03'); // today
      final b = mkc('alpha', due: '2026-10-03');
      mkc('Charlie', due: '2026-10-02'); // overdue
      mkc('Delta');
      final f = mkc('Echo', due: '2026-12-01');
      // Echo gets an extra overdue task, and Bravo's today task is completed
      repo.upsertTask(FollowUpTask(
          id: 'x', companyId: f.companyId, action: 'late', dueDate: '2026-09-01',
          createdAt: DateTime(2000), updatedAt: DateTime(2000)));
      final bt = repo.tasksFor(a.companyId).single;
      repo.completeTask(bt.id);
      final order = repo
          .queryLeads(const LeadQuery(sort: LeadSort.nextFollowUp), env.today)
          .map((r) => r.company.name)
          .toList();
      expect(order, ['Echo', 'Charlie', 'alpha', 'Bravo', 'Delta']);
      List<String> filt(FollowUpFilter x) => repo
          .queryLeads(LeadQuery(followUp: x, sort: LeadSort.companyName), env.today)
          .map((r) => r.company.name)
          .toList();
      expect(filt(FollowUpFilter.overdue), ['Charlie', 'Echo']);
      expect(filt(FollowUpFilter.today), ['alpha']);
      expect(filt(FollowUpFilter.none), ['Bravo', 'Delta']);
      expect(b.companyName, 'alpha');
    });

    test('nearest expiry ignores expired policies; expiring today counts', () {
      void co(String n, List<String?> exps) {
        final e = LeadEntry(companyName: n);
        e.products = [
          for (final x in exps)
            Product(id: newId(), companyId: e.companyId, expiryDate: x, createdAt: DateTime(2000), updatedAt: DateTime(2000))
        ];
        repo.commitEntry(e);
      }

      co('Past', ['2026-01-01']);
      co('Today', ['2026-10-03']);
      co('Later', ['2027-01-01', '2026-01-01']);
      co('Unknown', [null]);
      final o = repo
          .queryLeads(const LeadQuery(sort: LeadSort.nearestExpiry), env.today)
          .map((r) => r.company.name)
          .toList();
      expect(o, ['Today', 'Later', 'Past', 'Unknown']);
      expect(repo.renewals(from: '2026-10-03', to: '2026-10-03').single.companyName, 'Today');
    });
  });

  group('backup / restore / CSV', () {
    BackupService svc() => BackupService(repo);

    test('empty database round-trips', () {
      final j = svc().createBackup();
      final d = svc().parse(j);
      expect(d.companies, isEmpty);
      svc().restore(d);
      expect(repo.companyCount, 0);
    });

    test('BUG #4 (low): a backup saved by Windows Notepad (UTF-8 BOM) is rejected as "not valid JSON"', () {
      final j = svc().createBackup();
      expect(() => svc().parse('\u{FEFF}$j'), returnsNormally);
    });

    test('restore replaces data AND drafts, keeps settings not in backup', () {
      final e = LeadEntry(companyName: 'Old');
      repo.commitEntry(e);
      final j = svc().createBackup();
      repo.commitEntry(LeadEntry(companyName: 'New'));
      repo.saveDraft('new', LeadEntry(companyName: 'draft').encode());
      repo.setSetting('welcome_seen', '1');
      svc().restore(svc().parse(j));
      expect(repo.companyCount, 1);
      expect(repo.loadDraft('new'), isNull);
      expect(repo.getSetting('welcome_seen'), '1');
    });

    test('parse rejects tampered references', () {
      final e = LeadEntry(companyName: 'A');
      final ct = mk(e.companyId, 'Al');
      e.newContacts = [ct];
      e.metContactId = ct.id;
      e.summary = 's';
      e.taskAction = 'x';
      repo.commitEntry(e);
      final m = jsonDecode(svc().createBackup()) as Map<String, dynamic>;
      // task pointing at another company's contact
      final e2 = LeadEntry(companyName: 'B');
      repo.commitEntry(e2);
      final m2 = jsonDecode(svc().createBackup()) as Map<String, dynamic>;
      final tasks = (m2['tasks'] as List).cast<Map<String, dynamic>>();
      tasks.first['company_id'] = e2.companyId;
      expect(() => svc().parse(jsonEncode(m2)), throwsA(isA<BackupException>()));
      (m['companies'] as List).removeLast;
      m['counts'] = {'companies': 99};
      expect(() => svc().parse(jsonEncode(m)), throwsA(isA<BackupException>()));
      expect(() => svc().parse('null'), throwsA(isA<BackupException>()));
      expect(() => svc().parse('{"format":"bcr-leadbook-backup","version":"1"}'), throwsA(isA<BackupException>()));
      expect(() => svc().parse('{"format":"bcr-leadbook-backup","version":0,"companies":[]}'),
          throwsA(isA<BackupException>()));
    });

    test('restore of a structurally valid but semantically odd backup does not corrupt (bad dates ignored)', () {
      final e = LeadEntry(companyName: 'A')
        ..taskAction = 'x'
        ..taskDue = '2026-10-05';
      repo.commitEntry(e);
      final m = jsonDecode(svc().createBackup()) as Map<String, dynamic>;
      (m['tasks'] as List).first['due_date'] = 'not-a-date';
      (m['tasks'] as List).first['reminder_time'] = '25:99';
      final d = svc().parse(jsonEncode(m));
      svc().restore(d);
      expect(ReminderPlanner.plan(repo.pendingReminders(), env.clock), isEmpty);
      expect(repo.queryLeads(const LeadQuery(followUp: FollowUpFilter.overdue), env.today), isEmpty);
    });

    test('CSV: hostile values survive a parse round trip, formulas neutralised, columns aligned', () {
      final e = LeadEntry(companyName: '=HYPERLINK("x")')
        ..location = 'A, "B"\nC'
        ..trivia = '@SUM(1)'
        ..summary = '-cmd|calc'
        ..taskAction = '+1+1';
      final ct = mk(e.companyId, 'Zoë 🙂', phone: '+971 50 123 4567', notes: 'rapport');
      e.newContacts = [ct];
      e.metContactId = ct.id;
      repo.commitEntry(e);
      for (final withRapport in [false, true]) {
        final files = CsvExport(repo).build(includeRapport: withRapport);
        for (final entry in files.entries) {
          final rows = parseCsv(entry.value);
          expect(rows.length, (entry.key == 'products.csv' || entry.key == 'renewals.csv') ? 1 : 2, reason: entry.key);
          expect(rows.every((r) => r.length == rows.first.length), isTrue, reason: entry.key);
        }
        final ov = parseCsv(files['leads_overview.csv']!);
        final h = ov[0], r = ov[1];
        expect(r[h.indexOf('company_name')], "'=HYPERLINK(\"x\")");
        expect(r[h.indexOf('location')], 'A, "B"\nC');
        expect(r[h.indexOf('company_context')], "'@SUM(1)");
        expect(r[h.indexOf('last_meeting_summary')], "'-cmd|calc");
        expect(r[h.indexOf('next_action')], "'+1+1");
        expect(h.contains('company_rapport_notes'), withRapport);
        final cs = parseCsv(files['contacts.csv']!);
        expect(cs[1][cs[0].indexOf('phone')], '+971 50 123 4567');
        expect(cs[0].contains('rapport_notes'), withRapport);
        expect(files['contacts.csv']!.contains('rapport') && !withRapport && files['contacts.csv']!.contains('\nrapport'),
            isFalse);
      }
    });
  });

  group('notification sync on every write path', () {
    late FakeGateway gw;
    late AppController app;
    Future<void> settle() async {
      await app.reminders.sync();
    }

    setUp(() {
      gw = FakeGateway();
      app = AppController(repo: repo, reminders: ReminderService(repo, gw));
    });

    test('add, edit, move, snooze, complete, reopen, delete task/company, restore, demo', () async {
      Set<int> ids() => gw.scheduled.keys.toSet();
      String? tid;
      final cid = (() {
        final e = LeadEntry(companyName: 'Acme')
          ..taskAction = 'call'
          ..taskDue = '2026-10-05'
          ..reminderOn = true
          ..reminderTime = '09:00';
        final r = app.run(() => repo.commitEntry(e));
        tid = r.taskId;
        return e.companyId;
      })();
      await settle();
      expect(gw.scheduled, hasLength(1));
      expect(gw.scheduled.values.single.$1, DateTime(2026, 10, 5, 9, 0));
      expect(gw.scheduled.values.single.$3, 'You have a follow-up due.');

      app.run(() => repo.rescheduleTask(tid!, DateTime(2026, 10, 9)));
      await settle();
      expect(gw.scheduled.values.single.$1, DateTime(2026, 10, 9, 9, 0));

      app.run(() => repo.snoozeTaskUntilTomorrow(tid!, env.today));
      await settle();
      expect(gw.scheduled.values.single.$1, DateTime(2026, 10, 4, 9, 0));

      app.run(() => repo.completeTask(tid!));
      await settle();
      expect(gw.scheduled, isEmpty);
      app.run(() => repo.reopenTask(tid!));
      await settle();
      expect(gw.scheduled, hasLength(1));

      // edit: switch reminder off
      final t = repo.getTask(tid!)!;
      app.run(() => repo.upsertTask(FollowUpTask(
          id: t.id, seq: t.seq, companyId: t.companyId, action: t.action, dueDate: t.dueDate,
          createdAt: t.createdAt, updatedAt: t.updatedAt)));
      await settle();
      expect(gw.scheduled, isEmpty);

      app.run(() => repo.upsertTask(t));
      await settle();
      final before = ids();
      expect(before, hasLength(1));
      final backup = BackupService(repo).createBackup();

      app.run(() => repo.deleteCompany(cid));
      await settle();
      expect(gw.scheduled, isEmpty);

      app.run(() => BackupService(repo).restore(BackupService(repo).parse(backup)));
      await settle();
      expect(gw.scheduled, hasLength(1));

      app.run(() => DemoData.load(repo));
      await settle();
      final withDemo = gw.scheduled.length;
      app.run(() => DemoData.remove(repo));
      await settle();
      expect(gw.scheduled.length, lessThanOrEqualTo(withDemo));
      expect(gw.scheduled, hasLength(1));
    });

    test('company-name-in-notification setting re-syncs text immediately', () async {
      final e = LeadEntry(companyName: 'Secret Co')
        ..taskAction = 'x'
        ..taskDue = '2026-10-05';
      app.run(() => repo.commitEntry(e));
      await settle();
      expect(gw.scheduled.values.single.$3.contains('Secret'), isFalse);
      app.setShowCompanyInNotification(true);
      await settle();
      expect(gw.scheduled.values.single.$3, contains('Secret Co'));
    });
  });

  group('delete cascade', () {
    test('contact/product/meeting delete only clears links; company delete cascades everything', () {
      final e = LeadEntry(companyName: 'A')..summary = 's'..taskAction = 'x';
      final ct = mk(e.companyId, 'C');
      e.newContacts = [ct];
      e.metContactId = ct.id;
      e.products = [Product(id: newId(), companyId: e.companyId, createdAt: DateTime(2000), updatedAt: DateTime(2000))];
      final r = repo.commitEntry(e);
      repo.deleteContact(ct.id);
      expect(repo.meetingsFor(e.companyId).single.contactId, isNull);
      expect(repo.getTask(r.taskId!)!.contactId, isNull);
      repo.deleteMeeting(r.meetingId!);
      expect(repo.getTask(r.taskId!)!.meetingId, isNull);
      repo.deleteCompany(e.companyId);
      for (final t in ['contacts', 'products', 'meetings', 'tasks']) {
        expect(repo.db.select('SELECT COUNT(*) c FROM $t').first['c'], 0, reason: t);
      }
    });
  });
}
