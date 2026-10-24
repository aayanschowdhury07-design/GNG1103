import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scope.dart';
import '../session.dart';
import '../widgets.dart';
import 'account.dart';
import 'clinics.dart';
import 'intake.dart';

const _timeRoute = 'book-time';

void _backToTimes(BuildContext context) {
  context.draft.holdExpired(context.s);
  Navigator.of(context).popUntil((r) => r.settings.name == _timeRoute || r.isFirst);
}

/// Step 1: clinic, who the visit is for, and the service.
class BookServiceScreen extends StatelessWidget {
  const BookServiceScreen({super.key, this.embedded = false});

  /// True when shown as the Book tab (no back button).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, d = context.draft, s = context.s, lang = context.lang;
      final clinic = b.clinic(d.clinicId);
      final directory = b.clinics.where((c) => c.accepting).toList()..sort((x, y) => b.distanceKm(x).compareTo(b.distanceKm(y)));
      return ScreenFrame(
        back: !embedded,
        title: s.t('bookTitle'),
        actions: const [LangSwitch()],
        bottom: FilledButton(
          onPressed: () {
            if (d.minute == null) d.setError(null); // don't carry an old error into a new attempt
            Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: _timeRoute), builder: (_) => const BookTimeScreen()));
          },
          child: Text(s.t('continue')),
        ),
        children: [
          Text(s.t('bookIntro', {'name': clinic.name}), style: context.text.bodySmall),
          const SizedBox(height: 16),
          // the clinic dropdown: every directory clinic that takes online bookings, nearest first
          DropdownButtonFormField<String>(
            key: ValueKey(d.clinicId),
            initialValue: d.clinicId,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.t('clinic')),
            items: [
              for (final c in directory)
                DropdownMenuItem(
                  value: c.id,
                  child: Text(
                    '${c.name} · ${b.distanceKm(c)} km${c.isHome ? ' · ${s.t('yourClinic')}' : ''}${b.nextOpening(c.id) == null ? ' · ${s.t('noneToday')}' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) => d.start(b, id!),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClinicsScreen(standalone: true))),
              child: Text(s.t('seeMap')),
            ),
          ),
          const SizedBox(height: 8),
          Text(s.t('whoFor'), style: context.text.bodySmall),
          UnderlineTabs<String>(
            options: [(context.session.name, s.t('me')), for (final f in b.family()) (f.name, f.name.split(' ').first), ('+', s.t('addSomeone'))],
            selected: d.who,
            onSelect: (v) => v == '+' ? Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FamilyScreen(pickForBooking: true))) : d.pickWho(v),
          ),
          const SizedBox(height: 20),
          Text(s.t('step1'), style: context.text.bodySmall),
          Container(height: 1, color: context.colors.line, margin: const EdgeInsets.only(top: 8)),
          for (final svc in b.services(d.clinicId).where((x) => x.online))
            ChoiceRow(
              title: svc.nameIn(lang),
              subtitle: '${svc.minutes} min · ${svc.whoIn(lang)}',
              selected: d.serviceId == svc.id,
              onTap: () => d.pickService(b, svc.id),
            ),
        ],
      );
    });
  }
}

/// Step 2: clinician, day and time. Choosing a time holds it for 5 minutes.
class BookTimeScreen extends StatelessWidget {
  const BookTimeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, d = context.draft, s = context.s, lang = context.lang, c = context.colors;
      final svc = b.service(d.serviceId), clinic = b.clinic(d.clinicId);
      final ids = d.clinicianIds(b);
      SlotState stateOf(int m) {
        final all = ids.map((id) => b.slotState(id, d.date, m, viewer: BookingDraft.owner)).toList();
        return all.contains(SlotState.free) ? SlotState.free : all.first;
      }

      final anyFree = slotMinutes.any((m) => stateOf(m) == SlotState.free);
      final day = dayLabel(d.date, b.today, lang: lang, midSentence: true);
      final moving = d.rescheduling != null;
      Future<void> next() async {
        if (b.holdOf(BookingDraft.owner) == null) return d.setError(s.t(d.minute == null ? 'pickTime' : 'holdExpired'));
        if (!moving) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BookDetailsScreen()));
          return;
        }
        // changing the time needs no details or code: the patient is already signed in
        final r = await b.reschedule(d.rescheduling!, clinicianId: d.heldClinicianId!, date: d.date, minute: d.minute!, owner: BookingDraft.owner);
        if (!context.mounted) return;
        if (r.outcome != BookingOutcome.booked) return d.setError(s.t(r.outcome == BookingOutcome.slotTaken ? 'slotGone' : 'holdExpired'));
        final time = '${dayLabel(r.appointment!.date, b.today, lang: lang)}, ${formatTime(r.appointment!.minute, lang: lang)}';
        d.start(b, BookingDraft.defaultClinic(b));
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('moved', {'time': time}))));
      }

      return ScreenFrame(
        title: s.t(moving ? 'newTime' : 'whenTitle'),
        actions: const [LangSwitch()],
        bottom: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HoldBar(onExpired: () => d.holdExpired(s)),
          if (d.error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: ErrorLine(d.error)),
          FilledButton(onPressed: next, child: Text(s.t(moving ? 'move' : 'continue'))),
        ]),
        children: [
          if (!moving) Text(s.t('step2'), style: context.text.bodySmall),
          Container(height: 1, color: c.line, margin: const EdgeInsets.only(top: 8)),
          for (final id in svc.clinicianIds)
            ChoiceRow(
              leading: Avatar(initials(b.clinician(id).name)),
              title: b.clinician(id).name,
              subtitle: '${b.clinician(id).roleIn(lang)}${b.workingOn(id, d.date) ? '' : ' · ${s.t('notToday')}'}',
              selected: d.clinicianId == id,
              onTap: () => d.pickClinician(b, id),
            ),
          if (svc.clinicianIds.length > 1)
            ChoiceRow(title: s.t('anyClin'), subtitle: s.t('anyRole'), selected: d.clinicianId == 'any', onTap: () => d.pickClinician(b, 'any')),
          const SizedBox(height: 20),
          Text(s.t('day'), style: context.text.bodySmall),
          const SizedBox(height: 8),
          _DayStrip(
            today: b.today,
            days: b.bookableDays,
            selected: d.date,
            open: (day) => d.hasOpening(b, day),
            working: (day) => ids.any((id) => b.workingOn(id, day)),
            onPick: (day) => d.pickDay(b, day),
          ),
          const SizedBox(height: 16),
          Text('${longDay(d.date, b.today, lang: lang)} · ${clinic.name}', style: context.text.bodySmall),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.4,
            children: [
              for (final m in slotMinutes)
                _SlotButton(
                  label: formatTime(m, lang: lang),
                  selected: d.minute == m,
                  enabled: d.minute == m || stateOf(m) == SlotState.free,
                  onTap: () => d.pickTime(b, m, s),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            anyFree || d.minute != null
                ? s.t('slotNote')
                : d.clinicianId != 'any' && !b.workingOn(d.clinicianId, d.date)
                    ? s.t('clinNotIn', {'name': b.clinician(d.clinicianId).name, 'day': day})
                    : s.t('noTimes', {'name': clinic.name, 'day': day}),
            style: context.text.bodySmall,
          ),
        ],
      );
    });
  }
}

/// The next two weeks, one button per day. Days with nothing left are crossed out, like times.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.today, required this.days, required this.selected, required this.open, required this.working, required this.onPick});
  final List<String> days;
  final String today, selected;
  final bool Function(String) open, working;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors, lang = context.lang;
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final d = days[i], on = d == selected, free = open(d), date = DateTime.parse(d);
          final weekday = shortDate(d, lang: lang).split(' ').first;
          final fg = on ? c.accentFg : free ? c.fg : c.muted;
          return Semantics(
            button: true,
            selected: on,
            label: '${longDay(d, today, lang: lang)}${free ? '' : ', ${working(d) ? 'full' : context.s.t('closed')}'}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: free || on ? () => onPick(d) : null,
              child: Container(
                width: 52,
                decoration: BoxDecoration(
                  color: on ? c.accent : c.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: on ? c.accent : c.line),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(weekday, style: context.text.labelMedium?.copyWith(color: fg)),
                  Text('${date.day}', style: context.text.titleMedium?.copyWith(color: fg, decoration: free || on ? null : TextDecoration.lineThrough)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SlotButton extends StatelessWidget {
  const _SlotButton({required this.label, required this.selected, required this.enabled, required this.onTap});
  final String label;
  final bool selected, enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = context.text.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    if (selected) return FilledButton(onPressed: onTap, style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: EdgeInsets.zero), child: Text(label, style: style?.copyWith(color: c.accentFg)));
    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: EdgeInsets.zero, backgroundColor: c.surface),
      child: Text(label, style: style?.copyWith(color: enabled ? c.fg : c.muted, decoration: enabled ? null : TextDecoration.lineThrough)),
    );
  }
}

/// Step 3: name, phone and consent. Text reminders and the policy both start unticked.
class BookDetailsScreen extends StatefulWidget {
  const BookDetailsScreen({super.key});
  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  late final _name = TextEditingController(text: context.draft.who);
  late final _phone = TextEditingController(text: context.session.phone);
  final _email = TextEditingController(text: 'priya.r@example.ca');
  bool _sms = false, _policy = false, _sending = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final s = context.s, b = context.backend;
    if (b.holdOf(BookingDraft.owner) == null) return _backToTimes(context);
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final err = _name.text.trim().isEmpty
        ? s.t('errName')
        : phoneDigits.length < 10
            ? s.t('errPhone')
            : !_policy
                ? s.t('errPolicy')
                : null;
    if (err != null) return setState(() => _error = err);
    setState(() => _sending = true);
    try {
      await b.sendVerificationCode(_phone.text);
      if (!mounted) return;
      setState(() => _error = null);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookCodeScreen(name: _name.text.trim(), phone: _phone.text.trim(), smsConsent: _sms)));
    } on RateLimitException {
      setState(() => _error = s.t('errLimit'));
    } catch (e) {
      debugPrint('sendVerificationCode failed: $e');
      if (mounted) setState(() => _error = "We couldn't send a code just now. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final s = context.s, d = context.draft;
      return ScreenFrame(
        title: s.t('details'),
        actions: const [LangSwitch()],
        bottom: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: ErrorLine(_error)),
          FilledButton(onPressed: _sending ? null : _send, child: Text(s.t('sendCode'))),
        ]),
        children: [
          if (d.minute != null && d.heldClinicianId != null)
            BookingSummary(serviceId: d.serviceId, clinicianId: d.heldClinicianId!, date: d.date, minute: d.minute, clinicId: d.clinicId, who: d.who),
          const SizedBox(height: 8),
          HoldBar(onExpired: () => _backToTimes(context)),
          const SizedBox(height: 8),
          Text(s.t('step3'), style: context.text.bodySmall),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: InputDecoration(labelText: s.t('fullName')), autofillHints: const [AutofillHints.name], textInputAction: TextInputAction.next),
          const SizedBox(height: 12),
          TextField(controller: _phone, decoration: InputDecoration(labelText: s.t('mobile')), keyboardType: TextInputType.phone, autofillHints: const [AutofillHints.telephoneNumber], textInputAction: TextInputAction.next),
          const SizedBox(height: 12),
          TextField(controller: _email, decoration: InputDecoration(labelText: s.t('email')), keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email]),
          const SizedBox(height: 8),
          CheckboxListTile(value: _sms, onChanged: (v) => setState(() => _sms = v!), controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero, title: Text(s.t('smsConsent'), style: context.text.bodySmall?.copyWith(color: context.colors.fg))),
          CheckboxListTile(value: _policy, onChanged: (v) => setState(() => _policy = v!), controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero, title: Text(s.t('policy'), style: context.text.bodySmall?.copyWith(color: context.colors.fg))),
          const SizedBox(height: 8),
          Text(s.t('minData'), style: context.text.bodySmall, textAlign: TextAlign.center),
        ],
      );
    });
  }
}

/// Step 4: the 6-digit code. Verifying the phone confirms the booking.
class BookCodeScreen extends StatefulWidget {
  const BookCodeScreen({super.key, required this.name, required this.phone, required this.smsConsent});
  final String name, phone;
  final bool smsConsent;
  @override
  State<BookCodeScreen> createState() => _BookCodeScreenState();
}

class _BookCodeScreenState extends State<BookCodeScreen> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final s = context.s, b = context.backend, d = context.draft;
    if (_code.text.trim().length < 6) return setState(() => _error = s.t('errDigits'));
    setState(() => _busy = true);
    final ok = await b.verifyCode(widget.phone, _code.text);
    if (!mounted) return;
    if (!ok) {
      return setState(() {
        _error = s.t('errCode');
        _busy = false;
      });
    }
    if (b.holdOf(BookingDraft.owner) == null) return _backToTimes(context);
    final result = await b.book(BookingRequest(
      clinicId: d.clinicId,
      serviceId: d.serviceId,
      clinicianId: d.heldClinicianId!,
      date: d.date,
      minute: d.minute!,
      patientName: widget.name,
      phone: widget.phone,
      owner: BookingDraft.owner,
      bookedByGuardian: widget.name != context.session.name,
    ));
    if (!mounted) return;
    switch (result.outcome) {
      case BookingOutcome.booked:
        d.finish(result.appointment!);
        if (widget.smsConsent && !b.smsConsent) await b.setSmsConsent(true);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const BookedScreen()), (r) => r.isFirst);
      case BookingOutcome.holdExpired:
        _backToTimes(context);
      case BookingOutcome.slotTaken:
        d.setError(s.t('slotGone'));
        Navigator.of(context).popUntil((r) => r.settings.name == _timeRoute || r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s, demo = context.backend is TestInbox ? context.backend as TestInbox : null;
    return ScreenFrame(
      title: s.t('verify'),
      actions: const [LangSwitch()],
      bottom: FilledButton(onPressed: _busy ? null : _confirm, child: Text(s.t('confirmBooking'))),
      children: [
        Text(s.t('step4'), style: context.text.bodySmall),
        const SizedBox(height: 8),
        Text(s.t('otpTo', {'phone': widget.phone}), style: context.text.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          autofocus: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: context.text.headlineSmall?.copyWith(fontFamily: context.text.bodyMedium?.fontFamily, letterSpacing: 8, fontFeatures: const [FontFeature.tabularFigures()]),
          decoration: InputDecoration(labelText: s.t('code'), counterText: ''),
          onSubmitted: (_) => _confirm(),
        ),
        ErrorLine(_error),
        const SizedBox(height: 8),
        HoldBar(onExpired: () => _backToTimes(context)),
        // the phone's own one-time-code suggestion, simulated from the demo inbox
        if (demo != null)
          ValueListenableBuilder<String?>(
            valueListenable: demo.inbox,
            builder: (context, msg, _) {
              final code = RegExp(r'\d{6}').firstMatch(msg ?? '')?.group(0);
              return code == null ? const SizedBox.shrink() : Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _code.text = code, icon: const Icon(Icons.sms_outlined, size: 18), label: Text('From Messages: $code')));
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () async {
              try {
                await context.backend.sendVerificationCode(widget.phone);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('newCode'))));
              } on RateLimitException {
                setState(() => _error = s.t('errLimit'));
              }
            },
            child: Text(s.t('resend')),
          ),
        ),
      ],
    );
  }
}

/// Booked: what was booked and what happens next.
class BookedScreen extends StatelessWidget {
  const BookedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s, a = context.draft.lastBooked, c = context.colors;
    return ScreenFrame(
      title: s.t('booked'),
      back: false,
      bottom: FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: Text(s.t('done'))),
      children: [
        const SizedBox(height: 8),
        Center(child: CircleAvatar(radius: 30, backgroundColor: c.goodSoft, child: Icon(Icons.check, color: c.good, size: 30))),
        const SizedBox(height: 12),
        Text(s.t('bookedSub'), style: context.text.bodySmall, textAlign: TextAlign.center),
        if (a != null)
          Section(child: BookingSummary(serviceId: a.serviceId, clinicianId: a.clinicianId, date: a.date, minute: a.minute, clinicId: a.clinicId, who: a.patientName)),
        Section(
          title: s.t('next'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // the reason-for-visit form belongs to the patient's own clinic; others send their own
            if (a != null && context.backend.clinic(a.clinicId).isHome && !a.formsDone)
              Row(children: [
                Expanded(child: Text(s.t('formNow'), style: context.text.bodyMedium)),
                TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IntakeScreen(appointmentId: a.id))), child: Text(s.t('fill'))),
              ]),
            Text(s.t(a != null && a.date != context.backend.today ? 'nextLater' : 'nextToday'), style: context.text.bodySmall),
          ]),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('calendarAdded')))),
          child: Text(s.t('calendar')),
        ),
      ],
    );
  }
}
