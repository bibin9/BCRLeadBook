import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Thrown when the database file was written by a newer version of the app.
class DatabaseTooNewException implements Exception {
  DatabaseTooNewException(this.found, this.supported);
  final int found;
  final int supported;
  @override
  String toString() =>
      'This data was created by a newer version of BCR LeadBook '
      '(schema $found, this app supports $supported). Please update the app.';
}

typedef Migration = void Function(Database db);

/// Ordered migrations. `migrations[i]` upgrades schema version i to i+1.
/// NEVER edit a shipped migration; append a new one instead.
final List<Migration> migrations = [_v1];

int get currentSchemaVersion => migrations.length;

void _v1(Database db) {
  db.execute('''
CREATE TABLE companies (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  location TEXT NOT NULL DEFAULT '',
  trivia TEXT NOT NULL DEFAULT '',
  rapport_notes TEXT NOT NULL DEFAULT '',
  quality TEXT,
  target_month TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_companies_name ON companies(name COLLATE NOCASE);
CREATE INDEX idx_companies_updated ON companies(updated_at);

CREATE TABLE contacts (
  id TEXT PRIMARY KEY,
  company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  phone_norm TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  is_decision_maker INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_contacts_company ON contacts(company_id);

CREATE TABLE products (
  id TEXT PRIMARY KEY,
  company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  line TEXT NOT NULL,
  custom_line TEXT NOT NULL DEFAULT '',
  label TEXT NOT NULL DEFAULT '',
  expiry_date TEXT,
  insurer TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_products_company ON products(company_id);
CREATE INDEX idx_products_expiry ON products(expiry_date);

CREATE TABLE meetings (
  id TEXT PRIMARY KEY,
  company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  contact_id TEXT REFERENCES contacts(id) ON DELETE SET NULL,
  next_contact_id TEXT REFERENCES contacts(id) ON DELETE SET NULL,
  meeting_at INTEGER NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_meetings_company ON meetings(company_id, meeting_at);

CREATE TABLE tasks (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  contact_id TEXT REFERENCES contacts(id) ON DELETE SET NULL,
  product_id TEXT REFERENCES products(id) ON DELETE SET NULL,
  meeting_id TEXT REFERENCES meetings(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  due_date TEXT NOT NULL,
  reminder_time TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  completed_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_tasks_company ON tasks(company_id, status, due_date, reminder_time);
CREATE INDEX idx_tasks_status_due ON tasks(status, due_date);

CREATE TABLE drafts (
  key TEXT PRIMARY KEY,
  json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''');
}

/// Brings [db] up to [currentSchemaVersion]; each step is atomic.
void migrate(Database db) {
  final found = db.select('PRAGMA user_version').first.values.first as int;
  if (found > currentSchemaVersion) {
    throw DatabaseTooNewException(found, currentSchemaVersion);
  }
  for (var v = found; v < currentSchemaVersion; v++) {
    db.execute('BEGIN');
    try {
      migrations[v](db);
      db.execute('PRAGMA user_version = ${v + 1}');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}

Database _configure(Database db) {
  db.execute('PRAGMA foreign_keys = ON');
  migrate(db);
  return db;
}

Database openMemoryDatabase() => _configure(sqlite3.openInMemory());

Database openFileDatabase(String path) {
  final db = sqlite3.open(path);
  db.execute('PRAGMA journal_mode = WAL');
  return _configure(db);
}

/// Opens (creating if needed) the app database in the private documents
/// folder. Data lives only on this device.
Future<Database> openAppDatabase() async {
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  return openFileDatabase(p.join(dir.path, 'bcr_leadbook.db'));
}
