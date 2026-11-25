import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strings/poc_strings.dart';
import '../providers/call_providers.dart';

/// Paste a fresh Agora temp token without rebuilding the APK. Saved on the
/// phone and used for every call until replaced or reset.
class TokenField extends ConsumerStatefulWidget {
  const TokenField({super.key});

  @override
  ConsumerState<TokenField> createState() => _TokenFieldState();
}

class _TokenFieldState extends ConsumerState<TokenField> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: ref.read(manualTokenControllerProvider),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (pasted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(PocStrings.tokenClipboardEmpty)),
      );
      return;
    }
    await _save(pasted);
  }

  Future<void> _save(String token) async {
    await ref.read(manualTokenControllerProvider.notifier).save(token);
    if (!mounted) return;
    _setText(ref.read(manualTokenControllerProvider));
  }

  Future<void> _reset() async {
    await ref.read(manualTokenControllerProvider.notifier).resetToBuiltIn();
    if (!mounted) return;
    _setText(ref.read(manualTokenControllerProvider));
  }

  void _setText(String token) => _text.value = TextEditingValue(
    text: token,
    selection: TextSelection.collapsed(offset: token.length),
  );

  @override
  Widget build(BuildContext context) {
    // Rebuild the hint when the saved token changes.
    ref.watch(manualTokenControllerProvider);
    final isSaved = ref
        .read(manualTokenControllerProvider.notifier)
        .isUsingSavedToken;

    return TextField(
      controller: _text,
      maxLines: 1,
      // An emptied field just waits for input; "Use built-in token" resets.
      onChanged: (value) {
        if (value.trim().isNotEmpty) _save(value);
      },
      style: const TextStyle(fontFamily: 'monospace'),
      decoration: InputDecoration(
        labelText: PocStrings.tokenField,
        border: const OutlineInputBorder(),
        helperText: isSaved
            ? PocStrings.tokenSavedHint
            : PocStrings.tokenBuiltInHint,
        helperMaxLines: 3,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: PocStrings.tokenPaste,
              icon: const Icon(Icons.content_paste),
              onPressed: _paste,
            ),
            if (isSaved)
              IconButton(
                tooltip: PocStrings.tokenReset,
                icon: const Icon(Icons.restart_alt),
                onPressed: _reset,
              ),
          ],
        ),
      ),
    );
  }
}
