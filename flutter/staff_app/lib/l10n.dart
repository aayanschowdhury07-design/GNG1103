import 'package:flutter/material.dart';

import 'l10n/fr_a.dart';
import 'l10n/fr_b.dart';
import 'l10n/fr_c.dart';
import 'l10n/fr_d.dart';
import 'l10n/fr_staff_app.dart';

/// The staff app's language: 'en' (the default) or 'fr'. Shares the staff website's French.
final staffLang = ValueNotifier<String>('en');

/// The current language code, for the date and time helpers (formatTime(m, lang: lang)).
String get lang => staffLang.value;

/// Every French translation, keyed by the English text exactly as written in the code.
final Map<String, String> frStrings = {...frA, ...frB, ...frC, ...frD, ...frStaffApp};

/// [en] in the app's language, with {name} placeholders filled from [args].
String tr(String en, [Map<String, Object?> args = const {}]) {
  var s = staffLang.value == 'fr' ? (frStrings[en] ?? en) : en;
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// [one] or [many] depending on [n], translated, with {n} filled in.
String trn(int n, String one, String many, [Map<String, Object?> args = const {}]) => tr(n == 1 ? one : many, {'n': n, ...args});
