import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/contact_utils.dart';

/// Opens the phone's own Phone / WhatsApp / Email apps. These only *open* the
/// app with the number or address filled in. Nothing is ever sent
/// automatically.
class Launcher {
  Launcher._();

  static Future<void> _open(BuildContext context, Uri? uri, String failMsg) async {
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        ok = false;
      }
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failMsg)));
    }
  }

  static Future<void> call(BuildContext context, String phone) => _open(
      context, ContactUtils.telUri(phone), 'Could not open the phone app.');

  static Future<void> whatsapp(BuildContext context, String phone) => _open(
      context,
      ContactUtils.whatsappUri(phone),
      'Could not open WhatsApp. Check the number includes its country code.');

  static Future<void> email(BuildContext context, String email) => _open(
      context, ContactUtils.mailUri(email), 'Could not open an email app.');
}
