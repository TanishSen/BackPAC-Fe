import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

/// The keyboard alternative to the mic.
///
/// Voice is the default way into this app, so this bar only appears when the
/// user asks for it, and it offers a way straight back to talking.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.onSend,
    required this.onSwitchToVoice,
    required this.enabled,
  });

  final ValueChanged<String> onSend;
  final VoidCallback onSwitchToVoice;
  final bool enabled;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Opened on purpose, so put the caret where the user expects it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _text.text;
    if (value.trim().isEmpty) return;
    _text.clear();
    widget.onSend(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageH,
        8,
        AppSpacing.pageH,
        10,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x0D2A2140),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        enabled: widget.enabled,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        style: AppText.message,
                        cursorColor: AppColors.brand,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Type something…',
                          hintStyle: TextStyle(
                            fontSize: 15.5,
                            color: AppColors.muted,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                    // Send appears only when there is something to send, and
                    // nothing sits here otherwise.
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _text,
                      builder: (BuildContext context, TextEditingValue value, _) {
                        final bool hasText = value.text.trim().isNotEmpty;
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: hasText
                              ? IconButton(
                                  key: const ValueKey<String>('send'),
                                  onPressed: _submit,
                                  icon: const Icon(Icons.arrow_upward_rounded,
                                      size: 22, color: AppColors.brand),
                                  tooltip: 'Send',
                                )
                              : const SizedBox(
                                  key: ValueKey<String>('idle'), width: 14),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: 'Talk instead',
              child: GestureDetector(
                onTap: widget.onSwitchToVoice,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFFE879C0), Color(0xFF6A68DF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.brand.withValues(alpha: 0.26),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.mic_rounded,
                      color: Colors.white, size: 23),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
