import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';

void toast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String yes = 'Yes',
  String no = 'Cancel',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(no),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for a single non-negative number. Returns null if cancelled.
Future<double?> promptNumber(
  BuildContext context, {
  required String title,
  required String label,
  double? initial,
  bool allowZero = true,
  String ok = 'OK',
  String cancel = 'Cancel',
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _NumberPromptDialog(
      title: title,
      label: label,
      initial: initial,
      allowZero: allowZero,
      ok: ok,
      cancel: cancel,
    ),
  );
}

class _NumberPromptDialog extends StatefulWidget {
  const _NumberPromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.allowZero,
    required this.ok,
    required this.cancel,
  });

  final String title;
  final String label;
  final double? initial;
  final bool allowZero;
  final String ok;
  final String cancel;

  @override
  State<_NumberPromptDialog> createState() => _NumberPromptDialogState();
}

class _NumberPromptDialogState extends State<_NumberPromptDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial == null ? '' : qtyText(widget.initial!),
  );
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.trim());
    if (v == null || v < 0 || (!widget.allowZero && v == 0)) {
      setState(() => _error = 'Enter a valid number');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.ok)),
      ],
    );
  }
}
