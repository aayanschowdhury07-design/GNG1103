import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'l10n/fr_a.dart';
import 'l10n/fr_b.dart';
import 'l10n/fr_c.dart';
import 'l10n/fr_d.dart';

/// The staff website's language: 'en' (the default) or 'fr', remembered in this browser.
final staffLang = ValueNotifier<String>(_saved());

/// The current language code, for the date and time helpers (formatTime(m, lang: lang)).
String get lang => staffLang.value;

const _key = 'cf.staffLang';

String _saved() {
  try {
    return web.window.localStorage.getItem(_key) == 'fr' ? 'fr' : 'en';
  } catch (_) {
    return 'en';
  }
}

void setStaffLang(String code) {
  staffLang.value = code;
  try {
    web.window.localStorage.setItem(_key, code);
  } catch (_) {}
}

/// Every French translation, keyed by the English text exactly as written in the code.
final Map<String, String> frStrings = {...frA, ...frB, ...frC, ...frD};

/// [en] in the staff website's language. {name} placeholders are filled from [args]:
///   tr('{n} visits today', {'n': 3})
/// Text without a French translation stays English.
String tr(String en, [Map<String, Object?> args = const {}]) {
  var s = staffLang.value == 'fr' ? (frStrings[en] ?? en) : en;
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// [one] or [many] depending on [n], translated, with {n} filled in.
String trn(int n, String one, String many, [Map<String, Object?> args = const {}]) => tr(n == 1 ? one : many, {'n': n, ...args});

/// English / Français switch, shown in the sidebar and on the sign-in screen.
class LangToggle extends StatelessWidget {
  const LangToggle({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: staffLang,
        builder: (context, code, _) => SegmentedButton<String>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
          ),
          segments: const [
            ButtonSegment(value: 'en', label: SizedBox(width: 64, child: Text('English', maxLines: 1, softWrap: false, textAlign: TextAlign.center))),
            ButtonSegment(value: 'fr', label: SizedBox(width: 64, child: Text('Français', maxLines: 1, softWrap: false, textAlign: TextAlign.center))),
          ],
          selected: {code},
          onSelectionChanged: (v) => setStaffLang(v.first),
        ),
      );
}
