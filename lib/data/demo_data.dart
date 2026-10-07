import '../core/dates.dart';
import 'models.dart';
import 'repository.dart';

/// Optional sample records, only ever created when the user taps
/// "Load demo data" in Settings. Names are fictional. Demo ids start with
/// `demo_` so they can be removed again without touching real records.
class DemoData {
  DemoData._();

  static const prefix = 'demo_';

  static int count(Repository repo) => repo.db
      .select("SELECT COUNT(*) c FROM companies WHERE id LIKE 'demo\\_%' ESCAPE '\\'")
      .first['c'] as int;

  static void remove(Repository repo) {
    repo.transaction(() {
      repo.db.execute("DELETE FROM companies WHERE id LIKE 'demo\\_%' ESCAPE '\\'");
      repo.db.execute("DELETE FROM drafts WHERE key LIKE '%demo\\_%' ESCAPE '\\'");
    });
  }

  static void load(Repository repo) {
    final now = repo.now;
    final today = Dates.dateOnly(now);
    String d(int offsetDays) => Dates.toIso(Dates.addDays(today, offsetDays));

    repo.transaction(() {
      void company(
        String key,
        String name,
        String location, {
        LeadQuality? quality,
        String? target,
        String trivia = '',
        int updatedDaysAgo = 0,
        List<(String, String, String, String, String, bool, String)> people = const [],
        List<(ProductLine, String, String?, String)> products = const [],
        String summary = '',
        int metIdx = 0,
        int nextIdx = 0,
        String? action,
        int? dueOffset,
      }) {
        final cid = '$prefix$key';
        final at = now.subtract(Duration(days: updatedDaysAgo));
        repo.saveCompany(Company(
          id: cid,
          name: name,
          location: location,
          trivia: trivia,
          quality: quality,
          targetMonth: target,
          createdAt: at,
          updatedAt: at,
        ));
        final ids = <String>[];
        for (var i = 0; i < people.length; i++) {
          final p = people[i];
          final id = '$prefix${key}_c$i';
          ids.add(id);
          repo.saveContact(Contact(
            id: id,
            companyId: cid,
            name: p.$1,
            title: p.$2,
            phone: p.$3,
            email: p.$4,
            notes: p.$5,
            isDecisionMaker: p.$6,
            createdAt: at,
            updatedAt: at,
          ));
        }
        for (var i = 0; i < products.length; i++) {
          final p = products[i];
          repo.saveProduct(Product(
            id: '$prefix${key}_p$i',
            companyId: cid,
            line: p.$1,
            label: p.$2,
            expiryDate: p.$3,
            insurer: p.$4,
            createdAt: at,
            updatedAt: at,
          ));
        }
        String? mid;
        if (summary.isNotEmpty) {
          mid = '$prefix${key}_m0';
          repo.saveMeeting(Meeting(
            id: mid,
            companyId: cid,
            contactId: ids.isEmpty ? null : ids[metIdx],
            nextContactId: ids.isEmpty ? null : ids[nextIdx],
            meetingAt: at,
            summary: summary,
            createdAt: at,
            updatedAt: at,
          ));
        }
        if (action != null && dueOffset != null) {
          repo.saveTask(FollowUpTask(
            id: '$prefix${key}_t0',
            companyId: cid,
            contactId: ids.isEmpty ? null : ids[nextIdx],
            meetingId: mid,
            action: action,
            dueDate: d(dueOffset),
            createdAt: at,
            updatedAt: at,
          ));
        }
      }

      final nextYear = today.year + 1;
      company(
        'abc',
        'ABC Trading (demo)',
        'Dubai',
        quality: LeadQuality.hot,
        target: Dates.monthKey(today.year, today.month),
        trivia: 'Opening a second warehouse in Sharjah next year. Staff count growing from 40 to 70.',
        updatedDaysAgo: 1,
        people: [
          ('Sample Person A', 'Finance Manager', '+971 50 000 0001', 'a@example.com',
              'Supports a local football team. Prefers tea over coffee. Daughter starting university.', false, ''),
          ('Sample Person B', 'Managing Director', '+971 50 000 0002', 'b@example.com',
              'Recently back from a trip to Turkey.', true, ''),
        ],
        products: [
          (ProductLine.medical, 'Staff', '$nextYear-03-15', 'Sample Insurer'),
          (ProductLine.motor, 'Fleet', '$nextYear-07-20', ''),
        ],
        summary:
            'Reviewed current medical cover. Concern about rising premiums. Promised a comparison of three quotes. Next step: send quotes and call the MD.',
        metIdx: 0,
        nextIdx: 1,
        action: 'Send medical quote comparison',
        dueOffset: 0,
      );
      company(
        'bay',
        'Bay Marine Services (demo)',
        'Abu Dhabi',
        quality: LeadQuality.warm,
        target: Dates.monthKey(Dates.addMonths(today, 2).year, Dates.addMonths(today, 2).month),
        updatedDaysAgo: 3,
        people: [('Sample Person C', 'Operations Head', '+971 50 000 0003', '', '', true, '')],
        products: [(ProductLine.marine, 'Hull', d(45), '')],
        summary: 'Intro meeting. Vessel cover renews soon; wants a second option.',
        action: 'Call about marine renewal',
        dueOffset: -3,
      );
      company(
        'cedar',
        'Cedar Logistics (demo)',
        'Sharjah',
        quality: LeadQuality.cold,
        updatedDaysAgo: 10,
        products: [(ProductLine.liability, '', d(-20), '')],
        action: 'Check back after audit season',
        dueOffset: 14,
      );
      company(
        'dune',
        'Dune Foods (demo)',
        'Ras Al Khaimah',
        quality: LeadQuality.future,
        target: '$nextYear-01',
        updatedDaysAgo: 20,
        products: [(ProductLine.property, 'Factory', null, '')],
      );
      company('eagle', 'Eagle Interiors (demo)', '', updatedDaysAgo: 30);
    });
  }
}
