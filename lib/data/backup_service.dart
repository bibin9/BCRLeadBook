import 'dart:convert';

import 'models.dart';
import 'repository.dart';

const String backupFormat = 'bcr-leadbook-backup';

/// Version of the backup *file* format (separate from the database schema).
/// Increase it when the JSON layout changes and teach [BackupService.parse]
/// how to read older versions.
const int backupVersion = 1;

/// Setting keys that travel with a backup. Machine-specific flags (such as
/// "permission already asked") deliberately do not.
const List<String> backedUpSettings = [
  'reminder_default_time',
  'reminder_default_on',
  'notif_show_company',
];

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupData {
  BackupData({
    required this.createdAt,
    required this.companies,
    required this.contacts,
    required this.products,
    required this.meetings,
    required this.tasks,
    required this.settings,
  });

  final DateTime? createdAt;
  final List<Company> companies;
  final List<Contact> contacts;
  final List<Product> products;
  final List<Meeting> meetings;
  final List<FollowUpTask> tasks;
  final Map<String, String> settings;

  String get summary =>
      '${companies.length} companies, ${contacts.length} contacts, '
      '${products.length} products, ${meetings.length} meetings, '
      '${tasks.length} follow-ups';
}

class BackupService {
  BackupService(this.repo);
  final Repository repo;

  /// Serialises every record to a versioned JSON document.
  String createBackup() {
    List<Map<String, Object?>> dump(String sql, Map<String, Object?> Function(Map<String, Object?>) fix) =>
        repo.db
            .select(sql)
            .map((r) => fix(Map<String, Object?>.from(r)))
            .toList();
    Map<String, Object?> keep(Map<String, Object?> m) => m;

    final companies = dump('SELECT * FROM companies ORDER BY created_at, id', keep);
    final contacts = dump('SELECT * FROM contacts ORDER BY created_at, id', (m) => m..remove('phone_norm'));
    final products = dump('SELECT * FROM products ORDER BY created_at, id', keep);
    final meetings = dump('SELECT * FROM meetings ORDER BY created_at, id', keep);
    final tasks = dump('SELECT * FROM tasks ORDER BY seq', (m) => m..remove('seq'));
    final settings = <String, String>{
      for (final e in repo.allSettings().entries)
        if (backedUpSettings.contains(e.key)) e.key: e.value
    };
    final doc = <String, Object?>{
      'format': backupFormat,
      'version': backupVersion,
      'app': 'BCR LeadBook',
      'created_at': repo.now.toUtc().toIso8601String(),
      'counts': {
        'companies': companies.length,
        'contacts': contacts.length,
        'products': products.length,
        'meetings': meetings.length,
        'tasks': tasks.length,
      },
      'companies': companies,
      'contacts': contacts,
      'products': products,
      'meetings': meetings,
      'tasks': tasks,
      'settings': settings,
    };
    return const JsonEncoder.withIndent(' ').convert(doc);
  }

  /// Parses and validates a backup file. Throws [BackupException] with a
  /// plain-English reason; nothing in the database is touched.
  BackupData parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text.startsWith('﻿') ? text.substring(1) : text);
    } catch (_) {
      throw BackupException(
          'This file is not a BCR LeadBook backup (it is not valid JSON).');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != backupFormat) {
      throw BackupException('This file is not a BCR LeadBook backup.');
    }
    final Map<String, dynamic> doc = decoded;
    final version = doc['version'];
    if (version is! int) {
      throw BackupException('The backup has no version number.');
    }
    if (version > backupVersion) {
      throw BackupException(
          'This backup was made by a newer version of the app (format $version). Please update BCR LeadBook, then try again.');
    }
    if (version < 1) throw BackupException('Unsupported backup version.');

    List<T> read<T>(String key, T Function(Map<String, Object?>) build) {
      final raw = doc[key];
      if (raw is! List) throw BackupException('The backup is missing "$key".');
      final out = <T>[];
      for (var i = 0; i < raw.length; i++) {
        try {
          out.add(build(Map<String, Object?>.from(raw[i] as Map)));
        } catch (_) {
          throw BackupException('Record ${i + 1} in "$key" is damaged.');
        }
      }
      return out;
    }

    final companies = read('companies', Company.fromMap);
    final contacts = read('contacts', Contact.fromMap);
    final products = read('products', Product.fromMap);
    final meetings = read('meetings', Meeting.fromMap);
    final tasks = read('tasks', FollowUpTask.fromMap);

    final counts = doc['counts'];
    if (counts is Map) {
      final expected = {
        'companies': companies.length,
        'contacts': contacts.length,
        'products': products.length,
        'meetings': meetings.length,
        'tasks': tasks.length,
      };
      for (final e in expected.entries) {
        if (counts[e.key] != null && counts[e.key] != e.value) {
          throw BackupException(
              'The backup looks incomplete: expected ${counts[e.key]} ${e.key} but found ${e.value}.');
        }
      }
    }

    // Referential integrity: no orphaned records, no duplicate ids.
    void unique(Iterable<String> ids, String what) {
      final seen = <String>{};
      for (final id in ids) {
        if (!seen.add(id)) throw BackupException('Duplicate $what id in backup.');
      }
    }

    unique(companies.map((e) => e.id), 'company');
    unique(contacts.map((e) => e.id), 'contact');
    unique(products.map((e) => e.id), 'product');
    unique(meetings.map((e) => e.id), 'meeting');
    unique(tasks.map((e) => e.id), 'task');

    final companyIds = companies.map((e) => e.id).toSet();
    final contactCompany = {for (final c in contacts) c.id: c.companyId};
    final productCompany = {for (final p in products) p.id: p.companyId};
    final meetingIds = meetings.map((e) => e.id).toSet();

    for (final c in contacts) {
      if (!companyIds.contains(c.companyId)) {
        throw BackupException('A contact refers to a company that is not in the backup.');
      }
    }
    for (final p in products) {
      if (!companyIds.contains(p.companyId)) {
        throw BackupException('A product refers to a company that is not in the backup.');
      }
    }
    for (final m in meetings) {
      if (!companyIds.contains(m.companyId)) {
        throw BackupException('A meeting refers to a company that is not in the backup.');
      }
      for (final id in [m.contactId, m.nextContactId]) {
        if (id != null && contactCompany[id] != m.companyId) {
          throw BackupException('A meeting refers to a contact that is not in the backup.');
        }
      }
    }
    for (final t in tasks) {
      if (!companyIds.contains(t.companyId)) {
        throw BackupException('A follow-up refers to a company that is not in the backup.');
      }
      if (t.contactId != null && contactCompany[t.contactId] != t.companyId) {
        throw BackupException('A follow-up refers to a contact that is not in the backup.');
      }
      if (t.productId != null && productCompany[t.productId] != t.companyId) {
        throw BackupException('A follow-up refers to a product that is not in the backup.');
      }
      if (t.meetingId != null && !meetingIds.contains(t.meetingId)) {
        throw BackupException('A follow-up refers to a meeting that is not in the backup.');
      }
    }

    final rawSettings = doc['settings'];
    final settings = <String, String>{};
    if (rawSettings is Map) {
      for (final k in backedUpSettings) {
        final v = rawSettings[k];
        if (v is String) settings[k] = v;
      }
    }

    DateTime? created;
    final c = doc['created_at'];
    if (c is String) created = DateTime.tryParse(c)?.toLocal();

    return BackupData(
      createdAt: created,
      companies: companies,
      contacts: contacts,
      products: products,
      meetings: meetings,
      tasks: tasks,
      settings: settings,
    );
  }

  /// Replaces ALL current data with [data] in one transaction. If anything
  /// fails the existing data is left exactly as it was.
  void restore(BackupData data) {
    repo.transaction(() {
      final db = repo.db;
      for (final t in ['tasks', 'meetings', 'products', 'contacts', 'companies', 'drafts']) {
        db.execute('DELETE FROM $t');
      }
      for (final c in data.companies) {
        repo.saveCompany(c);
      }
      for (final c in data.contacts) {
        repo.saveContact(c);
      }
      for (final p in data.products) {
        repo.saveProduct(p);
      }
      for (final m in data.meetings) {
        repo.saveMeeting(m);
      }
      for (final t in data.tasks) {
        repo.saveTask(t);
      }
      for (final e in data.settings.entries) {
        repo.setSetting(e.key, e.value);
      }
    });
  }
}
