import 'package:bcr_leadbook/data/lead_entry.dart';
import 'package:bcr_leadbook/data/models.dart';
import 'package:bcr_leadbook/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Product prod(String cid, ProductLine l, String exp) => Product(
    id: newId(), companyId: cid, line: l, expiryDate: exp, createdAt: DateTime(2000), updatedAt: DateTime(2000));

void main() {
  late TestEnv env;
  late Repository repo;
  setUp(() {
    env = TestEnv();
    repo = env.repo;
  });

  test('merge moves contacts, products, meetings and tasks; notes are appended', () {
    final a = newId(), b = newId();
    final c = Contact(id: newId(), companyId: a, name: 'Dup Person', createdAt: DateTime(2000), updatedAt: DateTime(2000));
    repo.commitEntry(LeadEntry(
        companyId: a,
        companyName: 'Acme Trading',
        trivia: 'Likes quotes early',
        quality: LeadQuality.hot,
        newContacts: [c],
        metContactId: c.id,
        summary: 'Meeting A',
        products: [prod(a, ProductLine.medical, '2027-03-15')],
        taskAction: 'Call A',
        taskDue: '2026-10-10'));
    repo.commitEntry(LeadEntry(companyId: b, companyName: 'Acme Trading LLC', trivia: 'New warehouse', summary: 'Meeting B'));
    repo.mergeCompanies(a, b);
    expect(repo.getCompany(a), isNull);
    final m = repo.bundle(b)!;
    expect(m.contacts.single.name, 'Dup Person');
    expect(m.products.length, 1);
    expect(m.meetings.map((x) => x.summary).toSet(), {'Meeting A', 'Meeting B'});
    expect(m.tasks.single.action, 'Call A');
    expect(m.company.trivia, contains('New warehouse'));
    expect(m.company.trivia, contains('Likes quotes early'));
    expect(m.company.quality, LeadQuality.hot, reason: 'filled from the merged-away company when empty');
    expect(repo.companyCount, 1);
  });

  test('restoreBundle brings a deleted company back exactly (Undo)', () {
    final id = newId();
    final c = Contact(id: newId(), companyId: id, name: 'P', createdAt: DateTime(2000), updatedAt: DateTime(2000));
    repo.commitEntry(LeadEntry(
        companyId: id,
        companyName: 'Undo Co',
        newContacts: [c],
        metContactId: c.id,
        summary: 'notes',
        products: [prod(id, ProductLine.motor, '2027-01-01')],
        taskAction: 't',
        taskDue: '2026-10-10'));
    final snap = repo.bundle(id)!;
    repo.deleteCompany(id);
    expect(repo.getCompany(id), isNull);
    repo.restoreBundle(snap);
    final back = repo.bundle(id)!;
    expect(back.company.createdAt, snap.company.createdAt);
    expect(back.contacts.length, 1);
    expect(back.products.length, 1);
    expect(back.meetings.single.contactId, c.id);
    expect(back.tasks.length, 1);
  });

  test('renewals can be limited to one insurance line', () {
    final id = newId();
    repo.commitEntry(LeadEntry(companyId: id, companyName: 'Lines Co', products: [
      prod(id, ProductLine.medical, '2026-12-01'),
      prod(id, ProductLine.motor, '2026-11-01'),
    ]));
    expect(repo.renewals(line: ProductLine.medical).map((r) => r.product.line), [ProductLine.medical]);
    expect(repo.renewals().length, 2);
  });

  test('lead row expiry follows the line filter', () {
    final id = newId();
    repo.commitEntry(LeadEntry(companyId: id, companyName: 'Lines Co', products: [
      prod(id, ProductLine.medical, '2027-03-15'),
      prod(id, ProductLine.marine, '2026-10-20'),
    ]));
    final all = repo.queryLeads(const LeadQuery(), env.today).single;
    final med = repo.queryLeads(const LeadQuery(line: ProductLine.medical), env.today).single;
    expect(all.nearestExpiry(env.today), '2026-10-20');
    expect(med.nearestExpiry(env.today), '2027-03-15');
  });

  test('national-format phone numbers find the international contact', () {
    final id = newId();
    final c = Contact(id: newId(), companyId: id, name: 'X', phone: '+971 50 123 4567', createdAt: DateTime(2000), updatedAt: DateTime(2000));
    repo.commitEntry(LeadEntry(companyId: id, companyName: 'Phone Co', newContacts: [c]));
    for (final q in ['0501234567', '050 123 4567', '+971501234567', '123 4567']) {
      expect(repo.queryLeads(LeadQuery(text: q), env.today).length, 1, reason: q);
    }
    expect(repo.queryLeads(const LeadQuery(text: '0509999999'), env.today), isEmpty);
  });
}
