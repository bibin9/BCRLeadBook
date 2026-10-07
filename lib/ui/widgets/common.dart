import 'package:flutter/material.dart';

import '../../core/contact_utils.dart';
import '../../core/dates.dart';
import '../../data/models.dart';
import '../../services/app_controller.dart';
import '../../services/launcher.dart';
import '../theme.dart';

/// Re-runs [load] whenever data changes (AppController.revision) or
/// [cacheKey] changes; otherwise reuses the last result. SQLite reads are
/// synchronous and fast, so lists appear without a loading flicker.
class Live<T> extends StatefulWidget {
  const Live({
    super.key,
    required this.load,
    required this.builder,
    this.cacheKey,
  });

  final T Function(AppController app) load;
  final Widget Function(BuildContext context, T data) builder;
  final Object? cacheKey;

  @override
  State<Live<T>> createState() => _LiveState<T>();
}

class _LiveState<T> extends State<Live<T>> {
  int? _rev;
  Object? _key;
  T? _value;
  bool _has = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!_has || _rev != app.revision || _key != widget.cacheKey) {
      _value = widget.load(app);
      _rev = app.revision;
      _key = widget.cacheKey;
      _has = true;
    }
    return widget.builder(context, _value as T);
  }
}

class Signature extends StatelessWidget {
  const Signature({super.key, this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: kSignature,
      child: ExcludeSemantics(
        child: Text(
          kSignature,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: kMuted,
            fontSize: large ? 15 : 12.5,
            letterSpacing: 0.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.padding});
  final String title;
  final Widget? trailing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk)),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
       child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.blueGrey.shade300),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kInk)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: kMuted, height: 1.35)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
       ),
      ),
    );
  }
}

/// Small pill with colour AND text.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.fg, required this.bg, this.icon});
  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(text,
                style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class QualityBadge extends StatelessWidget {
  const QualityBadge(this.quality, {super.key, this.showUnrated = false});
  final LeadQuality? quality;
  final bool showUnrated;

  @override
  Widget build(BuildContext context) {
    if (quality == null && !showUnrated) return const SizedBox.shrink();
    final s = QualityStyle.of(quality);
    return Pill(s.label, fg: s.fg, bg: s.bg, icon: s.icon);
  }
}

class ExpiryBadge extends StatelessWidget {
  const ExpiryBadge(this.iso, this.today, {super.key});
  final String? iso;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final e = expiryInfo(iso, today);
    switch (e.state) {
      case ExpiryState.unknown:
        return const Pill('Expiry unknown', fg: kMuted, bg: Color(0xFFECEFF3));
      case ExpiryState.expired:
        return const Pill('Expired', fg: Color(0xFFB71C1C), bg: Color(0xFFFDE7E9), icon: Icons.error_outline);
      case ExpiryState.today:
        return const Pill('Expires today', fg: Color(0xFFB71C1C), bg: Color(0xFFFDE7E9), icon: Icons.schedule);
      case ExpiryState.upcoming:
        final soon = (e.days ?? 999) <= 30;
        return Pill(e.label,
            fg: soon ? const Color(0xFF8A3B00) : kSuccess,
            bg: soon ? const Color(0xFFFFEFD9) : kSuccessBg,
            icon: Icons.schedule);
    }
  }
}

class DuePill extends StatelessWidget {
  const DuePill(this.dueIso, this.today, {super.key});
  final String dueIso;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final b = followUpBucket(dueIso, today);
    final text = dueLabel(dueIso, today);
    return switch (b) {
      FollowUpBucket.overdue =>
        Pill(text, fg: const Color(0xFFB71C1C), bg: const Color(0xFFFDE7E9), icon: Icons.warning_amber_rounded),
      FollowUpBucket.today =>
        Pill(text, fg: const Color(0xFF8A3B00), bg: const Color(0xFFFFEFD9), icon: Icons.today),
      FollowUpBucket.upcoming => Pill(text, fg: kBlueDark, bg: kBlueSoft, icon: Icons.event),
    };
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel)),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E))
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

void showInfo(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

/// Clear "Saved" confirmation.
void showSaved(BuildContext context, [String message = 'Saved']) =>
    showSavedOn(ScaffoldMessenger.of(context), message);

void showSavedOn(ScaffoldMessengerState messenger, [String message = 'Saved']) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      backgroundColor: kSuccess,
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
      ]),
    ));
}

/// "Deleted. Undo" message that stays long enough to be noticed.
void showUndo(ScaffoldMessengerState messenger, String text, VoidCallback onUndo) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(text),
      action: SnackBarAction(label: 'Undo', onPressed: onUndo),
    ));
}

DateTime _earliest(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

Future<DateTime?> pickDate(
  BuildContext context, {
  DateTime? initial,
  DateTime? first,
  DateTime? last,
  String? help,
}) {
  final now = DateTime.now();
  final init = initial ?? now;
  return showDatePicker(
    context: context,
    initialDate: init,
    firstDate: _earliest(first ?? DateTime(now.year - 10), init),
    lastDate: last ?? DateTime(now.year + 15),
    helpText: help,
  );
}

Future<TimeOfDay?> pickTime(BuildContext context, String? hhmm) {
  final t = Dates.parseTime(hhmm);
  return showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: t?.hour ?? 9, minute: t?.minute ?? 0),
  );
}

/// Month + year chooser. Returns `yyyy-MM`, '' to clear, or null if cancelled.
Future<String?> pickMonthYear(BuildContext context, String? current) {
  final now = DateTime.now();
  final cur = Dates.parseMonthKey(current);
  var month = cur?.month ?? now.month;
  var year = cur?.year ?? now.year;
  final years = [for (var y = now.year - 1; y <= now.year + 8; y++) y];
  if (!years.contains(year)) years.add(year);
  years.sort();
  const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'];
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Target follow-up month'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: month,
              decoration: const InputDecoration(labelText: 'Month'),
              items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(names[i - 1]))],
              onChanged: (v) => setS(() => month = v ?? month),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: year,
              decoration: const InputDecoration(labelText: 'Year'),
              items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (v) => setS(() => year = v ?? year),
            ),
          ],
        ),
        actions: [
          if (current != null) TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Clear')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, Dates.monthKey(year, month)),
              child: const Text('Set')),
        ],
      ),
    ),
  );
}

/// Call / WhatsApp / Email shortcuts. They open the phone's own apps only.
class ContactActions extends StatelessWidget {
  const ContactActions(this.contact, {super.key});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final hasPhone = contact.phone.trim().isNotEmpty;
    final hasEmail = contact.email.trim().isNotEmpty;
    if (!hasPhone && !hasEmail) {
      return const Text('No phone or email saved', style: TextStyle(color: kMuted));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (hasPhone)
          OutlinedButton.icon(
            onPressed: () => Launcher.call(context, contact.phone),
            icon: const Icon(Icons.call),
            label: const Text('Call'),
          ),
        if (hasPhone)
          OutlinedButton.icon(
            onPressed: () => Launcher.whatsapp(context, contact.phone),
            icon: const Icon(Icons.chat),
            label: const Text('WhatsApp'),
          ),
        if (hasEmail)
          OutlinedButton.icon(
            onPressed: () => Launcher.email(context, contact.email),
            icon: const Icon(Icons.email_outlined),
            label: const Text('Email'),
          ),
      ],
    );
  }
}

/// Shows hint text under a field without blocking input.
String? phoneHintFor(String v) => ContactUtils.phoneHint(v);

class LabeledText extends StatelessWidget {
  const LabeledText(this.label, this.text, {super.key, this.maxLines});
  final String label;
  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: kMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(text.isEmpty ? '—' : text,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15.5, height: 1.35, color: kInk)),
      ],
    );
  }
}
