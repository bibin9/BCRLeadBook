import 'dart:math';

import '../core/contact_utils.dart';

/// Stable random 128-bit identifier (hex). Generated on the device, so records
/// created offline never collide and survive backup/restore unchanged.
String newId() {
  final r = Random.secure();
  final b = StringBuffer();
  for (var i = 0; i < 16; i++) {
    b.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

DateTime _dt(Object? v) =>
    DateTime.fromMillisecondsSinceEpoch(v as int, isUtc: false);
int _ms(DateTime d) => d.millisecondsSinceEpoch;
String _s(Object? v) => (v as String?) ?? '';
String? _sn(Object? v) {
  final s = v as String?;
  return (s == null || s.isEmpty) ? null : s;
}

// ---------------------------------------------------------------------------

enum LeadQuality {
  hot('hot', 'Hot'),
  warm('warm', 'Warm'),
  cold('cold', 'Cold'),
  future('future', 'Future Follow-Up');

  const LeadQuality(this.db, this.label);
  final String db;
  final String label;

  static LeadQuality? fromDb(String? v) {
    for (final q in values) {
      if (q.db == v) return q;
    }
    return null;
  }
}

enum ProductLine {
  medical('medical', 'Medical'),
  motor('motor', 'Motor'),
  property('property', 'Property'),
  marine('marine', 'Marine'),
  liability('liability', 'Liability'),
  other('other', 'Other');

  const ProductLine(this.db, this.label);
  final String db;
  final String label;

  static ProductLine fromDb(String? v) {
    for (final p in values) {
      if (p.db == v) return p;
    }
    return ProductLine.other;
  }
}

enum TaskStatus {
  pending('pending', 'Pending'),
  completed('completed', 'Completed');

  const TaskStatus(this.db, this.label);
  final String db;
  final String label;

  static TaskStatus fromDb(String? v) =>
      v == 'completed' ? TaskStatus.completed : TaskStatus.pending;
}

// ---------------------------------------------------------------------------

class Company {
  const Company({
    required this.id,
    required this.name,
    this.location = '',
    this.trivia = '',
    this.rapportNotes = '',
    this.quality,
    this.targetMonth,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String location;

  /// "Company Trivia & Context" - kept across meetings.
  final String trivia;

  /// Rapport notes used only when no specific contact was chosen.
  final String rapportNotes;
  final LeadQuality? quality;

  /// Target follow-up month as `yyyy-MM`. Independent of task due dates.
  final String? targetMonth;
  final DateTime createdAt;
  final DateTime updatedAt;

  Company copyWith({
    String? name,
    String? location,
    String? trivia,
    String? rapportNotes,
    LeadQuality? quality,
    bool clearQuality = false,
    String? targetMonth,
    bool clearTargetMonth = false,
    DateTime? updatedAt,
  }) =>
      Company(
        id: id,
        name: name ?? this.name,
        location: location ?? this.location,
        trivia: trivia ?? this.trivia,
        rapportNotes: rapportNotes ?? this.rapportNotes,
        quality: clearQuality ? null : (quality ?? this.quality),
        targetMonth: clearTargetMonth ? null : (targetMonth ?? this.targetMonth),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory Company.fromMap(Map<String, Object?> m) => Company(
        id: m['id'] as String,
        name: m['name'] as String,
        location: _s(m['location']),
        trivia: _s(m['trivia']),
        rapportNotes: _s(m['rapport_notes']),
        quality: LeadQuality.fromDb(m['quality'] as String?),
        targetMonth: _sn(m['target_month']),
        createdAt: _dt(m['created_at']),
        updatedAt: _dt(m['updated_at']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'location': location,
        'trivia': trivia,
        'rapport_notes': rapportNotes,
        'quality': quality?.db,
        'target_month': targetMonth,
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
      };
}

class Contact {
  const Contact({
    required this.id,
    required this.companyId,
    required this.name,
    this.title = '',
    this.phone = '',
    this.email = '',
    this.notes = '',
    this.isDecisionMaker = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String name;
  final String title;
  final String phone;
  final String email;

  /// Personal & rapport notes about this person. Kept across meetings.
  final String notes;
  final bool isDecisionMaker;
  final DateTime createdAt;
  final DateTime updatedAt;

  Contact copyWith({
    String? name,
    String? title,
    String? phone,
    String? email,
    String? notes,
    bool? isDecisionMaker,
    DateTime? updatedAt,
  }) =>
      Contact(
        id: id,
        companyId: companyId,
        name: name ?? this.name,
        title: title ?? this.title,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        notes: notes ?? this.notes,
        isDecisionMaker: isDecisionMaker ?? this.isDecisionMaker,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory Contact.fromMap(Map<String, Object?> m) => Contact(
        id: m['id'] as String,
        companyId: m['company_id'] as String,
        name: m['name'] as String,
        title: _s(m['title']),
        phone: _s(m['phone']),
        email: _s(m['email']),
        notes: _s(m['notes']),
        isDecisionMaker: (m['is_decision_maker'] as int? ?? 0) == 1,
        createdAt: _dt(m['created_at']),
        updatedAt: _dt(m['updated_at']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'company_id': companyId,
        'name': name,
        'title': title,
        'phone': phone,
        'phone_norm': ContactUtils.digitsOnly(phone),
        'email': email,
        'notes': notes,
        'is_decision_maker': isDecisionMaker ? 1 : 0,
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
      };

  /// Same contact moved under another company (used when a draft for a new
  /// company is merged into an existing record).
  Contact withCompany(String newCompanyId) => Contact(
        id: id,
        companyId: newCompanyId,
        name: name,
        title: title,
        phone: phone,
        email: email,
        notes: notes,
        isDecisionMaker: isDecisionMaker,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  bool sameContent(Contact o) =>
      name == o.name &&
      title == o.title &&
      phone == o.phone &&
      email == o.email &&
      notes == o.notes &&
      isDecisionMaker == o.isDecisionMaker;
}

class Product {
  const Product({
    required this.id,
    required this.companyId,
    this.line = ProductLine.medical,
    this.customLine = '',
    this.label = '',
    this.expiryDate,
    this.insurer = '',
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final ProductLine line;
  final String customLine;

  /// Optional text to tell apart several policies of the same type.
  final String label;

  /// `yyyy-MM-dd`, or null when unknown. Never guessed.
  final String? expiryDate;
  final String insurer;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// "Medical", or the custom text for "Other".
  String get lineLabel =>
      line == ProductLine.other && customLine.trim().isNotEmpty
          ? customLine.trim()
          : line.label;

  /// "Medical - Staff plan"
  String get displayName =>
      label.trim().isEmpty ? lineLabel : '$lineLabel (${label.trim()})';

  Product copyWith({
    ProductLine? line,
    String? customLine,
    String? label,
    String? expiryDate,
    bool clearExpiry = false,
    String? insurer,
    String? notes,
    DateTime? updatedAt,
  }) =>
      Product(
        id: id,
        companyId: companyId,
        line: line ?? this.line,
        customLine: customLine ?? this.customLine,
        label: label ?? this.label,
        expiryDate: clearExpiry ? null : (expiryDate ?? this.expiryDate),
        insurer: insurer ?? this.insurer,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as String,
        companyId: m['company_id'] as String,
        line: ProductLine.fromDb(m['line'] as String?),
        customLine: _s(m['custom_line']),
        label: _s(m['label']),
        expiryDate: _sn(m['expiry_date']),
        insurer: _s(m['insurer']),
        notes: _s(m['notes']),
        createdAt: _dt(m['created_at']),
        updatedAt: _dt(m['updated_at']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'company_id': companyId,
        'line': line.db,
        'custom_line': customLine,
        'label': label,
        'expiry_date': expiryDate,
        'insurer': insurer,
        'notes': notes,
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
      };

  Product withCompany(String newCompanyId) => Product(
        id: id,
        companyId: newCompanyId,
        line: line,
        customLine: customLine,
        label: label,
        expiryDate: expiryDate,
        insurer: insurer,
        notes: notes,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  bool sameContent(Product o) =>
      line == o.line &&
      customLine == o.customLine &&
      label == o.label &&
      expiryDate == o.expiryDate &&
      insurer == o.insurer &&
      notes == o.notes;
}

class Meeting {
  const Meeting({
    required this.id,
    required this.companyId,
    this.contactId,
    this.nextContactId,
    required this.meetingAt,
    this.summary = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;

  /// Person met.
  final String? contactId;

  /// Key contact for the next call (may equal [contactId]).
  final String? nextContactId;
  final DateTime meetingAt;
  final String summary;
  final DateTime createdAt;
  final DateTime updatedAt;

  Meeting copyWith({
    String? contactId,
    bool clearContact = false,
    String? nextContactId,
    bool clearNextContact = false,
    DateTime? meetingAt,
    String? summary,
    DateTime? updatedAt,
  }) =>
      Meeting(
        id: id,
        companyId: companyId,
        contactId: clearContact ? null : (contactId ?? this.contactId),
        nextContactId:
            clearNextContact ? null : (nextContactId ?? this.nextContactId),
        meetingAt: meetingAt ?? this.meetingAt,
        summary: summary ?? this.summary,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory Meeting.fromMap(Map<String, Object?> m) => Meeting(
        id: m['id'] as String,
        companyId: m['company_id'] as String,
        contactId: _sn(m['contact_id']),
        nextContactId: _sn(m['next_contact_id']),
        meetingAt: _dt(m['meeting_at']),
        summary: _s(m['summary']),
        createdAt: _dt(m['created_at']),
        updatedAt: _dt(m['updated_at']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'company_id': companyId,
        'contact_id': contactId,
        'next_contact_id': nextContactId,
        'meeting_at': _ms(meetingAt),
        'summary': summary,
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
      };
}

class FollowUpTask {
  const FollowUpTask({
    required this.id,
    this.seq,
    required this.companyId,
    this.contactId,
    this.productId,
    this.meetingId,
    required this.action,
    required this.dueDate,
    this.reminderTime,
    this.status = TaskStatus.pending,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Database sequence number; doubles as the local notification id.
  final int? seq;
  final String companyId;
  final String? contactId;
  final String? productId;
  final String? meetingId;
  final String action;

  /// `yyyy-MM-dd`.
  final String dueDate;

  /// `HH:mm` local time, or null for no reminder.
  final String? reminderTime;
  final TaskStatus status;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPending => status == TaskStatus.pending;

  FollowUpTask copyWith({
    String? contactId,
    bool clearContact = false,
    String? productId,
    bool clearProduct = false,
    String? action,
    String? dueDate,
    String? reminderTime,
    bool clearReminder = false,
    TaskStatus? status,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? updatedAt,
  }) =>
      FollowUpTask(
        id: id,
        seq: seq,
        companyId: companyId,
        contactId: clearContact ? null : (contactId ?? this.contactId),
        productId: clearProduct ? null : (productId ?? this.productId),
        meetingId: meetingId,
        action: action ?? this.action,
        dueDate: dueDate ?? this.dueDate,
        reminderTime:
            clearReminder ? null : (reminderTime ?? this.reminderTime),
        status: status ?? this.status,
        completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory FollowUpTask.fromMap(Map<String, Object?> m) => FollowUpTask(
        id: m['id'] as String,
        seq: m['seq'] as int?,
        companyId: m['company_id'] as String,
        contactId: _sn(m['contact_id']),
        productId: _sn(m['product_id']),
        meetingId: _sn(m['meeting_id']),
        action: m['action'] as String,
        dueDate: m['due_date'] as String,
        reminderTime: _sn(m['reminder_time']),
        status: TaskStatus.fromDb(m['status'] as String?),
        completedAt:
            m['completed_at'] == null ? null : _dt(m['completed_at']),
        createdAt: _dt(m['created_at']),
        updatedAt: _dt(m['updated_at']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'company_id': companyId,
        'contact_id': contactId,
        'product_id': productId,
        'meeting_id': meetingId,
        'action': action,
        'due_date': dueDate,
        'reminder_time': reminderTime,
        'status': status.db,
        'completed_at': completedAt == null ? null : _ms(completedAt!),
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
      };
}

/// A task together with the company it belongs to (for cross-company lists).
class TaskWithCompany {
  const TaskWithCompany(this.task, this.companyName);
  final FollowUpTask task;
  final String companyName;
}

/// A product together with its company name (renewal tracking).
class ProductWithCompany {
  const ProductWithCompany(this.product, this.companyName);
  final Product product;
  final String companyName;
}
