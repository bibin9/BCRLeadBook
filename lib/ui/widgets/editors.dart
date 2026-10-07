import 'package:flutter/material.dart';

import '../../core/contact_utils.dart';
import '../../core/dates.dart';
import '../../data/models.dart';
import '../../services/app_controller.dart';
import '../../services/reminder_service.dart';
import '../theme.dart';
import 'common.dart';

/// Bottom sheet that lifts above the keyboard and scrolls.
Future<T?> showFormSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: builder(ctx),
    ),
  );
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.saveLabel = 'Save',
    this.onDelete,
    this.deleteLabel = 'Delete',
  });
  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final String saveLabel;
  /// Return true when the item was deleted; the sheet then closes.
  final Future<bool> Function()? onDelete;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ...children,
          const SizedBox(height: 20),
          FilledButton(onPressed: onSave, child: Text(saveLabel)),
          if (onDelete != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
              onPressed: () async {
                if (await onDelete!() && context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline),
              label: Text(deleteLabel),
            ),
          ],
        ],
      ),
    );
  }
}

/// Quick date buttons + calendar. Value is `yyyy-MM-dd` or null.
class DateQuickPicker extends StatelessWidget {
  const DateQuickPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.today,
    this.label = 'Follow-up date',
  });
  final String? value;
  final ValueChanged<String?> onChanged;
  final DateTime today;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Dates.dateOnly(today);
    final quick = <(String, DateTime)>[
      ('Tomorrow', Dates.addDays(t, 1)),
      ('In 3 days', Dates.addDays(t, 3)),
      ('Next week', Dates.addDays(t, 7)),
      ('In 2 weeks', Dates.addDays(t, 14)),
      ('Next month', Dates.addMonths(t, 1)),
    ];
    // Next Mon..Fri, so "call him Thursday" is one tap.
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    DateTime nextWeekday(int weekday) {
      var d = Dates.addDays(t, 1);
      while (d.weekday != weekday) {
        d = Dates.addDays(d, 1);
      }
      return d;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: kInk)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < names.length; i++)
              ChoiceChip(
                label: Text('${names[i]} ${nextWeekday(i + 1).day}'),
                selected: value == Dates.toIso(nextWeekday(i + 1)),
                onSelected: (_) => onChanged(Dates.toIso(nextWeekday(i + 1))),
              ),
            for (final q in quick)
              ChoiceChip(
                label: Text(q.$1),
                selected: value == Dates.toIso(q.$2),
                onSelected: (_) => onChanged(Dates.toIso(q.$2)),
              ),
            ActionChip(
              avatar: const Icon(Icons.calendar_month, size: 18),
              label: Text(value == null
                  ? 'Pick a date'
                  : '${Dates.display(value)} (${dueLabel(value!, today)})'),
              onPressed: () async {
                final d = await pickDate(context,
                    initial: Dates.parseIso(value) ?? Dates.addDays(t, 1),
                    first: Dates.addDays(t, -365 * 2));
                if (d != null) onChanged(Dates.toIso(d));
              },
            ),
            if (value != null)
              ActionChip(
                avatar: const Icon(Icons.close, size: 18),
                label: const Text('No date'),
                onPressed: () => onChanged(null),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Remind me" switch + time (default from Settings, normally 9:00 AM).
class ReminderPicker extends StatelessWidget {
  const ReminderPicker({
    super.key,
    required this.enabled,
    required this.time,
    required this.onChanged,
  });
  final bool enabled;
  final String time;
  final void Function(bool enabled, String time) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Remind me'),
          subtitle: const Text('A private notification on your phone'),
          value: enabled,
          onChanged: (v) => onChanged(v, time),
        ),
        if (enabled)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alarm),
            title: const Text('Reminder time'),
            trailing: Text(Dates.displayTime(time),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kBlueDark)),
            onTap: () async {
              final t = await pickTime(context, time);
              if (t != null) onChanged(true, Dates.timeToString(t.hour, t.minute));
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Add / edit a contact. Only the name is required.
Future<Contact?> showContactSheet(
  BuildContext context, {
  required String companyId,
  Contact? existing,
  Future<bool> Function()? onDelete,
}) {
  return showFormSheet<Contact>(context, (ctx) => _ContactSheet(companyId: companyId, existing: existing, onDelete: onDelete));
}

class _ContactSheet extends StatefulWidget {
  const _ContactSheet({required this.companyId, this.existing, this.onDelete});
  final String companyId;
  final Contact? existing;
  final Future<bool> Function()? onDelete;

  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  late final name = TextEditingController(text: widget.existing?.name);
  late final title = TextEditingController(text: widget.existing?.title);
  late final phone = TextEditingController(text: widget.existing?.phone);
  late final email = TextEditingController(text: widget.existing?.email);
  late final notes = TextEditingController(text: widget.existing?.notes);
  late bool dm = widget.existing?.isDecisionMaker ?? false;
  String? nameError;

  @override
  void dispose() {
    for (final c in [name, title, phone, email, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (name.text.trim().isEmpty) {
      setState(() => nameError = 'Please enter a name');
      return;
    }
    final now = DateTime.now();
    final old = widget.existing;
    Navigator.pop(
      context,
      Contact(
        id: old?.id ?? newIdForContact(),
        companyId: widget.companyId,
        name: name.text.trim(),
        title: title.text.trim(),
        phone: phone.text.trim(),
        email: email.text.trim(),
        notes: notes.text,
        isDecisionMaker: dm,
        createdAt: old?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: widget.existing == null ? 'Add contact' : 'Edit contact',
      onSave: _save,
      onDelete: widget.onDelete,
      deleteLabel: 'Delete contact',
      children: [
        TextField(
          controller: name,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: 'Full name', errorText: nameError),
          onChanged: (_) {
            if (nameError != null) setState(() => nameError = null);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: title,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Job title (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Phone / WhatsApp (optional)',
            hintText: '+971 50 123 4567',
            helperText: phoneHintFor(phone.text) ?? 'Include the country code',
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.phone),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Email (optional)',
            helperText: ContactUtils.emailHint(email.text),
            prefixIcon: const Icon(Icons.email_outlined),
          ),
          onChanged: (_) => setState(() {}),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Decision-maker'),
          subtitle: const Text('Can approve the purchase'),
          value: dm,
          onChanged: (v) => setState(() => dm = v),
        ),
        TextField(
          controller: notes,
          minLines: 3,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Personal & rapport notes (optional)',
            hintText: 'Hobbies, family, coffee order, favourite team…',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

String newIdForContact() => newId();

// ---------------------------------------------------------------------------

/// Editable insurance product. Used inline in the entry form and inside a
/// bottom sheet on the company page.
class ProductFormCard extends StatefulWidget {
  const ProductFormCard({
    super.key,
    required this.product,
    required this.onChanged,
    this.onRemove,
    this.heading,
    this.embedded = true,
  });
  final Product product;
  final ValueChanged<Product> onChanged;
  final VoidCallback? onRemove;
  final String? heading;

  /// Wrap in a Card (inline) or not (inside a sheet).
  final bool embedded;

  @override
  State<ProductFormCard> createState() => _ProductFormCardState();
}

class _ProductFormCardState extends State<ProductFormCard> {
  late Product p = widget.product;
  late final custom = TextEditingController(text: p.customLine);
  late final label = TextEditingController(text: p.label);
  late final insurer = TextEditingController(text: p.insurer);
  late final notes = TextEditingController(text: p.notes);

  @override
  void dispose() {
    for (final c in [custom, label, insurer, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(Product np) {
    setState(() => p = np);
    widget.onChanged(np);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text(widget.heading ?? 'Insurance product',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          if (widget.onRemove != null)
            IconButton(
              tooltip: 'Remove this product',
              onPressed: widget.onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
        ]),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final l in ProductLine.values)
              ChoiceChip(
                label: Text(l.label),
                selected: p.line == l,
                onSelected: (_) => _set(p.copyWith(line: l)),
              ),
          ],
        ),
        if (p.line == ProductLine.other) ...[
          const SizedBox(height: 10),
          TextField(
            controller: custom,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Type of insurance (e.g. Cyber, Life)'),
            onChanged: (v) => _set(p.copyWith(customLine: v)),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: label,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Policy label (optional)',
            hintText: 'e.g. Staff plan, Fleet, Warehouse',
          ),
          onChanged: (v) => _set(p.copyWith(label: v)),
        ),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final d = await pickDate(
              context,
              initial: Dates.parseIso(p.expiryDate) ?? Dates.addMonths(app.today, 6),
              first: DateTime(app.today.year - 5),
              last: DateTime(app.today.year + 15),
              help: 'Current policy expiry',
            );
            if (d != null) _set(p.copyWith(expiryDate: Dates.toIso(d)));
          },
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Current policy expiry',
              suffixIcon: Icon(Icons.calendar_month),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.expiryDate == null ? 'Unknown (tap to set)' : Dates.display(p.expiryDate),
                    style: TextStyle(
                        fontSize: 16, color: p.expiryDate == null ? kMuted : kInk),
                  ),
                ),
                if (p.expiryDate != null) ExpiryBadge(p.expiryDate, app.today),
              ],
            ),
          ),
        ),
        if (p.expiryDate != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _set(p.copyWith(clearExpiry: true)),
              child: const Text('Expiry date unknown'),
            ),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: insurer,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Current insurer (optional)'),
          onChanged: (v) => _set(p.copyWith(insurer: v)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: notes,
          minLines: 2,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Notes about this product (optional)',
            alignLabelWithHint: true,
          ),
          onChanged: (v) => _set(p.copyWith(notes: v)),
        ),
      ],
    );
    if (!widget.embedded) return body;
    return Card(child: Padding(padding: const EdgeInsets.all(14), child: body));
  }
}

Product blankProduct(String companyId) {
  final now = DateTime.now();
  return Product(
    id: newId(),
    companyId: companyId,
    line: ProductLine.medical,
    createdAt: now,
    updatedAt: now,
  );
}

Future<Product?> showProductSheet(
  BuildContext context, {
  required String companyId,
  Product? existing,
  Future<bool> Function()? onDelete,
}) {
  return showFormSheet<Product>(context, (ctx) {
    var current = existing ?? blankProduct(companyId);
    return StatefulBuilder(builder: (ctx, _) {
      return SheetFrame(
        title: existing == null ? 'Add insurance product' : 'Edit insurance product',
        onSave: () => Navigator.pop(ctx, current),
        onDelete: onDelete,
        deleteLabel: 'Delete product',
        children: [
          ProductFormCard(
            embedded: false,
            heading: 'Details',
            product: current,
            onChanged: (p) => current = p,
          ),
        ],
      );
    });
  });
}

// ---------------------------------------------------------------------------

/// Add / edit a follow-up task. Returns true when saved.
Future<bool> showTaskSheet(
  BuildContext context, {
  required String companyId,
  FollowUpTask? existing,
  List<Contact> contacts = const [],
  List<Product> products = const [],
  String? presetContactId,
}) async {
  final r = await showFormSheet<bool>(
    context,
    (ctx) => _TaskSheet(
      companyId: companyId,
      existing: existing,
      contacts: contacts,
      products: products,
      presetContactId: presetContactId,
    ),
  );
  return r ?? false;
}

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({
    required this.companyId,
    this.existing,
    required this.contacts,
    required this.products,
    this.presetContactId,
  });
  final String companyId;
  final FollowUpTask? existing;
  final List<Contact> contacts;
  final List<Product> products;
  final String? presetContactId;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final action = TextEditingController(text: widget.existing?.action);
  String? due;
  late bool remind;
  late String time;
  String? contactId;
  String? productId;
  String? error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final app = AppScope.read(context);
    final e = widget.existing;
    due = e?.dueDate ?? Dates.toIso(Dates.addDays(app.today, 1));
    remind = e != null ? e.reminderTime != null : app.defaultReminderOn;
    time = e?.reminderTime ?? app.defaultReminderTime;
    contactId = e?.contactId ?? widget.presetContactId;
    productId = e?.productId;
    if (!widget.contacts.any((c) => c.id == contactId)) contactId = null;
    if (!widget.products.any((p) => p.id == productId)) productId = null;
  }

  @override
  void dispose() {
    action.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = action.text.trim();
    if (text.isEmpty) {
      setState(() => error = 'Please describe the next action');
      return;
    }
    final app = AppScope.read(context);
    final now = app.now;
    final old = widget.existing;
    final task = FollowUpTask(
      id: old?.id ?? newId(),
      seq: old?.seq,
      companyId: widget.companyId,
      contactId: contactId,
      productId: productId,
      meetingId: old?.meetingId,
      action: text,
      dueDate: due ?? Dates.toIso(Dates.addDays(app.today, 1)),
      reminderTime: remind ? time : null,
      status: old?.status ?? TaskStatus.pending,
      completedAt: old?.completedAt,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (remind) await requestReminderPermission(app, messenger);
    app.run(() => app.repo.upsertTask(task));
    nav.pop(true);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Saved'), duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return SheetFrame(
      title: widget.existing == null ? 'Add follow-up' : 'Edit follow-up',
      onSave: _save,
      children: [
        TextField(
          controller: action,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              labelText: 'Next action', hintText: 'e.g. Call to confirm quote', errorText: error),
          onChanged: (_) {
            if (error != null) setState(() => error = null);
          },
        ),
        const SizedBox(height: 16),
        DateQuickPicker(value: due, today: app.today, onChanged: (v) => setState(() => due = v)),
        const SizedBox(height: 8),
        ReminderPicker(
          enabled: remind,
          time: time,
          onChanged: (e, t) => setState(() {
            remind = e;
            time = t;
          }),
        ),
        if (widget.contacts.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: contactId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Linked contact (optional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('No specific contact')),
              for (final c in widget.contacts) DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => contactId = v),
          ),
        ],
        if (widget.products.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: productId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Linked product (optional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('No specific product')),
              for (final p in widget.products) DropdownMenuItem(value: p.id, child: Text(p.displayName)),
            ],
            onChanged: (v) => setState(() => productId = v),
          ),
        ],
      ],
    );
  }
}

/// Asks the OS for notification permission the first time a reminder is
/// used. If refused, the app carries on and still lists due tasks in-app.
Future<void> requestReminderPermission(AppController app, ScaffoldMessengerState messenger) async {
  final result = await app.reminders.ensurePermission();
  if (result == ReminderPermission.denied) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        duration: Duration(seconds: 5),
        content: Text(
            'Notifications are turned off, so no pop-up will appear. Your follow-up is saved and will still show in the Follow-ups tab.'),
      ));
  }
}

// ---------------------------------------------------------------------------

/// Edit company-level fields.
Future<Company?> showCompanySheet(BuildContext context, Company c) {
  return showFormSheet<Company>(context, (ctx) => _CompanySheet(company: c));
}

class _CompanySheet extends StatefulWidget {
  const _CompanySheet({required this.company});
  final Company company;

  @override
  State<_CompanySheet> createState() => _CompanySheetState();
}

class _CompanySheetState extends State<_CompanySheet> {
  late final name = TextEditingController(text: widget.company.name);
  late final location = TextEditingController(text: widget.company.location);
  late final trivia = TextEditingController(text: widget.company.trivia);
  late LeadQuality? quality = widget.company.quality;
  late String? month = widget.company.targetMonth;
  String? error;

  @override
  void dispose() {
    for (final c in [name, location, trivia]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: 'Edit company',
      onSave: () {
        if (name.text.trim().isEmpty) {
          setState(() => error = 'Company name is required');
          return;
        }
        Navigator.pop(
          context,
          widget.company.copyWith(
            name: name.text.trim(),
            location: location.text.trim(),
            trivia: trivia.text,
            quality: quality,
            clearQuality: quality == null,
            targetMonth: month,
            clearTargetMonth: month == null,
          ),
        );
      },
      children: [
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: 'Company name', errorText: error),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: location,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Location (optional)'),
        ),
        const SizedBox(height: 16),
        QualityPicker(value: quality, onChanged: (q) => setState(() => quality = q)),
        const SizedBox(height: 12),
        TargetMonthTile(
          value: month,
          onChanged: (m) => setState(() => month = m),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: trivia,
          minLines: 4,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Company trivia & context',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

/// Hot / Warm / Cold / Future. Tap the selected one again to un-select.
class QualityPicker extends StatelessWidget {
  const QualityPicker({super.key, required this.value, required this.onChanged});
  final LeadQuality? value;
  final ValueChanged<LeadQuality?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Lead quality', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final q in LeadQuality.values)
              ChoiceChip(
                label: Text(q.label),
                selected: value == q,
                selectedColor: QualityStyle.of(q).bg,
                labelStyle: Theme.of(context).chipTheme.labelStyle?.copyWith(
                      color: value == q ? QualityStyle.of(q).fg : kInk,
                      fontWeight: value == q ? FontWeight.w700 : FontWeight.w500,
                    ),
                checkmarkColor: QualityStyle.of(q).fg,
                onSelected: (_) => onChanged(value == q ? null : q),
              ),
          ],
        ),
        if (value == null)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Not chosen yet. You can set it later.',
                style: TextStyle(fontSize: 13, color: kMuted)),
          ),
      ],
    );
  }
}

class TargetMonthTile extends StatelessWidget {
  const TargetMonthTile({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final r = await pickMonthYear(context, value);
        if (r == null) return;
        onChanged(r.isEmpty ? null : r);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Target follow-up month',
          suffixIcon: Icon(Icons.calendar_view_month),
        ),
        child: Text(
          value == null ? 'Not set' : Dates.monthLabel(value),
          style: TextStyle(fontSize: 16, color: value == null ? kMuted : kInk),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Edit an existing meeting history entry.
Future<Meeting?> showMeetingSheet(
  BuildContext context, {
  required Meeting meeting,
  required List<Contact> contacts,
  Future<bool> Function()? onDelete,
}) {
  return showFormSheet<Meeting>(
      context, (ctx) => _MeetingSheet(meeting: meeting, contacts: contacts, onDelete: onDelete));
}

class _MeetingSheet extends StatefulWidget {
  const _MeetingSheet({required this.meeting, required this.contacts, this.onDelete});
  final Meeting meeting;
  final List<Contact> contacts;
  final Future<bool> Function()? onDelete;

  @override
  State<_MeetingSheet> createState() => _MeetingSheetState();
}

class _MeetingSheetState extends State<_MeetingSheet> {
  late final summary = TextEditingController(text: widget.meeting.summary);
  late DateTime at = widget.meeting.meetingAt;
  late String? met = widget.contacts.any((c) => c.id == widget.meeting.contactId) ? widget.meeting.contactId : null;
  late String? next = widget.contacts.any((c) => c.id == widget.meeting.nextContactId) ? widget.meeting.nextContactId : null;

  @override
  void dispose() {
    summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: 'Edit meeting',
      onSave: () => Navigator.pop(
        context,
        widget.meeting.copyWith(
          meetingAt: at,
          summary: summary.text,
          contactId: met,
          clearContact: met == null,
          nextContactId: next,
          clearNextContact: next == null,
        ),
      ),
      onDelete: widget.onDelete,
      deleteLabel: 'Delete this meeting',
      children: [
        MeetingDateTile(value: at, onChanged: (d) => setState(() => at = d)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: met,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Person met'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Not recorded')),
            for (final c in widget.contacts) DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => met = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: next,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Key contact for next call'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Not recorded')),
            for (final c in widget.contacts) DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => next = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: summary,
          minLines: 6,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Meeting summary & minor details',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

/// Date + time of a meeting (defaults to now; past dates allowed).
class MeetingDateTile extends StatelessWidget {
  const MeetingDateTile({super.key, required this.value, required this.onChanged});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final d = await pickDate(context,
                  initial: value, last: DateTime.now().add(const Duration(days: 365)), help: 'Meeting date');
              if (d != null) {
                onChanged(DateTime(d.year, d.month, d.day, value.hour, value.minute));
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Meeting date', suffixIcon: Icon(Icons.calendar_month)),
              child: Text(Dates.displayDate(value), style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final t = await showTimePicker(
                  context: context, initialTime: TimeOfDay(hour: value.hour, minute: value.minute));
              if (t != null) {
                onChanged(DateTime(value.year, value.month, value.day, t.hour, t.minute));
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Time', suffixIcon: Icon(Icons.access_time)),
              child: Text(Dates.displayTime(Dates.timeToString(value.hour, value.minute)),
                  style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ],
    );
  }
}
