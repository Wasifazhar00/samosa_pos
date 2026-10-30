import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// Small picture (or fallback icon) used as an item thumbnail.
class ItemThumb extends StatelessWidget {
  const ItemThumb({
    super.key,
    required this.path,
    required this.icon,
    this.size = 40,
    this.color,
  });

  final String path;
  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(path),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * 3).round()),
      );
    }
    return Icon(icon,
        size: size * 0.75, color: color ?? Theme.of(context).colorScheme.primary);
  }
}

/// Opens the gallery, shrinks the picture (so big phone photos cannot crash
/// the app) and stores a copy inside the app. Returns the saved path.
Future<String?> pickAndStoreImage({
  double maxSide = 700,
  int quality = 80,
  String prefix = 'img',
}) async {
  final x = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: maxSide,
    maxHeight: maxSide,
    imageQuality: quality,
  );
  if (x == null) return null;
  final base = await getApplicationSupportDirectory();
  await base.create(recursive: true);
  final ext = p.extension(x.path).isEmpty ? '.jpg' : p.extension(x.path);
  final dest = File(p.join(
      base.path, '${prefix}_${DateTime.now().millisecondsSinceEpoch}$ext'));
  await File(x.path).copy(dest.path);
  return dest.path;
}

class ImagePickRow extends StatelessWidget {
  const ImagePickRow({
    super.key,
    required this.path,
    required this.icon,
    required this.onChanged,
  });

  final String path;
  final IconData icon;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ItemThumb(path: path, icon: icon, size: 96),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final v = await pickAndStoreImage();
                    if (v != null) onChanged(v);
                  } catch (e) {
                    if (context.mounted) {
                      toast(context, 'Could not add the picture: $e', error: true);
                    }
                  }
                },
                icon: const Icon(Icons.photo, size: 18),
                label: Text(path.isEmpty ? 'Add picture' : 'Change picture'),
              ),
              if (path.isNotEmpty)
                TextButton(
                    onPressed: () => onChanged(''), child: const Text('Remove')),
            ],
          ),
        ),
      ],
    );
  }
}
