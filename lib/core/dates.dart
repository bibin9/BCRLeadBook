import 'package:intl/intl.dart';

/// Calendar-date helpers.
///
/// Dates without a time of day (policy expiry, follow-up due date) are stored
/// as `yyyy-MM-dd` text and compared as *calendar dates in the device's local
/// time zone*. Day arithmetic never uses `Duration(days: n)` on local
/// DateTimes, because that is off by an hour across daylight-saving changes.
class Dates {
  Dates._();

  static String _two(int n) => n.toString().padLeft(2, '0');

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String toIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  /// Parses `yyyy-MM-dd`; returns null for null, empty or invalid input.
  static DateTime? parseIso(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final dt = DateTime(y, mo, d);
    if (dt.year != y || dt.month != mo || dt.day != d) return null; // 31 Feb
    return dt;
  }

  /// Whole calendar days from [from] to [to] (negative if [to] is earlier).
  static int daysBetween(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;

  static DateTime addDays(DateTime d, int n) =>
      DateTime(d.year, d.month, d.day + n);

  /// Adds [n] months, clamping the day (31 Jan + 1 month = 28/29 Feb).
  static DateTime addMonths(DateTime d, int n) {
    final total = d.year * 12 + (d.month - 1) + n;
    final y = total ~/ 12;
    final m = total % 12 + 1;
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d.day > last ? last : d.day);
  }

  // ---- Target month ("2026-11") -------------------------------------------

  static String monthKey(int year, int month) =>
      '${year.toString().padLeft(4, '0')}-${_two(month)}';

  static ({int year, int month})? parseMonthKey(String? key) {
    if (key == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(key);
    if (m == null) return null;
    final mo = int.parse(m.group(2)!);
    if (mo < 1 || mo > 12) return null;
    return (year: int.parse(m.group(1)!), month: mo);
  }

  /// "November 2026"
  static String monthLabel(String? key) {
    final p = parseMonthKey(key);
    if (p == null) return '';
    return DateFormat('MMMM yyyy').format(DateTime(p.year, p.month));
  }

  // ---- Display -------------------------------------------------------------

  /// "15 Mar 2027"
  static String display(String? iso) {
    final d = parseIso(iso);
    return d == null ? '' : DateFormat('d MMM yyyy').format(d);
  }

  static String displayDate(DateTime d) => DateFormat('d MMM yyyy').format(d);

  /// "15 Mar 2027, 3:30 PM"
  static String displayDateTime(DateTime d) =>
      DateFormat('d MMM yyyy, h:mm a').format(d);

  /// "09:00" -> "9:00 AM"
  static String displayTime(String? hhmm) {
    final t = parseTime(hhmm);
    if (t == null) return '';
    return DateFormat('h:mm a').format(DateTime(2000, 1, 1, t.hour, t.minute));
  }

  static ({int hour, int minute})? parseTime(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    if (h > 23 || mi > 59) return null;
    return (hour: h, minute: mi);
  }

  static String timeToString(int hour, int minute) =>
      '${_two(hour)}:${_two(minute)}';
}

enum ExpiryState { unknown, expired, today, upcoming }

class ExpiryInfo {
  const ExpiryInfo(this.state, this.days, this.label);
  final ExpiryState state;

  /// Days until expiry; negative when expired; null when unknown.
  final int? days;
  final String label;
}

/// Days until a policy expires, using the device's local calendar date.
/// An unknown date stays unknown; nothing is invented.
ExpiryInfo expiryInfo(String? iso, DateTime today) {
  final d = Dates.parseIso(iso);
  if (d == null) {
    return const ExpiryInfo(ExpiryState.unknown, null, 'Expiry unknown');
  }
  final days = Dates.daysBetween(today, d);
  if (days < 0) return ExpiryInfo(ExpiryState.expired, days, 'Expired');
  if (days == 0) return const ExpiryInfo(ExpiryState.today, 0, 'Expires today');
  if (days == 1) return const ExpiryInfo(ExpiryState.upcoming, 1, '1 day left');
  return ExpiryInfo(ExpiryState.upcoming, days, '$days days left');
}

enum FollowUpBucket { overdue, today, upcoming }

FollowUpBucket followUpBucket(String dueIso, DateTime today) {
  final d = Dates.parseIso(dueIso);
  if (d == null) return FollowUpBucket.upcoming;
  final diff = Dates.daysBetween(today, d);
  if (diff < 0) return FollowUpBucket.overdue;
  if (diff == 0) return FollowUpBucket.today;
  return FollowUpBucket.upcoming;
}

/// Short, plain-English description of a due date relative to today.
String dueLabel(String dueIso, DateTime today) {
  final d = Dates.parseIso(dueIso);
  if (d == null) return '';
  final diff = Dates.daysBetween(today, d);
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff < 0) return '${-diff} days overdue';
  return Dates.display(dueIso);
}
