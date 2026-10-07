import 'package:bcr_leadbook/core/dates.dart';
import 'package:bcr_leadbook/data/lead_entry.dart';
import 'package:bcr_leadbook/data/models.dart';
import 'package:bcr_leadbook/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Contact contact(String companyId, String name,
        {String phone = '', bool dm = false, String notes = '', String title = ''}) =>
    Contact(
      id: newId(),
      companyId: companyId,
      name: name,
      phone: phone,
      isDecisionMaker: dm,
      notes: notes,
      title: title,
      createdAt: DateTime(2000),
      updatedAt: DateTime(2000),
    );

Product product(String companyId, ProductLine line, String? expiry, {String label = ''}) =>
    Product(
      id: newId(),
      companyId: companyId,
      line: line,
      expiryDate: expiry,
      label: label,
      createdAt: DateTime(2000),
      updatedAt: DateTime(2000),
    );

void main() {
  late TestEnv env;
  late Repository repo;
  setUp(() {
    env = TestEnv();
    repo = env.repo;
  });

  test('1. a lead can be saved with only a company name', () {
    final r = repo.commitEntry(LeadEntry(companyName: 'Solo Co'));
    final b = repo.bundle(r.companyId)!;
    expect(b.company.name, 'Solo Co');
    expect(b.company.quality, isNull, reason: 'quality stays unselected');
    expect(b.company.targetMonth, isNull);
    expect(b.meetings, isEmpty, reason: 'no empty meeting is invented');
    expect(b.tasks, isEmpty);
    expect(b.contacts, isEmpty);
    expect(r.createdCompany, isTrue);
  });

  test('an empty company name is the only thing rejected', () {
    expect(() => repo.commitEntry(LeadEntry(companyName: '   ')), throwsArgumentError);
    expect(repo.companyCount, 0);
  });

  test('2-4. realistic entry: two products, person met != next-call contact', () {
    final cid = newId();
    final met = contact(cid, 'Sam Accountant', phone: '+971501110001');
    final dm = contact(cid, 'Dana Director', phone: '+971501110002', dm: true);
    final e = LeadEntry(
      companyId: cid,
      companyName: 'ABC Trading',
      location: 'Dubai',
      trivia: 'Opening a new warehouse',
      quality: LeadQuality.hot,
      targetMonth: '2026-11',
      meetingAt: DateTime(2026, 10, 1, 14, 0),
      metContactId: met.id,
      nextSameAsMet: false,
      nextContactId: dm.id,
      newContacts: [met, dm],
      rapportEdits: {met.id: 'Loves cricket, tea no sugar'},
      products: [
        product(cid, ProductLine.medical, '2027-03-15'),
        product(cid, ProductLine.motor, '2027-07-20'),
      ],
      summary: 'Wants 3 quotes. Worried about premium increase.',
      taskAction: 'Send quotes',
      taskDue: '2026-10-10',
      reminderOn: true,
      reminderTime: '09:00',
    );
    final r = repo.commitEntry(e);
    final b = repo.bundle(r.companyId)!;

    expect(b.contacts.map((c) => c.name), containsAll(['Sam Accountant', 'Dana Director']));
    expect(b.products.length, 2);
    expect(b.productsByExpiry.map((p) => p.expiryDate), ['2027-03-15', '2027-07-20']);
    expect(b.meetings.length, 1);
    final m = b.lastMeeting!;
    expect(m.contactId, met.id);
    expect(m.nextContactId, dm.id);
    expect(m.contactId, isNot(m.nextContactId));
    expect(b.nextCallContact!.name, 'Dana Director');
    expect(b.contactById(met.id)!.notes, 'Loves cricket, tea no sugar');
    expect(b.nextTask!.action, 'Send quotes');
    expect(b.nextTask!.dueDate, '2026-10-10');
    expect(b.nextTask!.reminderTime, '09:00');
    expect(b.nextTask!.contactId, dm.id);
    expect(b.company.targetMonth, '2026-11');
  });

  test('"same person" is the default for next-call contact', () {
    final cid = newId();
    final c = contact(cid, 'Pat');
    final r = repo.commitEntry(LeadEntry(
      companyId: cid,
      companyName: 'X',
      newContacts: [c],
      metContactId: c.id,
      summary: 'hi',
    ));
    final m = repo.bundle(r.companyId)!.lastMeeting!;
    expect(m.contactId, c.id);
    expect(m.nextContactId, c.id);
  });

  test('5. adding another meeting keeps earlier notes (history, not overwrite)', () {
    final first = repo.commitEntry(LeadEntry(
      companyName: 'History Co',
      summary: 'First meeting notes',
      meetingAt: DateTime(2026, 9, 1, 10),
    ));
    env.advance(const Duration(days: 30));
    repo.commitEntry(LeadEntry(
      companyId: first.companyId,
      companyName: 'History Co',
      addingToExisting: true,
      summary: 'Second meeting notes',
      meetingAt: DateTime(2026, 10, 1, 10),
    ));
    // A third, empty-summary "Add Meeting" still logs a history row.
    repo.commitEntry(LeadEntry(
      companyId: first.companyId,
      companyName: 'History Co',
      addingToExisting: true,
      meetingAt: DateTime(2026, 10, 2, 10),
    ));
    final b = repo.bundle(first.companyId)!;
    expect(b.meetings.length, 3);
    expect(b.meetings.map((m) => m.summary), ['', 'Second meeting notes', 'First meeting notes']);
  });

  test('created date never changes; updated date does', () {
    final r = repo.commitEntry(LeadEntry(companyName: 'Stamp Co'));
    final before = repo.getCompany(r.companyId)!;
    env.advance(const Duration(days: 2));
    repo.commitEntry(LeadEntry(
      companyId: r.companyId,
      companyName: 'Stamp Co Renamed',
      addingToExisting: true,
      quality: LeadQuality.warm,
    ));
    final after = repo.getCompany(r.companyId)!;
    expect(after.name, 'Stamp Co Renamed');
    expect(after.createdAt, before.createdAt);
    expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
  });

  test('editing a child bumps the company\'s last-updated stamp', () {
    final r = repo.commitEntry(LeadEntry(companyName: 'Parent'));
    final t0 = repo.getCompany(r.companyId)!.updatedAt;
    env.advance(const Duration(hours: 5));
    repo.upsertContact(contact(r.companyId, 'New Person'));
    expect(repo.getCompany(r.companyId)!.updatedAt.isAfter(t0), isTrue);
  });

  test('existing contact rapport notes persist across meetings and can be edited', () {
    final cid = newId();
    final c = contact(cid, 'Rapport Person', notes: 'Likes golf');
    repo.commitEntry(LeadEntry(
        companyId: cid, companyName: 'R', newContacts: [c], metContactId: c.id, summary: 'm1'));
    // Meeting 2: no edit -> notes untouched
    repo.commitEntry(LeadEntry(
        companyId: cid, companyName: 'R', addingToExisting: true, metContactId: c.id, summary: 'm2'));
    expect(repo.getContact(c.id)!.notes, 'Likes golf');
    // Meeting 3: edited
    repo.commitEntry(LeadEntry(
        companyId: cid,
        companyName: 'R',
        addingToExisting: true,
        metContactId: c.id,
        rapportEdits: {c.id: 'Likes golf. Back from Maldives.'},
        summary: 'm3'));
    expect(repo.getContact(c.id)!.notes, 'Likes golf. Back from Maldives.');
    expect(repo.meetingsFor(cid).length, 3);
  });

  test('products: unknown expiry stays null; removal works; label separates policies', () {
    final cid = newId();
    final p1 = product(cid, ProductLine.medical, null, label: 'Staff');
    final p2 = product(cid, ProductLine.medical, '2027-03-15', label: 'Management');
    repo.commitEntry(LeadEntry(companyId: cid, companyName: 'P', products: [p1, p2]));
    var ps = repo.productsFor(cid);
    expect(ps.length, 2);
    expect(ps.firstWhere((p) => p.label == 'Staff').expiryDate, isNull);
    expect(ps.firstWhere((p) => p.label == 'Staff').displayName, 'Medical (Staff)');
    repo.commitEntry(LeadEntry(
        companyId: cid,
        companyName: 'P',
        addingToExisting: true,
        products: [p1],
        removedProductIds: {p2.id}));
    ps = repo.productsFor(cid);
    expect(ps.map((p) => p.id), [p1.id]);
  });

  test('Other product line uses custom text', () {
    final cid = newId();
    final p = Product(
        id: newId(),
        companyId: cid,
        line: ProductLine.other,
        customLine: 'Cyber',
        createdAt: DateTime(2000),
        updatedAt: DateTime(2000));
    repo.commitEntry(LeadEntry(companyId: cid, companyName: 'C', products: [p]));
    expect(repo.productsFor(cid).single.lineLabel, 'Cyber');
  });

  group('tasks', () {
    late String cid;
    late String tid;
    setUp(() {
      final r = repo.commitEntry(LeadEntry(
          companyName: 'Task Co',
          targetMonth: '2026-11',
          taskAction: 'Call back',
          taskDue: '2026-10-05'));
      cid = r.companyId;
      tid = r.taskId!;
    });

    test('9. create, reschedule, complete; target month untouched', () {
      expect(repo.tasks(pending: true).single.task.dueDate, '2026-10-05');
      repo.rescheduleTask(tid, DateTime(2026, 12, 31), reminderTime: '08:15');
      var t = repo.getTask(tid)!;
      expect(t.dueDate, '2026-12-31');
      expect(t.reminderTime, '08:15');
      expect(repo.getCompany(cid)!.targetMonth, '2026-11',
          reason: 'rescheduling must not overwrite the target month');
      repo.completeTask(tid);
      t = repo.getTask(tid)!;
      expect(t.status, TaskStatus.completed);
      expect(t.completedAt, isNotNull);
      expect(repo.tasks(pending: true), isEmpty);
      expect(repo.tasks(pending: false).length, 1);
      repo.reopenTask(tid);
      expect(repo.getTask(tid)!.isPending, isTrue);
      expect(repo.getTask(tid)!.completedAt, isNull);
    });

    test('changing target month does not move task dates', () {
      final c = repo.getCompany(cid)!;
      repo.updateCompany(c.copyWith(targetMonth: '2027-02'));
      expect(repo.getTask(tid)!.dueDate, '2026-10-05');
    });

    test('snooze until tomorrow crosses month and year ends', () {
      repo.snoozeTaskUntilTomorrow(tid, DateTime(2026, 12, 31, 23, 30));
      expect(repo.getTask(tid)!.dueDate, '2027-01-01');
      repo.snoozeTaskUntilTomorrow(tid, DateTime(2026, 2, 28));
      expect(repo.getTask(tid)!.dueDate, '2026-03-01');
    });

    test('multiple tasks per company; next task is the earliest pending', () {
      repo.upsertTask(FollowUpTask(
          id: newId(),
          companyId: cid,
          action: 'Earlier',
          dueDate: '2026-10-04',
          createdAt: env.clock,
          updatedAt: env.clock));
      final b = repo.bundle(cid)!;
      expect(b.tasks.length, 2);
      expect(b.nextTask!.action, 'Earlier');
    });

    test('task can link to a contact and a product', () {
      final c = contact(cid, 'Linked');
      final p = product(cid, ProductLine.marine, '2027-01-01');
      repo.upsertContact(c);
      repo.upsertProduct(p);
      repo.upsertTask(repo.getTask(tid)!.copyWith(contactId: c.id, productId: p.id));
      final t = repo.getTask(tid)!;
      expect(t.contactId, c.id);
      expect(t.productId, p.id);
      repo.deleteProduct(p.id);
      expect(repo.getTask(tid)!.productId, isNull, reason: 'link cleared, task kept');
    });

    test('deleting a task removes it', () {
      repo.deleteTask(tid);
      expect(repo.getTask(tid), isNull);
    });

    test('overdue / today / upcoming buckets for the lists', () {
      final today = DateTime(2026, 10, 5);
      for (final (a, d) in [('o', '2026-10-01'), ('t', '2026-10-05'), ('u', '2026-11-01')]) {
        repo.upsertTask(FollowUpTask(
            id: newId(),
            companyId: cid,
            action: a,
            dueDate: d,
            createdAt: env.clock,
            updatedAt: env.clock));
      }
      final pending = repo.tasks(pending: true);
      Set<String> names(FollowUpBucket b) => pending
          .where((t) => followUpBucket(t.task.dueDate, today) == b)
          .map((t) => t.task.action)
          .toSet();
      expect(names(FollowUpBucket.overdue), {'o'});
      expect(names(FollowUpBucket.today), {'Call back', 't'});
      expect(names(FollowUpBucket.upcoming), {'u'});
    });
  });

  test('deleting a company removes all its records (cascade)', () {
    final cid = newId();
    final c = contact(cid, 'Gone');
    repo.commitEntry(LeadEntry(
        companyId: cid,
        companyName: 'Gone Co',
        newContacts: [c],
        metContactId: c.id,
        products: [product(cid, ProductLine.motor, '2027-01-01')],
        summary: 'x',
        taskAction: 't',
        taskDue: '2026-10-10'));
    repo.deleteCompany(cid);
    for (final t in ['companies', 'contacts', 'products', 'meetings', 'tasks']) {
      expect(repo.db.select('SELECT COUNT(*) c FROM $t').first['c'], 0, reason: t);
    }
  });

  test('deleting a contact keeps meetings but clears the link', () {
    final cid = newId();
    final c = contact(cid, 'Leaver');
    repo.commitEntry(LeadEntry(
        companyId: cid, companyName: 'K', newContacts: [c], metContactId: c.id, summary: 'kept'));
    repo.deleteContact(c.id);
    final m = repo.meetingsFor(cid).single;
    expect(m.summary, 'kept');
    expect(m.contactId, isNull);
  });

  test('a failed commit leaves no partial data (rolls back)', () {
    // A failure while writing the meeting (after the company row was
    // written) must undo everything.
    repo.db.execute("CREATE TRIGGER boom BEFORE INSERT ON meetings BEGIN SELECT RAISE(ABORT, 'boom'); END");
    expect(
      () => repo.commitEntry(LeadEntry(companyName: 'Atomic', summary: 'x')),
      throwsA(anything),
    );
    repo.db.execute('DROP TRIGGER boom');
    expect(repo.db.select("SELECT * FROM companies WHERE name='Atomic'"), isEmpty);
    expect(repo.companyCount, 0);
    // and the repository is still usable afterwards
    repo.commitEntry(LeadEntry(companyName: 'After'));
    expect(repo.companyCount, 1);
  });

  group('drafts', () {
    test('7. an unfinished entry survives and can be resumed exactly', () {
      final cid = newId();
      final c = contact(cid, 'Draft Person', phone: '+971500000000');
      final e = LeadEntry(
        companyId: cid,
        companyName: 'Draft Co',
        quality: LeadQuality.future,
        targetMonth: '2027-01',
        newContacts: [c],
        metContactId: c.id,
        rapportEdits: {c.id: 'coffee: flat white'},
        products: [product(cid, ProductLine.property, null)],
        summary: 'half-typed',
        taskAction: 'Ring',
        taskDue: '2027-01-05',
      );
      repo.saveDraft('new', e.encode());
      expect(repo.listDrafts().single.key, 'new');
      final back = LeadEntry.tryDecode(repo.loadDraft('new')!)!;
      expect(back.companyName, 'Draft Co');
      expect(back.quality, LeadQuality.future);
      expect(back.newContacts.single.name, 'Draft Person');
      expect(back.rapportEdits[c.id], 'coffee: flat white');
      expect(back.products.single.line, ProductLine.property);
      expect(back.products.single.expiryDate, isNull);
      expect(back.summary, 'half-typed');
      expect(back.taskDue, '2027-01-05');
      expect(back.hasContent, isTrue);
    });

    test('draft is removed on commit; corrupt drafts are ignored', () {
      repo.saveDraft('new', LeadEntry(companyName: 'D').encode());
      repo.commitEntry(LeadEntry(companyName: 'D'), draftKey: 'new');
      expect(repo.loadDraft('new'), isNull);
      expect(LeadEntry.tryDecode('{not json'), isNull);
      expect(LeadEntry(companyName: '').hasContent, isFalse);
    });

    test('saving a draft twice overwrites the same key', () {
      repo.saveDraft('k', 'a');
      repo.saveDraft('k', 'b');
      expect(repo.listDrafts().length, 1);
      expect(repo.loadDraft('k'), 'b');
    });
  });

  group('8. search and filters', () {
    late String abc, bay, cedar, dune;
    setUp(() {
      abc = newId();
      bay = newId();
      cedar = newId();
      dune = newId();
      final sam = contact(abc, 'Sam Accountant', phone: '+971 50 123 4567', notes: 'plays cricket');
      repo.commitEntry(LeadEntry(
          companyId: abc,
          companyName: 'ABC Trading',
          location: 'Dubai',
          quality: LeadQuality.hot,
          targetMonth: '2026-11',
          trivia: 'new Sharjah warehouse',
          newContacts: [sam],
          metContactId: sam.id,
          summary: 'Discussed premium increase and objections',
          products: [
            product(abc, ProductLine.medical, '2027-03-15'),
            product(abc, ProductLine.motor, '2027-07-20'),
          ],
          taskAction: 'Quote',
          taskDue: '2026-10-03'));
      repo.commitEntry(LeadEntry(
          companyId: bay,
          companyName: 'Bay Marine',
          quality: LeadQuality.warm,
          targetMonth: '2026-12',
          products: [product(bay, ProductLine.marine, '2026-11-30')],
          taskAction: 'Call',
          taskDue: '2026-09-30'));
      env.advance(const Duration(days: 1));
      repo.commitEntry(LeadEntry(
          companyId: cedar,
          companyName: 'Cedar Logistics',
          products: [product(cedar, ProductLine.liability, '2026-09-01')],
          taskAction: 'Later',
          taskDue: '2027-02-01'));
      env.advance(const Duration(days: 1));
      repo.commitEntry(LeadEntry(companyId: dune, companyName: 'dune foods 100%_off'));
    });

    List<String> names(LeadQuery q) =>
        repo.queryLeads(q, env.today).map((r) => r.company.name).toList();

    test('by company name (case-insensitive) and location', () {
      expect(names(const LeadQuery(text: 'abc')), ['ABC Trading']);
      expect(names(const LeadQuery(text: 'DUBAI')), ['ABC Trading']);
    });
    test('by contact name, phone (any formatting) and notes', () {
      expect(names(const LeadQuery(text: 'sam acc')), ['ABC Trading']);
      expect(names(const LeadQuery(text: '501234567')), ['ABC Trading']);
      expect(names(const LeadQuery(text: '+971501234567')), ['ABC Trading']);
      expect(names(const LeadQuery(text: 'cricket')), ['ABC Trading']);
      expect(names(const LeadQuery(text: 'premium objections')), ['ABC Trading']);
      expect(names(const LeadQuery(text: 'sharjah')), ['ABC Trading']);
      expect(names(const LeadQuery(text: 'nonexistent')), isEmpty);
    });
    test('LIKE wildcards are treated literally', () {
      expect(names(const LeadQuery(text: '%')), ['dune foods 100%_off']);
      expect(names(const LeadQuery(text: '_')), ['dune foods 100%_off']);
    });
    test('filter by quality, incl. unrated', () {
      expect(names(const LeadQuery(qualities: {LeadQuality.hot})), ['ABC Trading']);
      expect(names(const LeadQuery(qualities: {LeadQuality.hot, LeadQuality.warm}, sort: LeadSort.companyName)),
          ['ABC Trading', 'Bay Marine']);
      expect(names(const LeadQuery(unrated: true, sort: LeadSort.companyName)),
          ['Cedar Logistics', 'dune foods 100%_off']);
    });
    test('filter by target month/year', () {
      expect(names(const LeadQuery(targetMonth: '2026-12')), ['Bay Marine']);
      expect(names(const LeadQuery(targetMonth: '2027-12')), isEmpty);
    });
    test('filter by insurance line', () {
      expect(names(const LeadQuery(line: ProductLine.motor)), ['ABC Trading']);
      expect(names(const LeadQuery(line: ProductLine.property)), isEmpty);
    });
    test('filter by follow-up status relative to today (3 Oct 2026)', () {
      // clock advanced by 2 days in setUp -> today is 5 Oct 2026
      expect(names(const LeadQuery(followUp: FollowUpFilter.overdue, sort: LeadSort.companyName)),
          ['ABC Trading', 'Bay Marine']);
      expect(names(const LeadQuery(followUp: FollowUpFilter.upcoming)), ['Cedar Logistics']);
      expect(names(const LeadQuery(followUp: FollowUpFilter.none)), ['dune foods 100%_off']);
      expect(names(const LeadQuery(followUp: FollowUpFilter.today)), isEmpty);
    });
    test('combined search + filter', () {
      expect(names(const LeadQuery(text: 'trading', qualities: {LeadQuality.warm})), isEmpty);
      expect(names(const LeadQuery(text: 'trading', qualities: {LeadQuality.hot})), ['ABC Trading']);
    });
    test('sorting', () {
      expect(names(const LeadQuery(sort: LeadSort.companyName)),
          ['ABC Trading', 'Bay Marine', 'Cedar Logistics', 'dune foods 100%_off']);
      expect(names(const LeadQuery(sort: LeadSort.nextFollowUp)),
          ['Bay Marine', 'ABC Trading', 'Cedar Logistics', 'dune foods 100%_off']);
      expect(names(const LeadQuery(sort: LeadSort.latestUpdate)).first, 'dune foods 100%_off');
      // nearest *upcoming* expiry (today = 5 Oct 2026): Bay 2026-11-30, ABC 2027-03-15,
      // Cedar's only policy already expired -> last with Dune (none).
      expect(names(const LeadQuery(sort: LeadSort.nearestExpiry)).take(2).toList(),
          ['Bay Marine', 'ABC Trading']);
    });
    test('row summary shows products, next action and expiry state', () {
      final r = repo.queryLeads(const LeadQuery(text: 'abc'), env.today).single;
      expect(r.productSummary, 'Medical, Motor');
      expect(r.nextAction, 'Quote');
      expect(r.nearestExpiry(env.today), '2027-03-15');
      final cedar = repo.queryLeads(const LeadQuery(text: 'cedar'), env.today).single;
      expect(cedar.hasExpired(env.today), isTrue);
      expect(cedar.nearestExpiry(env.today), isNull);
    });
    test('renewals list shows each product separately for the same company', () {
      final rs = repo.renewals(from: '2027-01-01', to: '2027-12-31');
      expect(rs.map((r) => '${r.companyName}:${r.product.lineLabel}:${r.product.expiryDate}'),
          ['ABC Trading:Medical:2027-03-15', 'ABC Trading:Motor:2027-07-20']);
    });
  });

  test('settings round-trip', () {
    expect(repo.getSetting('x'), isNull);
    repo.setSetting('x', '1');
    repo.setSetting('x', '2');
    expect(repo.getSetting('x'), '2');
  });

  test('13. a few thousand records stay fast and complete', () {
    final sw = Stopwatch()..start();
    repo.transaction(() {
      for (var i = 0; i < 4000; i++) {
        final cid = 'c$i';
        repo.saveCompany(Company(
            id: cid,
            name: 'Company $i',
            quality: LeadQuality.values[i % 4],
            targetMonth: '2026-${(i % 12 + 1).toString().padLeft(2, '0')}',
            createdAt: env.clock,
            updatedAt: env.clock.add(Duration(minutes: i))));
        repo.saveContact(contact(cid, 'Person $i', phone: '+97150${(1000000 + i)}'));
        repo.saveProduct(product(cid, ProductLine.values[i % 5], '2027-0${i % 9 + 1}-10'));
        repo.saveTask(FollowUpTask(
            id: 't$i',
            companyId: cid,
            action: 'a',
            dueDate: '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}',
            createdAt: env.clock,
            updatedAt: env.clock));
      }
    });
    final all = repo.queryLeads(const LeadQuery(), env.today);
    expect(all.length, 4000);
    expect(repo.queryLeads(const LeadQuery(text: 'Company 3999'), env.today).single.company.id, 'c3999');
    expect(repo.queryLeads(const LeadQuery(text: '501003999'), env.today).length, greaterThan(0));
    expect(repo.queryLeads(const LeadQuery(qualities: {LeadQuality.hot}), env.today).length, 1000);
    expect(sw.elapsedMilliseconds, lessThan(8000));
  });
}
