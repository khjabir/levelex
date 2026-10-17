import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/reminder_time.dart';

/// Large −/+ stepper for the reps-per-session setting.
class RepStepper extends StatelessWidget {
  const RepStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = Defaults.minPushUpsPerSession,
    this.max = Defaults.maxPushUpsPerSession,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepButton(
          icon: Icons.remove,
          label: 'Fewer push-ups',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 110,
          child: Semantics(
            label: 'Push-ups per session',
            value: '$value',
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.displayMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add,
          label: 'More push-ups',
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 56,
        height: 56,
        child: IconButton.filledTonal(
          onPressed: onPressed,
          icon: Icon(icon, size: 28),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.cardElevated,
            foregroundColor: AppColors.textPrimary,
            disabledForegroundColor: AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Preset chips (30 min / 1 h / 2 h) plus a custom interval dialog.
class IntervalPicker extends StatelessWidget {
  const IntervalPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Duration value;
  final ValueChanged<Duration> onChanged;

  static const presets = [
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
  ];

  static String label(Duration d) {
    final m = d.inMinutes;
    if (m % 60 == 0) {
      final h = m ~/ 60;
      return h == 1 ? 'Every hour' : 'Every $h hours';
    }
    if (m > 60) {
      final h = m ~/ 60;
      final rem = m % 60;
      return 'Every ${h}h ${rem}m';
    }
    return 'Every $m min';
  }

  @override
  Widget build(BuildContext context) {
    final isPreset = presets.contains(value);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in presets)
          ChoiceChip(
            label: Text(_short(preset)),
            selected: value == preset,
            onSelected: (_) => onChanged(preset),
          ),
        ChoiceChip(
          label: Text(isPreset ? 'Custom' : 'Custom · ${_short(value)}'),
          selected: !isPreset,
          onSelected: (_) => _pickCustom(context),
        ),
      ],
    );
  }

  static String _short(Duration d) {
    final m = d.inMinutes;
    if (m % 60 == 0) return '${m ~/ 60} h';
    if (m > 60) return '${m ~/ 60}h ${m % 60}m';
    return '$m min';
  }

  Future<void> _pickCustom(BuildContext context) async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) =>
          _CustomIntervalDialog(initialMinutes: value.inMinutes),
    );
    if (result != null) onChanged(Duration(minutes: result));
  }
}

class _CustomIntervalDialog extends StatefulWidget {
  const _CustomIntervalDialog({required this.initialMinutes});

  final int initialMinutes;

  @override
  State<_CustomIntervalDialog> createState() => _CustomIntervalDialogState();
}

class _CustomIntervalDialogState extends State<_CustomIntervalDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialMinutes}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_controller.text.trim());
    if (minutes == null ||
        minutes < Defaults.minIntervalMinutes ||
        minutes > Defaults.maxIntervalMinutes) {
      setState(
        () => _error =
            'Enter ${Defaults.minIntervalMinutes}–'
            '${Defaults.maxIntervalMinutes} minutes',
      );
      return;
    }
    Navigator.of(context).pop(minutes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom interval'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Minutes between reminders',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// A list tile that opens the platform time picker.
class TimeTile extends StatelessWidget {
  const TimeTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon = Icons.schedule,
  });

  final String title;
  final ReminderTime value;
  final ValueChanged<ReminderTime> onChanged;
  final IconData icon;

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
      helpText: title.toUpperCase(),
    );
    if (picked != null) {
      onChanged(ReminderTime(hour: picked.hour, minute: picked.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(
        value.label,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: AppColors.primary),
      ),
      onTap: () => _pick(context),
    );
  }
}

/// Shows a confirmation dialog; resolves true when the user confirms.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: AppColors.danger)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
