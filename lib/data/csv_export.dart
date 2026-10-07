import 'package:intl/intl.dart';

import 'models.dart';
import 'repository.dart';

/// CSV export for Excel / Google Sheets.
///
/// One CSV cannot hold several products and contacts per company without
/// either losing data or inventing a column layout, so the export is a small
/// set of related files that share `company_id`:
///
/// * `leads_overview.csv` - one row per company. Contacts, products and
///   follow-ups are also summarised in readable text columns, so the file is
///   useful on its own.
/// * `contacts.csv`  - one row per contact.
/// * `products.csv`  - one row per insurance product (policy).
/// * `meetings.csv`  - one row per dated meeting history entry.
/// * `follow_ups.csv` - one row per follow-up task.
///
/// Files are UTF-8 with a byte-order mark so Excel shows non-English names
/// correctly. Personal & rapport notes are left out unless asked for.
class CsvExport {
  CsvExport(this.repo);
  final Repository repo;

  static final DateFormat _stamp = DateFormat('yyyy-MM-dd HH:mm');

  /// Quotes a field and neutralises spreadsheet formulas (CSV injection).
  /// Phone-like values starting with + or - are left alone so international
  /// numbers survive.
  static String cell(Object? v) {
    var s = v == null ? '' : v.toString();
    if (s.isNotEmpty) {
      final c = s[0];
      final phoneLike = RegExp(r'^[+\-][0-9\s().\-]+$').hasMatch(s);
      if ((c == '=' || c == '@' || c == '\t' || c == '\r') ||
          ((c == '+' || c == '-') && !phoneLike)) {
        s = "'$s";
      }
    }
    if (s.contains(RegExp(r'[",\r\n]'))) {
      s = '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String toCsv(List<String> header, List<List<Object?>> rows) {
    final b = StringBuffer('\u{FEFF}');
    b.write('${header.map(cell).join(',')}\r\n');
    for (final r in rows) {
      b.write('${r.map(cell).join(',')}\r\n');
    }
    return b.toString();
  }

  static String _ts(DateTime d) => _stamp.format(d);

  /// Returns file name -> CSV text.
  Map<String, String> build({required bool includeRapport}) {
    final companies = repo.db
        .select('SELECT * FROM companies ORDER BY name COLLATE NOCASE')
        .map((r) => Company.fromMap(Map<String, Object?>.from(r)))
        .toList();
    final names = {for (final c in companies) c.id: c.name};

    List<T> all<T>(String sql, T Function(Map<String, Object?>) f) =>
        repo.db.select(sql).map((r) => f(Map<String, Object?>.from(r))).toList();

    final contacts = all('SELECT * FROM contacts ORDER BY company_id, name COLLATE NOCASE', Contact.fromMap);
    final products = all('SELECT * FROM products ORDER BY company_id, created_at', Product.fromMap);
    final meetings = all('SELECT * FROM meetings ORDER BY company_id, meeting_at DESC', Meeting.fromMap);
    final tasks = all('SELECT * FROM tasks ORDER BY company_id, due_date', FollowUpTask.fromMap);

    final contactName = {for (final c in contacts) c.id: c.name};
    final productName = {for (final p in products) p.id: p.displayName};

    final contactsBy = _group<Contact>(contacts, (c) => c.companyId);
    final productsBy = _group<Product>(products, (p) => p.companyId);
    final meetingsBy = _group<Meeting>(meetings, (m) => m.companyId);
    final tasksBy = _group<FollowUpTask>(tasks, (t) => t.companyId);

    // ---- overview ----
    final overviewHeader = [
      'company_id', 'company_name', 'location', 'lead_quality',
      'target_follow_up_month', 'next_follow_up_date', 'next_action',
      'pending_follow_ups', 'contact_count', 'contacts', 'product_count',
      'products', 'meeting_count', 'last_meeting', 'last_meeting_summary',
      'company_context', if (includeRapport) 'company_rapport_notes',
      'created', 'last_updated',
    ];
    final overview = <List<Object?>>[];
    for (final c in companies) {
      final cs = contactsBy[c.id] ?? [];
      final ps = productsBy[c.id] ?? [];
      final ms = meetingsBy[c.id] ?? [];
      final ts = (tasksBy[c.id] ?? []).where((t) => t.isPending).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      overview.add([
        c.id, c.name, c.location, c.quality?.label ?? '',
        c.targetMonth ?? '',
        ts.isEmpty ? '' : ts.first.dueDate,
        ts.isEmpty ? '' : ts.first.action,
        ts.length,
        cs.length,
        cs
            .map((x) => [
                  x.name,
                  if (x.title.isNotEmpty) '(${x.title})',
                  if (x.phone.isNotEmpty) x.phone,
                  if (x.email.isNotEmpty) x.email,
                  if (x.isDecisionMaker) '[decision-maker]',
                ].join(' '))
            .join(' | '),
        ps.length,
        ps
            .map((p) => [
                  p.displayName,
                  'expires ${p.expiryDate ?? 'unknown'}',
                  if (p.insurer.isNotEmpty) 'insurer ${p.insurer}',
                ].join(', '))
            .join(' | '),
        ms.length,
        ms.isEmpty ? '' : _ts(ms.first.meetingAt),
        ms.isEmpty ? '' : ms.first.summary,
        c.trivia,
        if (includeRapport) c.rapportNotes,
        _ts(c.createdAt), _ts(c.updatedAt),
      ]);
    }

    final contactRows = [
      for (final c in contacts)
        [
          c.id, c.companyId, names[c.companyId] ?? '', c.name, c.title,
          c.phone, c.email, c.isDecisionMaker ? 'Yes' : 'No',
          if (includeRapport) c.notes,
          _ts(c.createdAt), _ts(c.updatedAt),
        ]
    ];
    final productRows = [
      for (final p in products)
        [
          p.id, p.companyId, names[p.companyId] ?? '', p.line.label,
          p.line == ProductLine.other ? p.customLine : '', p.label,
          p.expiryDate ?? '', p.insurer, p.notes,
          _ts(p.createdAt), _ts(p.updatedAt),
        ]
    ];
    final meetingRows = [
      for (final m in meetings)
        [
          m.id, m.companyId, names[m.companyId] ?? '', _ts(m.meetingAt),
          contactName[m.contactId] ?? '', contactName[m.nextContactId] ?? '',
          m.summary, _ts(m.createdAt), _ts(m.updatedAt),
        ]
    ];
    final taskRows = [
      for (final t in tasks)
        [
          t.id, t.companyId, names[t.companyId] ?? '', t.action, t.dueDate,
          t.reminderTime ?? '', t.status.label,
          t.completedAt == null ? '' : _ts(t.completedAt!),
          contactName[t.contactId] ?? '', productName[t.productId] ?? '',
          _ts(t.createdAt), _ts(t.updatedAt),
        ]
    ];

    // One row per policy with the person to call: the renewal worklist.
    final renewalRows = <List<Object?>>[];
    final withExpiry = products.where((p) => p.expiryDate != null).toList()
      ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
    for (final p in withExpiry) {
      final cs = contactsBy[p.companyId] ?? [];
      Contact? who;
      for (final c in cs) {
        if (c.isDecisionMaker) who = c;
      }
      who ??= cs.isEmpty ? null : cs.first;
      renewalRows.add([
        names[p.companyId] ?? '', p.line.label,
        p.line == ProductLine.other ? p.customLine : '', p.label,
        p.expiryDate, p.insurer, who?.name ?? '', who?.phone ?? '',
        who?.email ?? '', p.notes, p.companyId, p.id,
      ]);
    }

    return {
      'leads_overview.csv': toCsv(overviewHeader, overview),
      'renewals.csv': toCsv([
        'company_name', 'product_line', 'other_line_text', 'policy_label',
        'expiry_date', 'current_insurer', 'contact_name', 'contact_phone',
        'contact_email', 'notes', 'company_id', 'product_id',
      ], renewalRows),
      'contacts.csv': toCsv([
        'contact_id', 'company_id', 'company_name', 'full_name', 'job_title',
        'phone', 'email', 'decision_maker',
        if (includeRapport) 'rapport_notes', 'created', 'last_updated',
      ], contactRows),
      'products.csv': toCsv([
        'product_id', 'company_id', 'company_name', 'product_line',
        'other_line_text', 'policy_label', 'expiry_date', 'current_insurer',
        'notes', 'created', 'last_updated',
      ], productRows),
      'meetings.csv': toCsv([
        'meeting_id', 'company_id', 'company_name', 'meeting_date_time',
        'person_met', 'next_call_contact', 'meeting_summary', 'created',
        'last_updated',
      ], meetingRows),
      'follow_ups.csv': toCsv([
        'follow_up_id', 'company_id', 'company_name', 'next_action',
        'due_date', 'reminder_time', 'status', 'completed_at',
        'linked_contact', 'linked_product', 'created', 'last_updated',
      ], taskRows),
    };
  }
}

Map<String, List<T>> _group<T>(List<T> items, String Function(T) key) {
  final m = <String, List<T>>{};
  for (final i in items) {
    (m[key(i)] ??= []).add(i);
  }
  return m;
}

/// Plain-text description shipped alongside the CSV files.
const String csvReadme = '''BCR LeadBook CSV export

Files share the column company_id, so they can be joined in Excel / Sheets.
  renewals.csv        renewal worklist: one row per policy with a known expiry date, soonest first, with the contact to call
  leads_overview.csv  one row per company (with readable summaries of contacts, products, next follow-up)
  contacts.csv        one row per contact
  products.csv        one row per insurance product; expiry_date is blank when unknown
  meetings.csv        one row per dated meeting entry
  follow_ups.csv      one row per follow-up task (status Pending / Completed)

Dates are yyyy-MM-dd; date-times are in the phone's local time.
Text beginning with = or @ is prefixed with an apostrophe so spreadsheets do not run it as a formula.
Personal & rapport notes are only included if you chose to include them.
''';
