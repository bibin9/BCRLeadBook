import 'dart:convert';
import 'dart:io';

import 'package:bcr_leadbook/data/backup_service.dart';
import 'package:bcr_leadbook/data/csv_export.dart';
import 'package:bcr_leadbook/data/database.dart';
import 'package:bcr_leadbook/data/demo_data.dart';
import 'package:bcr_leadbook/data/lead_entry.dart';
import 'package:bcr_leadbook/data/models.dart';
import 'package:bcr_leadbook/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'helpers.dart';

/// Builds a realistic data set and returns the company id.
String seed(Repository repo) {
  final cid = newId();
  Contact c(String n, {bool dm = false, String notes = ''}) => Contact(
      id: newId(),
      companyId: cid,
      name: n,
      phone: '+971 50 111 2222',
      email: '$n@example.com'.replaceAll(' ', '').toLowerCase(),
      isDecisionMaker: dm,
      notes: notes,
      createdAt: DateTime(2000),
      updatedAt: DateTime(2000));
  final sam = c('Sam', notes: 'Likes "tea", no sugar\nSecond line, comma');
  final dana = c('Dana', dm: true);
  Product p(ProductLine l, String? e, {String label = ''}) => Product(
      id: newId(),
      companyId: cid,
      line: l,
      expiryDate: e,
      label: label,
      insurer: 'Insurer, Inc',
      createdAt: DateTime(2000),
      updatedAt: DateTime(2000));
  final med = p(ProductLine.medical, '2027-03-15');
  repo.commitEntry(LeadEntry(
    companyId: cid,
    companyName: 'ABC Trading',
    location: 'Dubai',
    trivia: 'Trivia, with "quotes"',
    quality: LeadQuality.hot,
    targetMonth: '2026-11',
    newContacts: [sam, dana],
    metContactId: sam.id,
    nextSameAsMet: false,
    nextContactId: dana.id,
    products: [med, p(ProductLine.motor, '2027-07-20'), p(ProductLine.marine, null)],
    summary: 'First meeting',
    taskAction: 'Send quote',
    taskDue: '2026-10-10',
    reminderOn: true,
  ));
  repo.commitEntry(LeadEntry(
      companyId: cid,
      companyName: 'ABC Trading',
      location: 'Dubai',
      trivia: 'Trivia, with "quotes"',
      quality: LeadQuality.hot,
      targetMonth: '2026-11',
      addingToExisting: true,
      metContactId: dana.id,
      summary: 'Second meeting'));
  // a task linked to a product
  repo.upsertTask(FollowUpTask(
      id: newId(),
      companyId: cid,
      productId: med.id,
      contactId: dana.id,
      action: 'Renewal chat',
      dueDate: '2027-02-01',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026)));
  repo.commitEntry(LeadEntry(companyName: 'Second Co', quality: LeadQuality.cold));
  return cid;
}

Map<String, Object?> snapshot(Repository r) => {
      for (final t in ['companies', 'contacts', 'products', 'meetings'])
        t: r.db.select('SELECT * FROM $t ORDER BY id').map((x) => Map.of(x)).toList(),
      'tasks': r.db
          .select('SELECT id, company_id, contact_id, product_id, meeting_id, action, due_date, reminder_time, status, completed_at, created_at, updated_at FROM tasks ORDER BY id')
          .map((x) => Map.of(x))
          .toList(),
    };

void main() {
  group('6. persistence across app restarts (file database)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('bcr_leadbook_'));
    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('data written, database closed, reopened: everything is still there', () {
      final path = '${dir.path}/bcr.db';
      var db = openFileDatabase(path);
      var repo = Repository(db);
      final cid = seed(repo);
      repo.saveDraft('new', LeadEntry(companyName: 'Unfinished').encode());
      repo.setSetting('reminder_default_time', '08:30');
      final before = snapshot(repo);
      db.close(); // simulates the app being closed

      db = openFileDatabase(path);
      repo = Repository(db);
      expect(snapshot(repo), before);
      expect(repo.bundle(cid)!.meetings.length, 2);
      expect(repo.bundle(cid)!.products.length, 3);
      expect(repo.loadDraft('new'), isNotNull);
      expect(repo.getSetting('reminder_default_time'), '08:30');
      expect(db.select('PRAGMA user_version').first.values.first, currentSchemaVersion);
      db.close();
    });
  });

  group('migrations', () {
    test('a brand-new database is migrated to the current version', () {
      final db = sqlite3.openInMemory();
      expect(db.select('PRAGMA user_version').first.values.first, 0);
      migrate(db);
      expect(db.select('PRAGMA user_version').first.values.first, currentSchemaVersion);
      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'])
          .toSet();
      expect(tables, containsAll(['companies', 'contacts', 'products', 'meetings', 'tasks', 'drafts', 'settings']));
      migrate(db); // idempotent
      db.close();
    });

    test('a database from a newer app version is refused, not damaged', () {
      final db = sqlite3.openInMemory();
      db.execute('CREATE TABLE keep(x)');
      db.execute('PRAGMA user_version = ${currentSchemaVersion + 5}');
      expect(() => migrate(db), throwsA(isA<DatabaseTooNewException>()));
      expect(db.select("SELECT name FROM sqlite_master WHERE name='keep'"), isNotEmpty);
      db.close();
    });

    test('a failing migration rolls back and leaves the version unchanged', () {
      final db = sqlite3.openInMemory();
      migrations.add((d) {
        d.execute('CREATE TABLE half_done(x)');
        d.execute('THIS IS NOT SQL');
      });
      try {
        expect(() => migrate(db), throwsA(anything));
        expect(db.select('PRAGMA user_version').first.values.first, currentSchemaVersion - 1);
        expect(db.select("SELECT name FROM sqlite_master WHERE name='half_done'"), isEmpty);
      } finally {
        migrations.removeLast();
        db.close();
      }
    });
  });

  group('12. backup & restore', () {
    late TestEnv a;
    late String cid;
    setUp(() {
      a = TestEnv();
      cid = seed(a.repo);
      a.repo.setSetting('reminder_default_time', '08:45');
      a.repo.setSetting('welcome_seen', '1');
    });

    test('backup is versioned and contains every record type', () {
      final json = jsonDecode(BackupService(a.repo).createBackup()) as Map;
      expect(json['format'], 'bcr-leadbook-backup');
      expect(json['version'], backupVersion);
      expect(json['counts'], {'companies': 2, 'contacts': 2, 'products': 3, 'meetings': 2, 'tasks': 2});
      expect((json['settings'] as Map).keys, ['reminder_default_time'],
          reason: 'machine-specific flags are not exported');
    });

    test('restore into a fresh install recreates identical data and relationships', () {
      final text = BackupService(a.repo).createBackup();
      final b = TestEnv();
      final svc = BackupService(b.repo);
      final data = svc.parse(text);
      expect(data.summary, '2 companies, 2 contacts, 3 products, 2 meetings, 2 follow-ups');
      svc.restore(data);
      expect(snapshot(b.repo), snapshot(a.repo));
      final bundle = b.repo.bundle(cid)!;
      expect(bundle.lastMeeting!.contactId, bundle.contacts.firstWhere((c) => c.name == 'Dana').id);
      final linked = bundle.tasks.firstWhere((t) => t.action == 'Renewal chat');
      expect(bundle.products.any((p) => p.id == linked.productId), isTrue);
      expect(bundle.contactById(linked.contactId)!.name, 'Dana');
      expect(bundle.nextCallContact!.name, 'Dana');
      expect(b.repo.getSetting('reminder_default_time'), '08:45');
      expect(b.repo.getSetting('welcome_seen'), isNull);
      // Original timestamps survive the round trip.
      expect(b.repo.getCompany(cid)!.createdAt, a.repo.getCompany(cid)!.createdAt);
    });

    test('restore REPLACES existing data and drops stale drafts', () {
      final text = BackupService(a.repo).createBackup();
      final b = TestEnv();
      b.repo.commitEntry(LeadEntry(companyName: 'Will be replaced'));
      b.repo.saveDraft('new', 'x');
      final svc = BackupService(b.repo);
      svc.restore(svc.parse(text));
      expect(b.repo.queryLeads(const LeadQuery(text: 'replaced'), b.today), isEmpty);
      expect(b.repo.companyCount, 2);
      expect(b.repo.listDrafts(), isEmpty);
    });

    test('new tasks get fresh notification ids after restore', () {
      final text = BackupService(a.repo).createBackup();
      final b = TestEnv();
      final svc = BackupService(b.repo);
      svc.restore(svc.parse(text));
      final seqs = b.repo.pendingReminders().map((r) => r.seq).toList();
      expect(seqs.toSet().length, seqs.length);
    });

    group('validation (nothing is touched when the file is bad)', () {
      late BackupService svc;
      late Map<String, dynamic> good;
      setUp(() {
        svc = BackupService(a.repo);
        good = jsonDecode(svc.createBackup()) as Map<String, dynamic>;
      });
      void rejects(Object? input, String fragment) {
        final text = input is String ? input : jsonEncode(input);
        expect(() => svc.parse(text),
            throwsA(isA<BackupException>().having((e) => e.message, 'message', contains(fragment))));
      }

      test('not JSON / wrong format / no version', () {
        rejects('hello world', 'not valid JSON');
        rejects('[1,2]', 'not a BCR LeadBook backup');
        rejects({'format': 'something-else'}, 'not a BCR LeadBook backup');
        rejects({'format': backupFormat}, 'version');
      });
      test('newer backup version asks to update the app', () {
        rejects({...good, 'version': backupVersion + 1}, 'newer version');
      });
      test('missing section, damaged record, count mismatch', () {
        rejects({...good}..remove('contacts'), 'missing "contacts"');
        rejects({...good, 'companies': [{'id': 'x'}]}, 'damaged');
        rejects({...good, 'counts': {'companies': 99}}, 'incomplete');
      });
      test('orphaned records are rejected', () {
        final c = (good['contacts'] as List).cast<Map>().map((e) => {...e, 'company_id': 'nope'}).toList();
        rejects({...good, 'contacts': c}, 'contact refers to a company');
        final m = (good['meetings'] as List).cast<Map>().map((e) => {...e, 'contact_id': 'ghost'}).toList();
        rejects({...good, 'meetings': m}, 'meeting refers to a contact');
        final t = (good['tasks'] as List).cast<Map>().map((e) => {...e, 'product_id': 'ghost'}).toList();
        rejects({...good, 'tasks': t}, 'product');
      });
      test('duplicate ids are rejected', () {
        final cs = (good['companies'] as List);
        rejects({...good, 'companies': [cs.first, cs.first], 'counts': null}, 'Duplicate');
      });
      test('a restore that fails midway keeps the old data', () {
        final before = snapshot(a.repo);
        final data = svc.parse(jsonEncode(good));
        final broken = BackupData(
            createdAt: null,
            companies: data.companies,
            contacts: data.contacts,
            // product points to a company id that is not restored -> FK error
            products: [
              Product(
                  id: 'zzz',
                  companyId: 'missing',
                  createdAt: DateTime(2000),
                  updatedAt: DateTime(2000))
            ],
            meetings: const [],
            tasks: const [],
            settings: const {});
        expect(() => svc.restore(broken), throwsA(anything));
        expect(snapshot(a.repo), before);
      });
    });
  });

  group('CSV export', () {
    late TestEnv env;
    late CsvExport csv;
    setUp(() {
      env = TestEnv();
      seed(env.repo);
      csv = CsvExport(env.repo);
    });

    List<List<String>> parse(String text) {
      // minimal RFC4180 parser for assertions
      final rows = <List<String>>[];
      var row = <String>[];
      final cell = StringBuffer();
      var inQ = false;
      final s = text.startsWith('\u{FEFF}') ? text.substring(1) : text;
      for (var i = 0; i < s.length; i++) {
        final ch = s[i];
        if (inQ) {
          if (ch == '"') {
            if (i + 1 < s.length && s[i + 1] == '"') {
              cell.write('"');
              i++;
            } else {
              inQ = false;
            }
          } else {
            cell.write(ch);
          }
        } else if (ch == '"') {
          inQ = true;
        } else if (ch == ',') {
          row.add(cell.toString());
          cell.clear();
        } else if (ch == '\r') {
        } else if (ch == '\n') {
          row.add(cell.toString());
          cell.clear();
          rows.add(row);
          row = [];
        } else {
          cell.write(ch);
        }
      }
      return rows;
    }

    test('six files, every product and contact present (nothing silently lost)', () {
      final files = csv.build(includeRapport: true);
      expect(files.keys, ['leads_overview.csv', 'renewals.csv', 'contacts.csv', 'products.csv', 'meetings.csv', 'follow_ups.csv']);
      expect(parse(files['products.csv']!).length, 1 + 3);
      expect(parse(files['contacts.csv']!).length, 1 + 2);
      expect(parse(files['meetings.csv']!).length, 1 + 2);
      expect(parse(files['follow_ups.csv']!).length, 1 + 2);
      final ov = parse(files['leads_overview.csv']!);
      expect(ov.length, 1 + 2);
      final h = ov.first;
      final abc = ov.firstWhere((r) => r[h.indexOf('company_name')] == 'ABC Trading');
      expect(abc[h.indexOf('product_count')], '3');
      expect(abc[h.indexOf('products')], contains('Medical, expires 2027-03-15'));
      expect(abc[h.indexOf('products')], contains('Marine, expires unknown'));
      expect(abc[h.indexOf('contacts')], contains('Sam'));
      expect(abc[h.indexOf('contacts')], contains('Dana'));
      expect(abc[h.indexOf('lead_quality')], 'Hot');
      expect(abc[h.indexOf('company_context')], 'Trivia, with "quotes"');
    });

    test('rapport notes can be excluded and are then absent everywhere', () {
      final without = csv.build(includeRapport: false);
      for (final e in without.entries) {
        expect(e.value.contains('tea'), isFalse, reason: '${e.key} leaked rapport notes');
        expect(e.value.contains('rapport_notes'), isFalse, reason: e.key);
      }
      final withIt = csv.build(includeRapport: true);
      expect(withIt['contacts.csv'], contains('Likes ""tea"", no sugar'));
      expect(withIt['contacts.csv'], contains('rapport_notes'));
    });

    test('quoting, UTF-8 BOM, CRLF and formula protection', () {
      expect(CsvExport.cell('a,b'), '"a,b"');
      expect(CsvExport.cell('say "hi"'), '"say ""hi"""');
      expect(CsvExport.cell('=SUM(A1)'), "'=SUM(A1)");
      expect(CsvExport.cell('@x'), "'@x");
      expect(CsvExport.cell('-cmd|x'), "'-cmd|x");
      expect(CsvExport.cell('+971 50 111 2222'), '+971 50 111 2222');
      expect(CsvExport.cell(null), '');
      final out = csv.build(includeRapport: false)['contacts.csv']!;
      expect(out.startsWith('\u{FEFF}'), isTrue);
      expect(out.contains('\r\n'), isTrue);
    });

    test('empty database still exports valid header-only files', () {
      final empty = CsvExport(TestEnv().repo).build(includeRapport: false);
      for (final f in empty.values) {
        expect(parse(f).length, 1);
      }
    });
  });

  group('demo data is explicit, optional and removable', () {
    test('fresh database has no records', () {
      expect(TestEnv().repo.companyCount, 0);
    });
    test('load adds demo records; remove deletes only them', () {
      final env = TestEnv();
      env.repo.commitEntry(LeadEntry(companyName: 'My real client'));
      DemoData.load(env.repo);
      expect(DemoData.count(env.repo), 5);
      expect(env.repo.companyCount, 6);
      DemoData.remove(env.repo);
      expect(DemoData.count(env.repo), 0);
      expect(env.repo.companyCount, 1);
      expect(env.repo.db.select('SELECT COUNT(*) c FROM products').first['c'], 0);
    });
  });
}
