import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../orb/rezolve_orb.dart';
import '../model/chat_message.dart';

/// One message. The user speaks in white cards on the right; the assistant
/// speaks as plain text on the page, under its name and the time — the same
/// asymmetry the design uses, and it keeps long answers readable.
class ChatMessageView extends StatelessWidget {
  const ChatMessageView({
    super.key,
    required this.message,
    required this.onReply,
    this.showHeader = true,
  });

  final ChatMessage message;
  final ValueChanged<String> onReply;

  /// False when the previous message was from the same author, so a run of
  /// replies does not repeat the avatar and name.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return message.isUser ? _user(context) : _assistant(context);
  }

  Widget _user(BuildContext context) {
    final Widget content = Container(
            padding: const EdgeInsets.fromLTRB(18, 13, 18, 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppSpacing.cardRadius),
                topRight: Radius.circular(AppSpacing.cardRadius),
                bottomLeft: Radius.circular(AppSpacing.cardRadius),
                bottomRight: Radius.circular(6),
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x0F2A2140),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Text(message.text, style: AppText.message),
          );

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: content,
      ),
    );
  }

  Widget _assistant(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 38,
          child: showHeader
              ? const ExcludeSemantics(
                  child: RezolveOrb(
                    size: 34,
                    headroom: 0,
                    playfulness: 0.25,
                    quality: OrbQuality.balanced,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (showHeader) ...<Widget>[
                Row(
                  children: <Widget>[
                    Text(_time(message.at), style: AppText.caption),
                    const SizedBox(width: 8),
                    const Text(
                      'backPAC AI',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Text(message.text, style: AppText.message),
              if (message.replies.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String r in message.replies)
                      _ReplyChip(label: r, onTap: () => onReply(r)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _time(DateTime t) {
    final int h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final String m = t.minute.toString().padLeft(2, '0');
    return '$h:$m${t.hour < 12 ? 'am' : 'pm'}';
  }
}

class _ReplyChip extends StatelessWidget {
  const _ReplyChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandWash,
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
              color: AppColors.brand,
            ),
          ),
        ),
      ),
    );
  }
}
