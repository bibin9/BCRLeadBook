import 'package:sqlite3/sqlite3.dart';

import '../core/dates.dart';
import 'lead_entry.dart';
import 'models.dart';

enum FollowUpFilter { any, overdue, today, upcoming, none }

enum LeadSort { nextFollowUp, latestUpdate, companyName, nearestExpiry }

class LeadQuery {
  const LeadQuery({
    this.text = '',
    this.qualities = const {},
    this.unrated = false,
    this.targetMonth,
    this.line,
    this.followUp = FollowUpFilter.any,
    this.sort = LeadSort.latestUpdate,
  });

  final String text;
  final Set<LeadQuality> qualities;

  /// Also match leads whose quality hasn't been chosen yet.
  final bool unrated;
  final String? targetMonth;
  final ProductLine? line;
  final FollowUpFilter followUp;
  final LeadSort sort;

  bool get hasFilters =>
      qualities.isNotEmpty ||
      unrated ||
      targetMonth != null ||
      line != null ||
      followUp != FollowUpFilter.any;

  LeadQuery copyWith({
    String? text,
    Set<LeadQuality>? qualities,
    bool? unrated,
    String? targetMonth,
    bool clearTargetMonth = false,
    ProductLine? line,
    bool clearLine = false,
    FollowUpFilter? followUp,
    LeadSort? sort,
  }) =>
      LeadQuery(
        text: text ?? this.text,
        qualities: qualities ?? this.qualities,
        unrated: unrated ?? this.unrated,
        targetMonth: clearTargetMonth ? null : (targetMonth ?? this.targetMonth),
        line: clearLine ? null : (line ?? this.line),
        followUp: followUp ?? this.followUp,
        sort: sort ?? this.sort,
      );

  String get cacheKey =>
      '$text|${(qualities.map((q) => q.db).toList()..sort()).join(',')}|$unrated|$targetMonth|${line?.db}|${followUp.name}|${sort.name}';
}

/// One compact row of the Leads list.
class LeadRow {
  LeadRow({
    required this.company,
    this.nextDue,
    this.nextAction,
    this.products = const [],
    this.lineFilter,
  });

  final Company company;
  final String? nextDue;
  final String? nextAction;
  final List<Product> products;

  /// When the list is filtered to one insurance line, expiry dates shown for
  /// the row only consider that line.
  final ProductLine? lineFilter;

  Iterable<Product> get _relevant =>
      lineFilter == null ? products : products.where((p) => p.line == lineFilter);

  /// Earliest not-yet-expired expiry date across the relevant products.
  String? nearestExpiry(DateTime today) {
    final t = Dates.toIso(today);
    String? best;
    for (final p in _relevant) {
      final e = p.expiryDate;
      if (e == null || e.compareTo(t) < 0) continue;
      if (best == null || e.compareTo(best) < 0) best = e;
    }
    return best;
  }

  bool hasExpired(DateTime today) {
    final t = Dates.toIso(today);
    return _relevant.any((p) => p.expiryDate != null && p.expiryDate!.compareTo(t) < 0);
  }

  /// "Medical, Motor"
  String get productSummary {
    final seen = <String>[];
    for (final p in products) {
      final l = p.lineLabel;
      if (!seen.contains(l)) seen.add(l);
    }
    return seen.join(', ');
  }
}

/// A pending task that wants a local notification.
class PendingReminder {
  const PendingReminder({
    required this.seq,
    required this.taskId,
    required this.dueDate,
    required this.time,
    required this.companyName,
  });
  final int seq;
  final String taskId;
  final String dueDate;
  final String time;
  final String companyName;
}

class CompanyBundle {
  CompanyBundle({
    required this.company,
    required this.contacts,
    required this.products,
    required this.meetings,
    required this.tasks,
  });
  final Company company;
  final List<Contact> contacts;
  final List<Product> products;

  /// Newest first.
  final List<Meeting> meetings;
  final List<FollowUpTask> tasks;

  Contact? contactById(String? id) {
    if (id == null) return null;
    for (final c in contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  Meeting? get lastMeeting => meetings.isEmpty ? null : meetings.first;

  /// The person to call next: the last meeting's "next call" contact, falling
  /// back to the person met, then a decision-maker.
  Contact? get nextCallContact {
    final m = lastMeeting;
    if (m != null) {
      final c = contactById(m.nextContactId) ?? contactById(m.contactId);
      if (c != null) return c;
    }
    for (final c in contacts) {
      if (c.isDecisionMaker) return c;
    }
    return contacts.isEmpty ? null : contacts.first;
  }

  List<FollowUpTask> get pendingTasks {
    final l = tasks.where((t) => t.isPending).toList()
      ..sort((a, b) {
        final c = a.dueDate.compareTo(b.dueDate);
        return c != 0 ? c : (a.reminderTime ?? '').compareTo(b.reminderTime ?? '');
      });
    return l;
  }

  FollowUpTask? get nextTask {
    final l = pendingTasks;
    return l.isEmpty ? null : l.first;
  }

  /// Products with a known expiry, nearest first.
  List<Product> get productsByExpiry {
    final l = [...products];
    l.sort((a, b) {
      if (a.expiryDate == null && b.expiryDate == null) return 0;
      if (a.expiryDate == null) return 1;
      if (b.expiryDate == null) return -1;
      return a.expiryDate!.compareTo(b.expiryDate!);
    });
    return l;
  }
}

/// All reads and writes to the local SQLite database.
///
/// The UI never sees SQL. All multi-row writes run in a transaction.
class Repository {
  Repository(this.db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database db;
  final DateTime Function() _clock;

  DateTime get now => _clock();

  // ---- transactions --------------------------------------------------------

  int _depth = 0;

  T transaction<T>(T Function() body) {
    if (_depth > 0) return body();
    db.execute('BEGIN');
    _depth++;
    try {
      final r = body();
      db.execute('COMMIT');
      return r;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      _depth--;
    }
  }

  List<Map<String, Object?>> _rows(String sql, [List<Object?> args = const []]) =>
      db.select(sql, args).map((r) => Map<String, Object?>.from(r)).toList();

  // ---- companies -----------------------------------------------------------

  Company? getCompany(String id) {
    final r = _rows('SELECT * FROM companies WHERE id = ?', [id]);
    return r.isEmpty ? null : Company.fromMap(r.first);
  }

  int get companyCount =>
      db.select('SELECT COUNT(*) c FROM companies').first['c'] as int;

  /// Lightweight (id, name) list for similar-name detection.
  List<({String id, String name})> companyNames() => db
      .select('SELECT id, name FROM companies ORDER BY name COLLATE NOCASE')
      .map((r) => (id: r['id'] as String, name: r['name'] as String))
      .toList();

  /// Insert or update. `created_at` is never changed on update.
  void saveCompany(Company c) {
    db.execute('''
INSERT INTO companies (id, name, location, trivia, rapport_notes, quality, target_month, created_at, updated_at)
VALUES (?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
  name=excluded.name, location=excluded.location, trivia=excluded.trivia,
  rapport_notes=excluded.rapport_notes, quality=excluded.quality,
  target_month=excluded.target_month, updated_at=excluded.updated_at
''', [
      c.id,
      c.name,
      c.location,
      c.trivia,
      c.rapportNotes,
      c.quality?.db,
      c.targetMonth,
      c.createdAt.millisecondsSinceEpoch,
      c.updatedAt.millisecondsSinceEpoch,
    ]);
  }

  /// Update company fields and stamp "last updated".
  void updateCompany(Company c) =>
      saveCompany(c.copyWith(updatedAt: now));

  /// Moves everything from [sourceId] into [targetId], then removes the
  /// source company. Notes are appended, never discarded.
  void mergeCompanies(String sourceId, String targetId) {
    if (sourceId == targetId) return;
    transaction(() {
      final src = getCompany(sourceId);
      final dst = getCompany(targetId);
      if (src == null || dst == null) {
        throw ArgumentError('Company not found');
      }
      for (final t in ['contacts', 'products', 'meetings', 'tasks']) {
        db.execute('UPDATE $t SET company_id = ? WHERE company_id = ?', [targetId, sourceId]);
      }
      String join(String a, String b) {
        if (b.trim().isEmpty || a.contains(b.trim())) return a;
        return a.trim().isEmpty ? b : '$a\n\n$b';
      }
      saveCompany(dst.copyWith(
        trivia: join(dst.trivia, src.trivia),
        rapportNotes: join(dst.rapportNotes, src.rapportNotes),
        location: dst.location.isEmpty ? src.location : dst.location,
        quality: dst.quality ?? src.quality,
        targetMonth: dst.targetMonth ?? src.targetMonth,
        updatedAt: now,
      ));
      db.execute('DELETE FROM companies WHERE id = ?', [sourceId]);
      db.execute('DELETE FROM drafts WHERE key = ?', ['co:$sourceId']);
    });
  }

  /// Puts a deleted company back exactly as it was (Undo).
  void restoreBundle(CompanyBundle b) => transaction(() {
        saveCompany(b.company);
        for (final c in b.contacts) {
          saveContact(c);
        }
        for (final p in b.products) {
          saveProduct(p);
        }
        for (final m in b.meetings) {
          saveMeeting(m);
        }
        for (final t in b.tasks) {
          saveTask(t);
        }
      });

  void touchCompany(String id) => db.execute(
      'UPDATE companies SET updated_at = ? WHERE id = ?',
      [now.millisecondsSinceEpoch, id]);

  void deleteCompany(String id) => transaction(() {
        db.execute('DELETE FROM companies WHERE id = ?', [id]);
        db.execute('DELETE FROM drafts WHERE key = ?', ['co:$id']);
      });

  // ---- contacts ------------------------------------------------------------

  List<Contact> contactsFor(String companyId) => _rows(
          'SELECT * FROM contacts WHERE company_id = ? ORDER BY is_decision_maker DESC, name COLLATE NOCASE',
          [companyId])
      .map(Contact.fromMap)
      .toList();

  Contact? getContact(String id) {
    final r = _rows('SELECT * FROM contacts WHERE id = ?', [id]);
    return r.isEmpty ? null : Contact.fromMap(r.first);
  }

  void saveContact(Contact c) {
    final m = c.toMap();
    db.execute('''
INSERT INTO contacts (id, company_id, name, title, phone, phone_norm, email, notes, is_decision_maker, created_at, updated_at)
VALUES (?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
  name=excluded.name, title=excluded.title, phone=excluded.phone,
  phone_norm=excluded.phone_norm, email=excluded.email, notes=excluded.notes,
  is_decision_maker=excluded.is_decision_maker, updated_at=excluded.updated_at
''', [
      m['id'], m['company_id'], m['name'], m['title'], m['phone'],
      m['phone_norm'], m['email'], m['notes'], m['is_decision_maker'],
      m['created_at'], m['updated_at'],
    ]);
  }

  /// Save from the UI: stamps updated_at on contact and company.
  void upsertContact(Contact c) => transaction(() {
        saveContact(c.copyWith(updatedAt: now));
        touchCompany(c.companyId);
      });

  void deleteContact(String id) => transaction(() {
        final c = getContact(id);
        db.execute('DELETE FROM contacts WHERE id = ?', [id]);
        if (c != null) touchCompany(c.companyId);
      });

  // ---- products ------------------------------------------------------------

  List<Product> productsFor(String companyId) => _rows(
          'SELECT * FROM products WHERE company_id = ? ORDER BY created_at',
          [companyId])
      .map(Product.fromMap)
      .toList();

  void saveProduct(Product p) {
    final m = p.toMap();
    db.execute('''
INSERT INTO products (id, company_id, line, custom_line, label, expiry_date, insurer, notes, created_at, updated_at)
VALUES (?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
  line=excluded.line, custom_line=excluded.custom_line, label=excluded.label,
  expiry_date=excluded.expiry_date, insurer=excluded.insurer, notes=excluded.notes,
  updated_at=excluded.updated_at
''', [
      m['id'], m['company_id'], m['line'], m['custom_line'], m['label'],
      m['expiry_date'], m['insurer'], m['notes'], m['created_at'],
      m['updated_at'],
    ]);
  }

  void upsertProduct(Product p) => transaction(() {
        saveProduct(p.copyWith(updatedAt: now));
        touchCompany(p.companyId);
      });

  void deleteProduct(String id) => transaction(() {
        final r = _rows('SELECT company_id FROM products WHERE id = ?', [id]);
        db.execute('DELETE FROM products WHERE id = ?', [id]);
        if (r.isNotEmpty) touchCompany(r.first['company_id'] as String);
      });

  /// Products with a known expiry, nearest first, joined with company names.
  /// [from]/[to] are inclusive `yyyy-MM-dd` bounds (either may be null).
  List<ProductWithCompany> renewals({String? from, String? to, ProductLine? line}) {
    final where = <String>['p.expiry_date IS NOT NULL'];
    final args = <Object?>[];
    if (from != null) {
      where.add('p.expiry_date >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('p.expiry_date <= ?');
      args.add(to);
    }
    if (line != null) {
      where.add('p.line = ?');
      args.add(line.db);
    }
    final rows = _rows('''
SELECT p.*, c.name AS company_name FROM products p
JOIN companies c ON c.id = p.company_id
WHERE ${where.join(' AND ')}
ORDER BY p.expiry_date, c.name COLLATE NOCASE
''', args);
    return rows
        .map((r) => ProductWithCompany(Product.fromMap(r), r['company_name'] as String))
        .toList();
  }

  // ---- meetings ------------------------------------------------------------

  List<Meeting> meetingsFor(String companyId) => _rows(
          'SELECT * FROM meetings WHERE company_id = ? ORDER BY meeting_at DESC, created_at DESC',
          [companyId])
      .map(Meeting.fromMap)
      .toList();

  void saveMeeting(Meeting m) {
    final x = m.toMap();
    db.execute('''
INSERT INTO meetings (id, company_id, contact_id, next_contact_id, meeting_at, summary, created_at, updated_at)
VALUES (?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
  contact_id=excluded.contact_id, next_contact_id=excluded.next_contact_id,
  meeting_at=excluded.meeting_at, summary=excluded.summary, updated_at=excluded.updated_at
''', [
      x['id'], x['company_id'], x['contact_id'], x['next_contact_id'],
      x['meeting_at'], x['summary'], x['created_at'], x['updated_at'],
    ]);
  }

  void upsertMeeting(Meeting m) => transaction(() {
        saveMeeting(m.copyWith(updatedAt: now));
        touchCompany(m.companyId);
      });

  void deleteMeeting(String id) => transaction(() {
        final r = _rows('SELECT company_id FROM meetings WHERE id = ?', [id]);
        db.execute('DELETE FROM meetings WHERE id = ?', [id]);
        if (r.isNotEmpty) touchCompany(r.first['company_id'] as String);
      });

  // ---- tasks ---------------------------------------------------------------

  List<FollowUpTask> tasksFor(String companyId) => _rows(
          'SELECT * FROM tasks WHERE company_id = ? ORDER BY due_date, reminder_time',
          [companyId])
      .map(FollowUpTask.fromMap)
      .toList();

  FollowUpTask? getTask(String id) {
    final r = _rows('SELECT * FROM tasks WHERE id = ?', [id]);
    return r.isEmpty ? null : FollowUpTask.fromMap(r.first);
  }

  void saveTask(FollowUpTask t) {
    final m = t.toMap();
    db.execute('''
INSERT INTO tasks (id, company_id, contact_id, product_id, meeting_id, action, due_date, reminder_time, status, completed_at, created_at, updated_at)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
  contact_id=excluded.contact_id, product_id=excluded.product_id,
  action=excluded.action, due_date=excluded.due_date,
  reminder_time=excluded.reminder_time, status=excluded.status,
  completed_at=excluded.completed_at, updated_at=excluded.updated_at
''', [
      m['id'], m['company_id'], m['contact_id'], m['product_id'],
      m['meeting_id'], m['action'], m['due_date'], m['reminder_time'],
      m['status'], m['completed_at'], m['created_at'], m['updated_at'],
    ]);
  }

  void upsertTask(FollowUpTask t) => transaction(() {
        saveTask(t.copyWith(updatedAt: now));
        touchCompany(t.companyId);
      });

  void deleteTask(String id) => transaction(() {
        final r = _rows('SELECT company_id FROM tasks WHERE id = ?', [id]);
        db.execute('DELETE FROM tasks WHERE id = ?', [id]);
        if (r.isNotEmpty) touchCompany(r.first['company_id'] as String);
      });

  void completeTask(String id) {
    final t = getTask(id);
    if (t == null) return;
    upsertTask(t.copyWith(status: TaskStatus.completed, completedAt: now));
  }

  void reopenTask(String id) {
    final t = getTask(id);
    if (t == null) return;
    upsertTask(t.copyWith(status: TaskStatus.pending, clearCompletedAt: true));
  }

  /// Move to a new date (and optionally time). The due date is the only
  /// thing that changes; the company's target month is untouched.
  void rescheduleTask(String id, DateTime date, {String? reminderTime, bool clearReminder = false}) {
    final t = getTask(id);
    if (t == null) return;
    upsertTask(t.copyWith(
      dueDate: Dates.toIso(date),
      reminderTime: reminderTime,
      clearReminder: clearReminder,
    ));
  }

  /// Snooze until tomorrow (calendar day after [today]).
  void snoozeTaskUntilTomorrow(String id, DateTime today) =>
      rescheduleTask(id, Dates.addDays(Dates.dateOnly(today), 1));

  /// Tasks across all companies.
  /// [pending] true = pending only, false = completed only.
  List<TaskWithCompany> tasks({required bool pending}) {
    final rows = _rows('''
SELECT t.*, c.name AS company_name FROM tasks t
JOIN companies c ON c.id = t.company_id
WHERE t.status = ?
ORDER BY ${pending ? 't.due_date, t.reminder_time, c.name COLLATE NOCASE' : 't.completed_at DESC'}
''', [pending ? 'pending' : 'completed']);
    return rows
        .map((r) => TaskWithCompany(FollowUpTask.fromMap(r), r['company_name'] as String))
        .toList();
  }

  /// Pending tasks that carry a reminder time, soonest first.
  List<PendingReminder> pendingReminders() {
    final rows = _rows('''
SELECT t.seq, t.id, t.due_date, t.reminder_time, c.name AS company_name
FROM tasks t JOIN companies c ON c.id = t.company_id
WHERE t.status = 'pending' AND t.reminder_time IS NOT NULL
ORDER BY t.due_date, t.reminder_time
''');
    return rows
        .map((r) => PendingReminder(
              seq: r['seq'] as int,
              taskId: r['id'] as String,
              dueDate: r['due_date'] as String,
              time: r['reminder_time'] as String,
              companyName: r['company_name'] as String,
            ))
        .toList();
  }

  // ---- bundles & lists -----------------------------------------------------

  CompanyBundle? bundle(String companyId) {
    final c = getCompany(companyId);
    if (c == null) return null;
    return CompanyBundle(
      company: c,
      contacts: contactsFor(companyId),
      products: productsFor(companyId),
      meetings: meetingsFor(companyId),
      tasks: tasksFor(companyId),
    );
  }

  /// Recently updated companies (dashboard).
  List<Company> recentCompanies(int limit) =>
      _rows('SELECT * FROM companies ORDER BY updated_at DESC LIMIT ?', [limit])
          .map(Company.fromMap)
          .toList();

  List<Company> hotLeads(int limit) => _rows(
          "SELECT * FROM companies WHERE quality = 'hot' ORDER BY updated_at DESC LIMIT ?",
          [limit])
      .map(Company.fromMap)
      .toList();

  int countHot() => db
      .select("SELECT COUNT(*) c FROM companies WHERE quality = 'hot'")
      .first['c'] as int;

  static String _like(String token) {
    final escaped = token
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return '%$escaped%';
  }

  /// Search + filter + sort for the Leads screen.
  ///
  /// Search is matched per word (all words must match somewhere) across
  /// company, location, context, contact names/titles/emails/notes/phones,
  /// meeting summaries and product details.
  List<LeadRow> queryLeads(LeadQuery q, DateTime today) {
    final where = <String>[];
    final args = <Object?>[];

    // A phone number typed with spaces ("050 123 4567") is one search term.
    final raw = q.text.trim();
    final phoneLike = RegExp(r'^[+0-9()\-\s]+$').hasMatch(raw) &&
        raw.replaceAll(RegExp(r'[^0-9]'), '').length >= 7;
    final tokens = phoneLike
        ? [raw]
        : raw.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    for (final token in tokens) {
      final like = _like(token);
      final digits = token.replaceAll(RegExp(r'[^0-9]'), '');
      // "0501234567" (national format) must also find "+971 50 123 4567".
      final phoneNeedles = <String>[
        if (digits.length >= 3) digits,
        if (digits.length >= 7 && digits.startsWith('0') && !digits.startsWith('00'))
          digits.replaceFirst(RegExp(r'^0+'), ''),
      ];
      final phoneClause = [
        for (final _ in phoneNeedles) " OR ct.phone_norm LIKE ? ESCAPE '\\'"
      ].join();
      where.add('''(
  c.name LIKE ? ESCAPE '\\' OR c.location LIKE ? ESCAPE '\\' OR c.trivia LIKE ? ESCAPE '\\' OR c.rapport_notes LIKE ? ESCAPE '\\'
  OR EXISTS (SELECT 1 FROM contacts ct WHERE ct.company_id = c.id AND (
       ct.name LIKE ? ESCAPE '\\' OR ct.title LIKE ? ESCAPE '\\' OR ct.email LIKE ? ESCAPE '\\'
       OR ct.notes LIKE ? ESCAPE '\\' OR ct.phone LIKE ? ESCAPE '\\'$phoneClause))
  OR EXISTS (SELECT 1 FROM meetings m WHERE m.company_id = c.id AND m.summary LIKE ? ESCAPE '\\')
  OR EXISTS (SELECT 1 FROM products p WHERE p.company_id = c.id AND (
       p.label LIKE ? ESCAPE '\\' OR p.insurer LIKE ? ESCAPE '\\' OR p.notes LIKE ? ESCAPE '\\' OR p.custom_line LIKE ? ESCAPE '\\'))
)''');
      args.addAll([like, like, like, like, like, like, like, like, like]);
      args.addAll(phoneNeedles.map((n) => '%$n%'));
      args.addAll([like, like, like, like, like]);
    }

    if (q.qualities.isNotEmpty || q.unrated) {
      final parts = <String>[];
      if (q.qualities.isNotEmpty) {
        parts.add('c.quality IN (${q.qualities.map((_) => '?').join(',')})');
        args.addAll(q.qualities.map((e) => e.db));
      }
      if (q.unrated) parts.add('c.quality IS NULL');
      where.add('(${parts.join(' OR ')})');
    }
    if (q.targetMonth != null) {
      where.add('c.target_month = ?');
      args.add(q.targetMonth);
    }
    if (q.line != null) {
      where.add('EXISTS (SELECT 1 FROM products p WHERE p.company_id = c.id AND p.line = ?)');
      args.add(q.line!.db);
    }

    final rows = _rows('''
SELECT c.*,
  (SELECT t.due_date FROM tasks t WHERE t.company_id = c.id AND t.status = 'pending'
     ORDER BY t.due_date, t.reminder_time LIMIT 1) AS next_due,
  (SELECT t.action FROM tasks t WHERE t.company_id = c.id AND t.status = 'pending'
     ORDER BY t.due_date, t.reminder_time LIMIT 1) AS next_action
FROM companies c
${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
''', args);

    // Products for all matched companies in a single query.
    final byCompany = <String, List<Product>>{};
    for (final r in _rows('SELECT * FROM products ORDER BY created_at')) {
      final p = Product.fromMap(r);
      (byCompany[p.companyId] ??= []).add(p);
    }

    var list = rows
        .map((r) => LeadRow(
              company: Company.fromMap(r),
              nextDue: r['next_due'] as String?,
              nextAction: r['next_action'] as String?,
              products: byCompany[r['id']] ?? const [],
              lineFilter: q.line,
            ))
        .toList();

    final t = Dates.toIso(today);
    switch (q.followUp) {
      case FollowUpFilter.any:
        break;
      case FollowUpFilter.overdue:
        list = list.where((r) => r.nextDue != null && r.nextDue!.compareTo(t) < 0).toList();
      case FollowUpFilter.today:
        list = list.where((r) => r.nextDue == t).toList();
      case FollowUpFilter.upcoming:
        list = list.where((r) => r.nextDue != null && r.nextDue!.compareTo(t) > 0).toList();
      case FollowUpFilter.none:
        list = list.where((r) => r.nextDue == null).toList();
    }

    int byName(LeadRow a, LeadRow b) =>
        a.company.name.toLowerCase().compareTo(b.company.name.toLowerCase());
    int nullsLast(String? a, String? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    switch (q.sort) {
      case LeadSort.nextFollowUp:
        list.sort((a, b) {
          final c = nullsLast(a.nextDue, b.nextDue);
          return c != 0 ? c : byName(a, b);
        });
      case LeadSort.latestUpdate:
        list.sort((a, b) => b.company.updatedAt.compareTo(a.company.updatedAt));
      case LeadSort.companyName:
        list.sort(byName);
      case LeadSort.nearestExpiry:
        list.sort((a, b) {
          final c = nullsLast(a.nearestExpiry(today), b.nearestExpiry(today));
          return c != 0 ? c : byName(a, b);
        });
    }
    return list;
  }

  // ---- the quick-entry commit ---------------------------------------------

  /// Saves a whole quick-entry form atomically. Only the company name is
  /// required. Editing never changes `created_at`; adding a meeting always
  /// inserts a new history row.
  CommitResult commitEntry(LeadEntry e, {String? draftKey}) {
    final name = e.companyName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Company name is required');
    }
    return transaction(() {
      final stamp = now;
      final existing = getCompany(e.companyId);
      final createdCompany = existing == null;

      // Contacts created in the form.
      final contacts = <String, Contact>{};
      for (final c in e.newContacts) {
        final fresh = Contact(
          id: c.id,
          companyId: e.companyId,
          name: c.name,
          title: c.title,
          phone: c.phone,
          email: c.email,
          notes: c.notes,
          isDecisionMaker: c.isDecisionMaker,
          createdAt: stamp,
          updatedAt: stamp,
        );
        contacts[fresh.id] = fresh;
      }

      // Company row first so child foreign keys are valid.
      saveCompany(Company(
        id: e.companyId,
        name: name,
        location: e.location.trim(),
        trivia: e.trivia,
        rapportNotes: e.rapportEdits[''] ?? existing?.rapportNotes ?? '',
        quality: e.quality,
        targetMonth: e.targetMonth,
        createdAt: existing?.createdAt ?? stamp,
        updatedAt: stamp,
      ));

      for (final c in contacts.values) {
        saveContact(c);
      }

      // Rapport notes belong to the person they were typed against.
      // A draft may refer to a person deleted since it was saved; drop such
      // links instead of failing the whole save.
      String? alive(String? id) => id == null
          ? null
          : (contacts.containsKey(id) || getContact(id)?.companyId == e.companyId)
              ? id
              : null;
      final metId = alive(e.metContactId);
      final nextId = alive(e.effectiveNextContactId);
      for (final entry in e.rapportEdits.entries) {
        if (entry.key.isEmpty) continue;
        final c = contacts[entry.key] ?? getContact(entry.key);
        if (c != null && c.companyId == e.companyId && c.notes != entry.value) {
          saveContact(c.copyWith(notes: entry.value, updatedAt: stamp));
        }
      }

      // Products: upsert only when changed.
      final stored = {for (final p in productsFor(e.companyId)) p.id: p};
      for (final p in e.products) {
        final old = stored[p.id];
        if (old == null && e.loadedProductIds.contains(p.id)) {
          continue; // deleted elsewhere since this draft was saved
        }
        if (old == null) {
          saveProduct(Product(
            id: p.id,
            companyId: e.companyId,
            line: p.line,
            customLine: p.customLine,
            label: p.label,
            expiryDate: p.expiryDate,
            insurer: p.insurer,
            notes: p.notes,
            createdAt: stamp,
            updatedAt: stamp,
          ));
        } else if (!old.sameContent(p)) {
          saveProduct(p.copyWith(updatedAt: stamp));
        }
      }
      for (final id in e.removedProductIds) {
        db.execute('DELETE FROM products WHERE id = ? AND company_id = ?', [id, e.companyId]);
      }

      String? meetingId;
      if (e.shouldLogMeeting) {
        meetingId = newId();
        saveMeeting(Meeting(
          id: meetingId,
          companyId: e.companyId,
          contactId: metId,
          nextContactId: nextId,
          meetingAt: e.meetingAt,
          summary: e.summary,
          createdAt: stamp,
          updatedAt: stamp,
        ));
      }

      String? taskId;
      if (e.shouldCreateTask) {
        taskId = newId();
        final due = e.taskDue ?? Dates.toIso(Dates.addDays(Dates.dateOnly(stamp), 1));
        saveTask(FollowUpTask(
          id: taskId,
          companyId: e.companyId,
          contactId: nextId,
          meetingId: meetingId,
          action: e.taskAction.trim().isEmpty ? 'Follow up' : e.taskAction.trim(),
          dueDate: due,
          reminderTime: e.reminderOn ? e.reminderTime : null,
          createdAt: stamp,
          updatedAt: stamp,
        ));
      }

      if (draftKey != null) deleteDraft(draftKey);
      return CommitResult(
        companyId: e.companyId,
        meetingId: meetingId,
        taskId: taskId,
        createdCompany: createdCompany,
      );
    });
  }

  // ---- drafts --------------------------------------------------------------

  void saveDraft(String key, String json) => db.execute('''
INSERT INTO drafts (key, json, updated_at) VALUES (?,?,?)
ON CONFLICT(key) DO UPDATE SET json=excluded.json, updated_at=excluded.updated_at
''', [key, json, now.millisecondsSinceEpoch]);

  String? loadDraft(String key) {
    final r = db.select('SELECT json FROM drafts WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['json'] as String;
  }

  void deleteDraft(String key) =>
      db.execute('DELETE FROM drafts WHERE key = ?', [key]);

  /// (key, updatedAt) of every saved draft, newest first.
  List<({String key, DateTime updatedAt})> listDrafts() => db
      .select('SELECT key, updated_at FROM drafts ORDER BY updated_at DESC')
      .map((r) => (
            key: r['key'] as String,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
          ))
      .toList();

  // ---- settings ------------------------------------------------------------

  String? getSetting(String key) {
    final r = db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  void setSetting(String key, String value) => db.execute('''
INSERT INTO settings (key, value) VALUES (?,?)
ON CONFLICT(key) DO UPDATE SET value=excluded.value
''', [key, value]);

  Map<String, String> allSettings() => {
        for (final r in db.select('SELECT key, value FROM settings'))
          r['key'] as String: r['value'] as String
      };
}
