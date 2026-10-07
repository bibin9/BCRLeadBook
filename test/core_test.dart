import 'package:bcr_leadbook/core/contact_utils.dart';
import 'package:bcr_leadbook/core/dates.dart';
import 'package:bcr_leadbook/core/name_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expiryInfo (local calendar date)', () {
    final today = DateTime(2026, 10, 3, 23, 59);
    test('unknown stays unknown', () {
      expect(expiryInfo(null, today).state, ExpiryState.unknown);
      expect(expiryInfo('', today).state, ExpiryState.unknown);
      expect(expiryInfo('garbage', today).state, ExpiryState.unknown);
      expect(expiryInfo('2026-02-31', today).state, ExpiryState.unknown);
    });
    test('today, tomorrow, future, expired', () {
      expect(expiryInfo('2026-10-03', today).label, 'Expires today');
      expect(expiryInfo('2026-10-04', today).label, '1 day left');
      expect(expiryInfo('2026-10-13', today).label, '10 days left');
      expect(expiryInfo('2026-10-02', today).label, 'Expired');
      expect(expiryInfo('2026-10-02', today).state, ExpiryState.expired);
    });
    test('spans month and year boundaries', () {
      final dec31 = DateTime(2026, 12, 31, 8);
      expect(expiryInfo('2027-01-01', dec31).days, 1);
      expect(expiryInfo('2027-03-15', dec31).days, 74);
      expect(expiryInfo('2026-12-30', dec31).state, ExpiryState.expired);
    });
    test('leap day', () {
      expect(expiryInfo('2028-03-01', DateTime(2028, 2, 28)).days, 2);
      expect(expiryInfo('2027-03-01', DateTime(2027, 2, 28)).days, 1);
    });
    test('daylight-saving change does not shift the day count', () {
      // Would be off by one with Duration-based maths in a DST zone.
      expect(Dates.daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(Dates.daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    });
  });

  group('follow-up buckets', () {
    final today = DateTime(2026, 1, 1, 9);
    test('overdue / today / upcoming across a year boundary', () {
      expect(followUpBucket('2025-12-31', today), FollowUpBucket.overdue);
      expect(followUpBucket('2026-01-01', today), FollowUpBucket.today);
      expect(followUpBucket('2026-01-02', today), FollowUpBucket.upcoming);
    });
    test('labels', () {
      expect(dueLabel('2025-12-29', today), '3 days overdue');
      expect(dueLabel('2025-12-31', today), 'Yesterday');
      expect(dueLabel('2026-01-02', today), 'Tomorrow');
    });
  });

  group('month arithmetic', () {
    test('addDays crosses month/year', () {
      expect(Dates.toIso(Dates.addDays(DateTime(2026, 12, 31), 1)), '2027-01-01');
      expect(Dates.toIso(Dates.addDays(DateTime(2026, 1, 1), -1)), '2025-12-31');
    });
    test('addMonths clamps day', () {
      expect(Dates.toIso(Dates.addMonths(DateTime(2026, 1, 31), 1)), '2026-02-28');
      expect(Dates.toIso(Dates.addMonths(DateTime(2028, 1, 31), 1)), '2028-02-29');
      expect(Dates.toIso(Dates.addMonths(DateTime(2026, 11, 15), 3)), '2027-02-15');
      expect(Dates.toIso(Dates.addMonths(DateTime(2026, 2, 15), -3)), '2025-11-15');
    });
    test('month key & label', () {
      expect(Dates.monthKey(2026, 11), '2026-11');
      expect(Dates.monthLabel('2026-11'), 'November 2026');
      expect(Dates.parseMonthKey('2026-13'), isNull);
      expect(Dates.parseMonthKey(null), isNull);
    });
    test('time parsing', () {
      expect(Dates.parseTime('09:00')!.hour, 9);
      expect(Dates.parseTime('24:00'), isNull);
      expect(Dates.displayTime('09:00'), '9:00 AM');
      expect(Dates.displayTime('15:30'), '3:30 PM');
    });
  });

  group('phone & email helpers', () {
    test('friendly phone hints', () {
      expect(ContactUtils.phoneHint(''), isNull);
      expect(ContactUtils.phoneHint('+971 50 123 4567'), isNull);
      expect(ContactUtils.phoneHint('+44 (0)20 7946 0958'), isNull);
      expect(ContactUtils.phoneHint('0501234567'), contains('country code'));
      expect(ContactUtils.phoneHint('123'), contains('short'));
      expect(ContactUtils.phoneHint('abc'), contains('digits'));
    });
    test('whatsapp link is digits only, no plus or 00', () {
      expect(ContactUtils.whatsappUri('+971 50 123 4567').toString(),
          'https://wa.me/971501234567');
      expect(ContactUtils.whatsappUri('00971501234567').toString(),
          'https://wa.me/971501234567');
      expect(ContactUtils.whatsappUri('12'), isNull);
    });
    test('tel keeps plus', () {
      expect(ContactUtils.telUri('+971 50-123 4567').toString(), 'tel:+971501234567');
    });
    test('email hint', () {
      expect(ContactUtils.emailHint('a@b.com'), isNull);
      expect(ContactUtils.emailHint('a@b'), isNotNull);
      expect(ContactUtils.emailHint(''), isNull);
    });
  });

  group('similar company names', () {
    test('suggests near matches', () {
      expect(NameMatch.similar('ABC Trading LLC', 'ABC Trading'), isTrue);
      expect(NameMatch.similar('A.B.C. Trading', 'ABC trading'), isTrue);
      expect(NameMatch.similar('Al Noor Group', 'Al Nour Group'), isTrue);
      expect(NameMatch.similar('Gulf Marine', 'Gulf Marine Services'), isTrue);
    });
    test('does not match different companies', () {
      expect(NameMatch.similar('ABC Trading', 'XYZ Trading'), isFalse);
      expect(NameMatch.similar('Bay Marine', 'Cedar Logistics'), isFalse);
      expect(NameMatch.similar('AB', 'AC'), isFalse);
    });
  });
}
