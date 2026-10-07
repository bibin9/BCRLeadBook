/// Detects company names that resemble each other so the app can *suggest*
/// opening an existing record. It never blocks creating a separate company.
class NameMatch {
  NameMatch._();

  static const _noise = {
    'the', 'ltd', 'limited', 'llc', 'inc', 'co', 'company', 'corp',
    'corporation', 'fze', 'fzco', 'fzc', 'pjsc', 'psc', 'llp', 'plc', 'gmbh',
    'pvt', 'private', 'and', 'trading', 'group', 'holding', 'holdings',
  };

  static String normalize(String name) {
    final cleaned = name
        .toLowerCase()
        .replaceAll('&', ' ')
        .replaceAll(RegExp(r'[^a-z0-9؀-ۿ\s]'), ' ');
    final words = cleaned
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_noise.contains(w))
        .toList();
    if (words.isEmpty) {
      return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return words.join(' ');
  }

  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// True when [a] and [b] are probably the same business.
  static bool similar(String a, String b) {
    // Spaces are ignored so "A.B.C." matches "ABC".
    final na = normalize(a).replaceAll(' ', ''), nb = normalize(b).replaceAll(' ', '');
    if (na.length < 3 || nb.length < 3) return false;
    if (na == nb) return true;
    final shorter = na.length <= nb.length ? na : nb;
    final longer = na.length <= nb.length ? nb : na;
    if (shorter.length >= 4 && longer.startsWith(shorter)) return true;
    final dist = levenshtein(na, nb);
    if (longer.length >= 6 && dist <= 2) return true;
    return longer.length >= 4 && dist <= 1;
  }
}
