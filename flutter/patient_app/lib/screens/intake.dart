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
    await context.backend.submitIntake(widget.appointmentId, IntakeAnswers(visitType: _type, note: _note.text.trim(), contactByText: _contact));
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Form received. The front desk can see it.')));
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Reason for visit',
      bottom: FilledButton(onPressed: _submit, child: const Text('Submit')),
      children: [
        Text("This form only helps the front desk plan your visit. Please don't include symptoms or medical details; your clinician will ask about those in person.",
            style: context.text.bodySmall),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Type of visit'),
          items: [for (final t in IntakeAnswers.visitTypes) DropdownMenuItem(value: t, child: Text(t))],
          onChanged: (v) => setState(() => _type = v!),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Anything that would make your visit easier? (optional)',
            hintText: 'For example: a ground-floor room, an interpreter, or extra time to get settled.',
            alignLabelWithHint: true,
          ),
        ),
        CheckboxListTile(
          value: _contact,
          onChanged: (v) => setState(() => _contact = v!),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text('The clinic can contact me about this visit by text.', style: context.text.bodySmall?.copyWith(color: context.colors.fg)),
        ),
      ],
    );
  }
}
