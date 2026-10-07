import 'dart:convert';

import 'models.dart';

/// Everything the quick-entry form edits, in one serialisable object.
///
/// It doubles as the *draft* format: the form autosaves it as JSON so an
/// unfinished entry can be resumed after the app is closed.
class LeadEntry {
  LeadEntry({
    String? companyId,
    this.companyName = '',
    this.location = '',
    this.trivia = '',
    this.quality,
    this.targetMonth,
    DateTime? meetingAt,
    this.metContactId,
    this.nextSameAsMet = true,
    this.nextContactId,
    List<Contact>? newContacts,
    Map<String, String>? rapportEdits,
    List<Product>? products,
    Set<String>? removedProductIds,
    this.summary = '',
    this.taskAction = '',
    this.taskDue,
    this.reminderOn = true,
    this.reminderTime = '09:00',
    this.addingToExisting = false,
  })  : companyId = companyId ?? newId(),
        meetingAt = meetingAt ?? DateTime.now(),
        newContacts = newContacts ?? [],
        rapportEdits = rapportEdits ?? {},
        products = products ?? [],
        removedProductIds = removedProductIds ?? {};

  /// Always set: pre-generated for a brand-new company so contacts/products
  /// created in the form can reference it before it is saved.
  String companyId;

  /// True when the form was opened from an existing company (Add Meeting).
  /// A meeting history entry is then always created.
  bool addingToExisting;

  String companyName;
  String location;
  String trivia;
  LeadQuality? quality;
  String? targetMonth;

  DateTime meetingAt;
  String? metContactId;
  bool nextSameAsMet;
  String? nextContactId;

  /// Contacts created inside this form and not yet in the database.
  List<Contact> newContacts;

  /// Edited "Personal & Rapport Notes", keyed by contact id (or '' for the
  /// company when nobody was selected). Only entries the user actually
  /// changed are stored, so switching person met never loses typed text.
  Map<String, String> rapportEdits;

  /// All products shown in the form (existing + new).
  List<Product> products;
  Set<String> removedProductIds;

  String summary;

  String taskAction;
  String? taskDue;
  bool reminderOn;
  String reminderTime;

  String? get effectiveNextContactId =>
      nextSameAsMet ? metContactId : nextContactId;

  /// Has the user typed anything worth keeping as a draft?
  bool get hasContent =>
      companyName.trim().isNotEmpty ||
      location.trim().isNotEmpty ||
      trivia.trim().isNotEmpty ||
      quality != null ||
      targetMonth != null ||
      metContactId != null ||
      newContacts.isNotEmpty ||
      rapportEdits.isNotEmpty ||
      summary.trim().isNotEmpty ||
      taskAction.trim().isNotEmpty ||
      taskDue != null ||
      products.any((p) => !loadedProductIds.contains(p.id));

  /// Ids of products that already existed in the database when the form
  /// opened; anything else in [products] was added in this form.
  Set<String> loadedProductIds = {};

  /// A meeting history row is created when there is something to record.
  bool get shouldLogMeeting =>
      addingToExisting ||
      summary.trim().isNotEmpty ||
      metContactId != null ||
      effectiveNextContactId != null;

  bool get shouldCreateTask =>
      taskAction.trim().isNotEmpty || (taskDue != null && taskDue!.isNotEmpty);

  Map<String, Object?> toJson() => {
        'companyId': companyId,
        'addingToExisting': addingToExisting,
        'companyName': companyName,
        'location': location,
        'trivia': trivia,
        'quality': quality?.db,
        'targetMonth': targetMonth,
        'meetingAt': meetingAt.millisecondsSinceEpoch,
        'metContactId': metContactId,
        'nextSameAsMet': nextSameAsMet,
        'nextContactId': nextContactId,
        'newContacts': newContacts.map((c) => c.toMap()).toList(),
        'rapportEdits': rapportEdits,
        'products': products.map((p) => p.toMap()).toList(),
        'removedProductIds': removedProductIds.toList(),
        'loadedProductIds': loadedProductIds.toList(),
        'summary': summary,
        'taskAction': taskAction,
        'taskDue': taskDue,
        'reminderOn': reminderOn,
        'reminderTime': reminderTime,
      };

  String encode() => jsonEncode(toJson());

  static LeadEntry? tryDecode(String text) {
    try {
      final m = jsonDecode(text) as Map<String, dynamic>;
      return LeadEntry(
        companyId: m['companyId'] as String?,
        addingToExisting: m['addingToExisting'] as bool? ?? false,
        companyName: m['companyName'] as String? ?? '',
        location: m['location'] as String? ?? '',
        trivia: m['trivia'] as String? ?? '',
        quality: LeadQuality.fromDb(m['quality'] as String?),
        targetMonth: m['targetMonth'] as String?,
        meetingAt: DateTime.fromMillisecondsSinceEpoch(m['meetingAt'] as int),
        metContactId: m['metContactId'] as String?,
        nextSameAsMet: m['nextSameAsMet'] as bool? ?? true,
        nextContactId: m['nextContactId'] as String?,
        newContacts: ((m['newContacts'] as List?) ?? [])
            .map((e) => Contact.fromMap(Map<String, Object?>.from(e as Map)))
            .toList(),
        rapportEdits: Map<String, String>.from((m['rapportEdits'] as Map?) ?? {}),
        products: ((m['products'] as List?) ?? [])
            .map((e) => Product.fromMap(Map<String, Object?>.from(e as Map)))
            .toList(),
        removedProductIds:
            ((m['removedProductIds'] as List?) ?? []).cast<String>().toSet(),
        summary: m['summary'] as String? ?? '',
        taskAction: m['taskAction'] as String? ?? '',
        taskDue: m['taskDue'] as String?,
        reminderOn: m['reminderOn'] as bool? ?? true,
        reminderTime: m['reminderTime'] as String? ?? '09:00',
      )..loadedProductIds =
          ((m['loadedProductIds'] as List?) ?? []).cast<String>().toSet();
    } catch (_) {
      return null; // corrupt draft is ignored rather than crashing the app
    }
  }
}

class CommitResult {
  const CommitResult({
    required this.companyId,
    this.meetingId,
    this.taskId,
    required this.createdCompany,
  });
  final String companyId;
  final String? meetingId;
  final String? taskId;
  final bool createdCompany;
}
