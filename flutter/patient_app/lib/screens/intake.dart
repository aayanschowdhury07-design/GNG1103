import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

import '../scope.dart';
import '../widgets.dart';

/// The reason-for-visit form. It only helps the front desk plan; nothing clinical is asked.
class IntakeScreen extends StatefulWidget {
  const IntakeScreen({super.key, required this.appointmentId});
  final String appointmentId;
  @override
  State<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends State<IntakeScreen> {
  String _type = IntakeAnswers.visitTypes.first;
  final _note = TextEditingController();
  bool _contact = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = context.s;
    await context.backend.submitIntake(widget.appointmentId, IntakeAnswers(visitType: _type, note: _note.text.trim(), contactByText: _contact));
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('formReceived'))));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return ScreenFrame(
      title: s.t('reasonTitle'),
      actions: const [LangSwitch()],
      bottom: FilledButton(onPressed: _submit, child: Text(s.t('submit'))),
      children: [
        Text(s.t('intakeIntro'), style: context.text.bodySmall),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.t('visitType')),
          // stored in English for the clinic; shown in the patient's language
          items: [for (final v in IntakeAnswers.visitTypes) DropdownMenuItem(value: v, child: Text(s.visitType(v)))],
          onChanged: (v) => setState(() => _type = v!),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(labelText: s.t('intakeNote'), hintText: s.t('intakeHint'), alignLabelWithHint: true),
        ),
        CheckboxListTile(
          value: _contact,
          onChanged: (v) => setState(() => _contact = v!),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(s.t('intakeContact'), style: context.text.bodySmall?.copyWith(color: context.colors.fg)),
        ),
      ],
    );
  }
}
