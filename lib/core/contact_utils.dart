/// Phone / email helpers. Validation here is deliberately *friendly*: it only
/// produces hints and never blocks saving a record.
class ContactUtils {
  ContactUtils._();

  /// Digits only; Arabic-Indic / Persian digits are converted to 0-9.
  static String digitsOnly(String s) {
    final b = StringBuffer();
    for (final u in s.runes) {
      if (u >= 0x30 && u <= 0x39) {
        b.writeCharCode(u);
      } else if (u >= 0x660 && u <= 0x669) {
        b.writeCharCode(0x30 + u - 0x660);
      } else if (u >= 0x6F0 && u <= 0x6F9) {
        b.writeCharCode(0x30 + u - 0x6F0);
      }
    }
    return b.toString();
  }

  /// Allowed characters for a phone field (international formats).
  static final RegExp phoneChars = RegExp(r'^[0-9+\-\s().]*$');

  /// Returns a hint string, or null when the number looks fine / is empty.
  static String? phoneHint(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (!phoneChars.hasMatch(s)) {
      return 'Use digits only, e.g. +971 50 123 4567';
    }
    final n = digitsOnly(s).length;
    if (n < 7) {
      return 'That looks short. Include the country code, e.g. +971 50 123 4567';
    }
    if (n > 15) return 'That looks too long for an international number';
    if (!s.startsWith('+') && !s.startsWith('00')) {
      return 'Add the country code (e.g. +971) so WhatsApp works';
    }
    return null;
  }

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? emailHint(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    return _email.hasMatch(s) ? null : 'This email address looks incomplete';
  }

  /// `tel:` URI preserving a leading +.
  static Uri telUri(String phone) {
    final cleaned = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    return Uri(scheme: 'tel', path: cleaned);
  }

  /// wa.me link: digits only, international format, no leading + or 00.
  static Uri? whatsappUri(String phone) {
    // "+971 (0) 50 ...": the (0) trunk prefix must not be dialled abroad.
    var d = digitsOnly(phone.replaceAll(RegExp(r'\(\s*0\s*\)'), ''));
    if (phone.trim().startsWith('00') && d.startsWith('00')) d = d.substring(2);
    if (d.length < 7) return null;
    return Uri.parse('https://wa.me/$d');
  }

  static Uri mailUri(String email) => Uri(scheme: 'mailto', path: email.trim());
}
