import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/name_match.dart';
import '../../data/lead_entry.dart';
import '../../data/models.dart';
import '../../services/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/editors.dart';
import 'company_screen.dart';

String draftKeyFor(String? companyId) => companyId == null ? 'new' : 'co:$companyId';

/// Builds a fresh entry: blank for a new lead, or pre-filled from an
/// existing company (the form is then an "Add Meeting" for that company).
LeadEntry buildBlankEntry(AppController app, {String? companyId}) {
  final e = LeadEntry(
    meetingAt: app.now,
    reminderOn: app.defaultReminderOn,
    reminderTime: app.defaultReminderTime,
  );
  if (companyId != null) {
    final b = app.repo.bundle(companyId);
    if (b != null) {
      e
        ..companyId = b.company.id
        ..addingToExisting = true
        ..companyName = b.company.name
        ..location = b.company.location
        ..trivia = b.company.trivia
        ..quality = b.company.quality
        ..targetMonth = b.company.targetMonth
        ..products = [...b.products]
        ..loadedProductIds = b.products.map((p) => p.id).toSet();
    }
  }
  return e;
}

/// Opens the quick-entry form. If an unfinished draft exists the user is
/// offered to resume it. Returns the saved company id (or null).
Future<String?> startEntry(BuildContext context, {String? companyId, bool resume = false}) async {
  final app = AppScope.read(context);
  final key = draftKeyFor(companyId);
  final blank = buildBlankEntry(app, companyId: companyId);
  var entry = blank;
  final raw = app.repo.loadDraft(key);
  final draft = raw == null ? null : LeadEntry.tryDecode(raw);
  if (draft != null) {
    var useDraft = resume;
    if (!resume) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Resume unfinished entry?'),
          content: Text(draft.companyName.trim().isEmpty
              ? 'You have an unfinished entry saved on this phone.'
              : 'You have an unfinished entry for "${draft.companyName.trim()}".'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'new'), child: const Text('Start fresh')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'resume'), child: const Text('Resume')),
          ],
        ),
      );
      if (choice == null) return null;
      useDraft = choice == 'resume';
    }
    if (useDraft) {
      entry = draft;
    } else {
      app.repo.deleteDraft(key);
    }
  }
  if (!context.mounted) return null;
  final id = await Navigator.of(context).push<String>(MaterialPageRoute(
    builder: (_) => EntryScreen(initial: entry, blankJson: blank.encode(), draftKey: key),
  ));
  if (id != null && companyId == null && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanyScreen(companyId: id)));
  }
  return id;
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key, required this.initial, required this.blankJson, required this.draftKey});
  final LeadEntry initial;
  final String blankJson;
  final String draftKey;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> with WidgetsBindingObserver {
  late LeadEntry e = widget.initial;
  late String draftKey = widget.draftKey;
  final scroll = ScrollController();

  late final name = TextEditingController(text: e.companyName);
  late final location = TextEditingController(text: e.location);
  late final trivia = TextEditingController(text: e.trivia);
  late final summary = TextEditingController(text: e.summary);
  late final rapport = TextEditingController();
  late final action = TextEditingController(text: e.taskAction);

  List<Contact> existingContacts = [];
  Company? existingCompany;
  List<({String id, String name})> allNames = [];
  final Set<String> dismissedSimilar = {};
  List<({String id, String name})> similar = [];

  Timer? _draftTimer;
  Timer? _nameTimer;
  bool _saved = false;
  bool _saving = false;
  String? nameError;
  bool _init = false;
  bool _showMore = false;
  AppController? _app;

  AppController get app => _app ?? AppScope.read(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= AppScope.read(context);
    if (_init) return;
    _init = true;
    WidgetsBinding.instance.addObserver(this);
    allNames = app.repo.companyNames();
    _loadExisting();
    _showMore = e.location.isNotEmpty;
    _syncRapportBox();
    _updateSimilar();
  }

  void _loadExisting() {
    existingCompany = app.repo.getCompany(e.companyId);
    existingContacts = existingCompany == null ? [] : app.repo.contactsFor(e.companyId);
  }

  /// Save immediately when the app is sent to the background; the process
  /// may be killed before the autosave timer fires.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _draftTimer?.cancel();
      _flushDraft();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftTimer?.cancel();
    _nameTimer?.cancel();
    // Lists on other screens (e.g. the dashboard's draft card) must notice
    // that a draft was written or removed.
    final a = _app;
    if (a != null) Future.microtask(() => a.changed(resync: false));
    for (final c in [name, location, trivia, summary, rapport, action]) {
      c.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  List<Contact> get contacts => [...existingContacts, ...e.newContacts];

  Contact? contactById(String? id) {
    if (id == null) return null;
    for (final c in contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool get dirty => e.encode() != widget.blankJson;

  // ---- drafts --------------------------------------------------------------

  void _touch() {
    setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _flushDraft);
  }

  void _flushDraft() {
    if (_saved) return;
    try {
      if (dirty) {
        app.repo.saveDraft(draftKey, e.encode());
      } else {
        app.repo.deleteDraft(draftKey);
      }
    } catch (_) {
      // A failed autosave must never interrupt typing.
    }
  }

  Future<void> _onBack(bool didPop) async {
    if (didPop) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text(
            'Your work is kept as a draft on this phone, so you can resume it later. You can also discard it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'keep'), child: const Text('Keep draft & leave')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'edit'), child: const Text('Keep editing')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'discard') {
      _draftTimer?.cancel();
      app.repo.deleteDraft(draftKey);
      _saved = true;
      Navigator.of(context).pop();
    } else if (choice == 'keep') {
      _draftTimer?.cancel();
      _flushDraft();
      _saved = true;
      Navigator.of(context).pop();
    }
  }

  // ---- company name & similar suggestions ---------------------------------

  void _onNameChanged(String v) {
    e.companyName = v;
    if (nameError != null) nameError = null;
    _touch();
    _nameTimer?.cancel();
    _nameTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(_updateSimilar);
    });
  }

  void _updateSimilar() {
    if (e.addingToExisting || e.companyName.trim().length < 3) {
      similar = [];
      return;
    }
    similar = allNames
        .where((n) =>
            n.id != e.companyId &&
            !dismissedSimilar.contains(n.id) &&
            NameMatch.similar(e.companyName, n.name))
        .take(3)
        .toList();
  }

  /// Switch this form over to an existing company, keeping everything the
  /// user already typed.
  void _adoptExisting(String id) {
    final b = app.repo.bundle(id);
    if (b == null) return;
    final oldKey = draftKey;
    final oldId = e.companyId;
    setState(() {
      e.newContacts = e.newContacts.map((c) => c.withCompany(id)).toList();
      final mine = e.products.map((p) => p.withCompany(id)).toList();
      e.products = [...b.products, ...mine];
      e.loadedProductIds = b.products.map((p) => p.id).toSet();
      e.companyId = id;
      e.addingToExisting = true;
      e.companyName = b.company.name;
      name.text = b.company.name;
      if (e.location.trim().isEmpty) {
        e.location = b.company.location;
        location.text = b.company.location;
      }
      if (e.trivia.trim().isEmpty) {
        e.trivia = b.company.trivia;
        trivia.text = b.company.trivia;
      }
      final typedRapport = e.rapportEdits[''];
      if (typedRapport != null) {
        final old = b.company.rapportNotes.trim();
        e.rapportEdits[''] = old.isEmpty ? typedRapport : '${b.company.rapportNotes}\n$typedRapport';
      }
      e.quality ??= b.company.quality;
      e.targetMonth ??= b.company.targetMonth;
      draftKey = draftKeyFor(id);
      similar = [];
      _loadExisting();
      _syncRapportBox();
    });
    if (oldId != id) app.repo.deleteDraft(oldKey);
    _touch();
    showInfo(context, 'Opened the existing record for ${e.companyName}. Your notes are kept.');
  }

  // ---- contacts & rapport --------------------------------------------------

  String _rapportKey() => e.metContactId ?? '';

  String _rapportOriginal(String key) =>
      key.isEmpty ? (existingCompany?.rapportNotes ?? '') : (contactById(key)?.notes ?? '');

  void _syncRapportBox() {
    final key = _rapportKey();
    rapport.text = e.rapportEdits[key] ?? _rapportOriginal(key);
  }

  void _onRapportChanged(String v) {
    final key = _rapportKey();
    if (v == _rapportOriginal(key)) {
      e.rapportEdits.remove(key);
    } else {
      e.rapportEdits[key] = v;
    }
    _touch();
  }

  Future<void> _addContact({required bool forNext}) async {
    final c = await showContactSheet(context, companyId: e.companyId);
    if (c == null) return;
    setState(() {
      e.newContacts = [...e.newContacts, c];
      if (forNext) {
        e.nextContactId = c.id;
      } else {
        e.metContactId = c.id;
        _syncRapportBox();
      }
    });
    _touch();
  }

  Widget _contactDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    required VoidCallback onAdd,
    String emptyLabel = 'Not selected',
  }) {
    final v = contacts.any((c) => c.id == value) ? value : null;
    return DropdownButtonFormField<String?>(
      key: ValueKey('$label-${contacts.length}-$v'),
      initialValue: v,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem(value: null, child: Text(emptyLabel)),
        for (final c in contacts)
          DropdownMenuItem(
            value: c.id,
            child: Text(c.title.isEmpty ? c.name : '${c.name} · ${c.title}', overflow: TextOverflow.ellipsis),
          ),
        const DropdownMenuItem(
          value: '__add__',
          child: Row(children: [Icon(Icons.person_add, size: 20), SizedBox(width: 8), Text('Add new person…')]),
        ),
      ],
      onChanged: (x) {
        if (x == '__add__') {
          onAdd();
        } else {
          onChanged(x);
        }
      },
    );
  }

  // ---- products ------------------------------------------------------------

  void _addProduct() {
    setState(() => e.products = [...e.products, blankProduct(e.companyId)]);
    _touch();
  }

  Future<void> _removeProduct(Product p) async {
    final ok = await confirm(context,
        title: 'Remove this product?',
        message: '${p.displayName} will be removed from this company when you save.',
        confirmLabel: 'Remove',
        destructive: true);
    if (!ok) return;
    setState(() {
      e.products = e.products.where((x) => x.id != p.id).toList();
      if (e.loadedProductIds.contains(p.id)) e.removedProductIds.add(p.id);
    });
    _touch();
  }

  // ---- save ----------------------------------------------------------------

  Future<void> _save() async {
    if (_saving) return;
    if (e.companyName.trim().isEmpty) {
      setState(() => nameError = 'Please enter the company name');
      scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final a = app;
    _draftTimer?.cancel();
    try {
      // A new meeting usually means the earlier follow-ups were done.
      var closeIds = <String>[];
      if (e.addingToExisting) {
        final open = a.repo.tasksFor(e.companyId).where((t) => t.isPending).toList();
        if (open.isNotEmpty) {
          final picked = await _askCloseTasks(open);
          if (picked == null) {
            if (mounted) setState(() => _saving = false);
            return;
          }
          closeIds = picked;
        }
      }
      if (e.shouldCreateTask && e.reminderOn) {
        await requestReminderPermission(a, messenger);
      }
      final r = a.run(() {
        final res = a.repo.commitEntry(e, draftKey: draftKey);
        for (final id in closeIds) {
          a.repo.completeTask(id);
        }
        return res;
      });
      _saved = true;
      nav.pop(r.companyId);
      showSavedOn(messenger, 'Saved: ${e.companyName.trim()}');
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        showInfo(context, 'Sorry, that could not be saved. Your entry is still here. ($err)');
      }
    }
  }

  /// Returns ids to mark done, or null if the user went back to editing.
  Future<List<String>?> _askCloseTasks(List<FollowUpTask> open) {
    final today = Dates.toIso(app.today);
    final checked = {for (final t in open) t.id: t.dueDate.compareTo(today) <= 0};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Earlier follow-ups still open'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tick the ones this meeting took care of. They will be marked done.'),
              for (final t in open)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: checked[t.id],
                  onChanged: (v) => setS(() => checked[t.id] = v ?? false),
                  title: Text(t.action),
                  subtitle: Text(dueLabel(t.dueDate, app.today)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, [for (final e in checked.entries) if (e.value) e.key]),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- UI ------------------------------------------------------------------

  Widget _card(String title, IconData icon, List<Widget> children, {String? subtitle}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, color: kBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 13.5)),
              ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _noteField({
    required String title,
    required String hint,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    int minLines = 6,
    String? caption,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: kBlueDark)),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(caption, style: const TextStyle(fontSize: 13, color: kMuted)),
          ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint, alignLabelWithHint: true),
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final met = contactById(e.metContactId);
    final isNew = !e.addingToExisting;
    return PopScope(
      canPop: _saved || !dirty,
      onPopInvokedWithResult: (didPop, _) => _onBack(didPop),
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? 'Add Lead / Meeting' : 'Add Meeting'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            controller: scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _card('Company', Icons.business, [
                TextField(
                  controller: name,
                  autofocus: isNew && e.companyName.isEmpty,
                  readOnly: false,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Company name',
                    helperText: 'The only thing you must fill in',
                    errorText: nameError,
                  ),
                  onChanged: _onNameChanged,
                ),
                if (similar.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6E0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE9C46A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Already saved? A similar company exists:',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        for (final s in similar)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(children: [
                              Expanded(child: Text(s.name, style: const TextStyle(fontSize: 15.5))),
                              OutlinedButton(
                                onPressed: () => _adoptExisting(s.id),
                                child: const Text('Open it'),
                              ),
                            ]),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => setState(() {
                              dismissedSimilar.addAll(similar.map((s) => s.id));
                              similar = [];
                            }),
                            child: const Text('This is a different company'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                QualityPicker(
                  value: e.quality,
                  onChanged: (q) {
                    e.quality = q;
                    _touch();
                  },
                ),
                const SizedBox(height: 12),
                TargetMonthTile(
                  value: e.targetMonth,
                  onChanged: (m) {
                    e.targetMonth = m;
                    _touch();
                  },
                ),
                const SizedBox(height: 4),
                if (!_showMore)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showMore = true),
                      icon: const Icon(Icons.expand_more),
                      label: const Text('More company details (location)'),
                    ),
                  )
                else ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: location,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Company location (optional)'),
                    onChanged: (v) {
                      e.location = v;
                      _touch();
                    },
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              _card('Meeting & people', Icons.groups, [
                MeetingDateTile(
                  value: e.meetingAt,
                  onChanged: (d) {
                    e.meetingAt = d;
                    _touch();
                  },
                ),
                const SizedBox(height: 12),
                if (contacts.isEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _addContact(forNext: false),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add the person you met'),
                  )
                else
                  _contactDropdown(
                    label: 'Person met',
                    value: e.metContactId,
                    onChanged: (id) {
                      e.metContactId = id;
                      _syncRapportBox();
                      _touch();
                    },
                    onAdd: () => _addContact(forNext: false),
                  ),
                if (contacts.isNotEmpty || e.nextSameAsMet == false) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Next call is with the same person'),
                    value: e.nextSameAsMet,
                    onChanged: (v) {
                      e.nextSameAsMet = v;
                      _touch();
                    },
                  ),
                  if (!e.nextSameAsMet)
                    _contactDropdown(
                      label: 'Key contact for the next call',
                      value: e.nextContactId,
                      onChanged: (id) {
                        e.nextContactId = id;
                        _touch();
                      },
                      onAdd: () => _addContact(forNext: true),
                    ),
                ],
              ]),
              const SizedBox(height: 12),
              _card(
                'Insurance products',
                Icons.shield_outlined,
                subtitle: 'Optional. Each policy can have its own expiry date.',
                [
                  if (e.products.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('No products added yet.', style: TextStyle(color: kMuted)),
                    ),
                  for (final p in e.products)
                    Padding(
                      key: ValueKey(p.id),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _productTile(p),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addProduct,
                    icon: const Icon(Icons.add),
                    label: Text(e.products.isEmpty ? 'Add Product' : 'Add Another Product'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _card('Notes', Icons.edit_note, subtitle: 'Take your time. These are the details that win the next call.', [
                _noteField(
                  title: 'Meeting Summary & Minor Details',
                  hint: 'Discussion points, requirements, objections, promises made, agreed next steps, any small detail worth remembering…',
                  controller: summary,
                  minLines: 8,
                  onChanged: (v) {
                    e.summary = v;
                    _touch();
                  },
                ),
                const SizedBox(height: 20),
                _noteField(
                  title: 'Personal & Rapport Notes',
                  caption: met == null
                      ? 'Saved with the company. Choose the person met to attach them to that person.'
                      : 'About ${met.name}. Kept for every future meeting.',
                  hint: 'Hobbies, family mentions, coffee preference, favourite team, recent trips…',
                  controller: rapport,
                  minLines: 5,
                  onChanged: _onRapportChanged,
                ),
                const SizedBox(height: 20),
                _noteField(
                  title: 'Company Trivia & Context',
                  caption: 'Kept with the company across meetings.',
                  hint: 'Expansion plans, new locations, business challenges, company news…',
                  controller: trivia,
                  minLines: 5,
                  onChanged: (v) {
                    e.trivia = v;
                    _touch();
                  },
                ),
              ]),
              const SizedBox(height: 12),
              _card('Next action', Icons.event_available, [
                TextField(
                  controller: action,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Next action required',
                    hintText: 'e.g. Send three quotes',
                  ),
                  onChanged: (v) {
                    e.taskAction = v;
                    _touch();
                  },
                ),
                const SizedBox(height: 14),
                DateQuickPicker(
                  value: e.taskDue,
                  today: app.today,
                  onChanged: (d) {
                    e.taskDue = d;
                    _touch();
                  },
                ),
                if (e.taskAction.trim().isNotEmpty && e.taskDue == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('No date chosen: tomorrow will be used.',
                        style: TextStyle(fontSize: 13, color: kMuted)),
                  ),
                const SizedBox(height: 4),
                ReminderPicker(
                  enabled: e.reminderOn,
                  time: e.reminderTime,
                  onChanged: (on, t) {
                    e.reminderOn = on;
                    e.reminderTime = t;
                    _touch();
                  },
                ),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: const Text('Save'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              const SizedBox(height: 12),
              const Signature(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _productTile(Product p) {
    final isNewProduct = !e.loadedProductIds.contains(p.id);
    return Card(
      color: kBlueSoft.withValues(alpha: 0.5),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('tile-${p.id}'),
          initiallyExpanded: isNewProduct,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(p.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(p.expiryDate == null
              ? 'Expiry unknown'
              : 'Expires ${Dates.display(p.expiryDate)} · ${expiryInfo(p.expiryDate, app.today).label}'),
          children: [
            ProductFormCard(
              embedded: false,
              heading: 'Details',
              product: p,
              onRemove: () => _removeProduct(p),
              onChanged: (np) {
                e.products = [for (final x in e.products) x.id == np.id ? np : x];
                _touch();
              },
            ),
          ],
        ),
      ),
    );
  }
}
