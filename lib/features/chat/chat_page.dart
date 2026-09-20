import 'package:flutter/material.dart';

import '../../app/app_config.dart';
import '../../app/app_theme.dart';
import '../../orb/rezolve_orb.dart';
import '../conversation/conversation.dart';
import '../conversation/demo_conversation.dart';
import '../conversation/live_conversation.dart';
import '../history/data/history_client.dart';
import '../voice/voice_controller.dart' show VoiceState;
import '../voice/widgets/mic_dock.dart';
import 'model/chat_message.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_message_view.dart';
import 'widgets/typing_indicator.dart';

/// The conversation.
///
/// Voice first: the mic sits alone at the bottom over its bloom of colour, and
/// the keyboard is one tap away for anyone who would rather type.
///
/// This screen has no idea whether it is driving a real voice call or the
/// offline demo. It renders a [Conversation] and nothing else — which is why
/// [AppConfig.liveVoice] can flip between the two without touching any widget.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    this.title = 'New trip',
    this.opener,
    this.resumeSessionId,
    this.conversation,
    this.autoListen = false,
  });

  final String title;

  /// The line that started this conversation on the home screen. It is sent as
  /// the first message so the assistant answers it rather than just greeting.
  final String? opener;

  /// Continue an earlier conversation rather than starting a new one. Set by
  /// the history list; the transcript so far is replayed into the thread and
  /// no opener is sent.
  final String? resumeSessionId;

  /// Override who is talking — tests pass a fake. Defaults to a live call when
  /// [AppConfig.liveVoice] is on, and the scripted demo otherwise.
  final Conversation? conversation;

  /// Retained for the home screen's mic button. A live call opens its mic as
  /// soon as it connects, so this only affects the demo.
  final bool autoListen;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final Conversation _talk = widget.conversation ?? _defaultConversation();

  Conversation _defaultConversation() => AppConfig.liveVoice
      ? LiveConversation(
          opener: widget.opener,
          resumeSessionId: widget.resumeSessionId,
        )
      // The scripted demo has no past to resume, so it ignores the id and just
      // opens normally.
      : DemoConversation(opener: widget.opener);

  final ScrollController _scroll = ScrollController();
  final HistoryClient _history = HistoryClient();
  bool _saved = false;
  bool _typingMode = false;

  @override
  void initState() {
    super.initState();
    _talk.addListener(_onChanged);
    // Immediately. This used to wait for the slide-up to finish, so the screen
    // would not arrive mid-connection — but connecting is now what the screen
    // shows, and the assistant takes long enough to answer that every fraction
    // of a second spent not asking for it is wasted.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _talk.start();
      if (!mounted) return;
      if (widget.autoListen && _talk is DemoConversation) {
        await _talk.onMicTap();
      }
    });
  }

  @override
  void dispose() {
    _history.dispose();
    _talk.removeListener(_onChanged);
    _talk.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Bookmark this conversation, or un-bookmark it.
  ///
  /// Flips on screen first and puts it back if the server disagrees: the tap
  /// is on a toggle, and a toggle that waits for a round trip before moving
  /// feels broken on a slow connection.
  Future<void> _toggleSaved() async {
    final String? id = _talk.sessionId;
    if (id == null) {
      // No session yet — the call is still connecting, or this is the scripted
      // demo. Saying so beats a bookmark that silently does not stick.
      _say('There is nothing to save until the conversation has started.');
      return;
    }

    final bool next = !_saved;
    setState(() => _saved = next);
    try {
      await _history.setSaved(id, next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saved = !next);
      _say('Could not save that. Try again in a moment.');
    }
  }

  /// Erase this conversation and leave the screen.
  ///
  /// Asks first, and says what is actually lost. Unlike saving, this is not a
  /// toggle to be flipped optimistically — the transcript and the cards go
  /// with it, in the database, and there is no undo to offer afterwards.
  Future<void> _deleteConversation() async {
    final String? id = _talk.sessionId;
    if (id == null) {
      _say('There is nothing to delete yet — this conversation was never '
          'saved to your history.');
      return;
    }

    final bool confirmed = await _confirmDelete();
    if (!confirmed || !mounted) return;

    try {
      await _history.delete(id);
    } catch (_) {
      if (!mounted) return;
      _say('Could not delete that. It is still in your history.');
      return;
    }

    if (!mounted) return;
    // Straight out: staying on a conversation that no longer exists would let
    // someone carry on talking into a transcript with nowhere to go.
    Navigator.of(context).maybePop();
  }

  Future<bool> _confirmDelete() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        title: Text('Delete this conversation?', style: AppText.section),
        content: Text(
          'Everything said in it, and the results it found, will be gone. '
          'This cannot be undone.',
          style: AppText.body,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep it',
                style: AppText.label.copyWith(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete',
                style: AppText.label.copyWith(color: const Color(0xFFC0392B))),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToEnd();
  }

  /// Ride the bottom of the thread as it grows. Posted to the next frame so the
  /// new message has been laid out before we measure.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<ChatMessage> messages = _talk.messages;
    final bool connecting = _talk.status == ConversationStatus.connecting;
    // While connecting there is nothing to say yet, and inviting someone to
    // talk to an assistant that has not arrived is a lie the old empty state
    // was telling.
    final bool empty = messages.isEmpty && !_talk.isTyping;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _ChatBar(
              title: widget.title,
              saved: _saved,
              onBack: () => Navigator.of(context).maybePop(),
              onSave: _toggleSaved,
              onDelete: _deleteConversation,
            ),
            // Failures get a banner, and so does a usable-but-degraded call
            // (a blocked microphone). Connecting is not a footnote — it is the
            // whole screen, below.
            if (_talk.status != ConversationStatus.connecting &&
                _talk.statusMessage != null)
              _StatusBanner(message: _talk.statusMessage!),
            Expanded(
              child: Stack(
                children: <Widget>[
                  if (connecting)
                    _ConnectingState(message: _talk.statusMessage)
                  else if (empty)
                    const _EmptyState()
                  else
                    ListView.separated(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.pageH,
                        8,
                        AppSpacing.pageH,
                        _typingMode ? 16 : 190,
                      ),
                      itemCount: messages.length + (_talk.isTyping ? 1 : 0),
                      separatorBuilder: (BuildContext context, int i) =>
                          SizedBox(height: _gapAfter(messages, i)),
                      itemBuilder: (BuildContext context, int i) {
                        if (i >= messages.length) {
                          return const _Entrance(
                            key: ValueKey<String>('typing'),
                            child: TypingIndicator(),
                          );
                        }
                        final ChatMessage m = messages[i];
                        final bool newSpeaker =
                            i == 0 || messages[i - 1].author != m.author;
                        return _Entrance(
                          key: ValueKey<String>(m.id),
                          child: ChatMessageView(
                            message: m,
                            showHeader: newSpeaker,
                            onReply: _talk.send,
                          ),
                        );
                      },
                    ),
                  if (!_typingMode)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: MicDock(
                        state: _talk.voiceState,
                        level: _talk.level,
                        partial: _talk.partial,
                        onTap: _talk.onMicTap,
                        auraHeight: 268,
                        idleHint: _micHint,
                        // Overrides the dock's own caption while connecting,
                        // which would otherwise read "Thinking…" — the orb is
                        // not thinking, nobody has arrived yet.
                        caption: connecting ? _talk.statusMessage : null,
                      ),
                    ),
                  if (!_typingMode)
                    Positioned(
                      left: AppSpacing.pageH,
                      // Level with the mic circle, as in the wireframe, rather
                      // than up beside the caption — and above the gesture bar.
                      bottom: 26 + MediaQuery.paddingOf(context).bottom,
                      child: _SmallRound(
                        icon: Icons.keyboard_alt_outlined,
                        tooltip: 'Type instead',
                        onTap: () => setState(() => _typingMode = true),
                      ),
                    ),
                ],
              ),
            ),
            if (_typingMode)
              ChatComposer(
                enabled: _talk.canType && !_talk.isTyping,
                onSend: _talk.send,
                onSwitchToVoice: () => setState(() => _typingMode = false),
              ),
          ],
        ),
      ),
    );
  }

  /// The caption under the mic. On a live call the mic is a mute toggle, so it
  /// must not say "tap to talk" — the assistant is already listening.
  String get _micHint => switch (_talk.status) {
        ConversationStatus.connecting => 'Connecting…',
        ConversationStatus.ready when _talk is LiveConversation =>
          _talk.voiceState == VoiceState.idle
              ? 'Tap the mic to talk'
              : 'Listening — just talk',
        ConversationStatus.failed => 'Tap the keyboard to type instead',
        ConversationStatus.ended => 'Call ended',
        _ => 'Tap and tell me where to',
      };

  /// Tighter spacing inside one speaker's run, looser between speakers.
  static double _gapAfter(List<ChatMessage> messages, int i) {
    if (i + 1 >= messages.length) return 20;
    return messages[i].author == messages[i + 1].author ? 10 : 22;
  }
}

/// A one-line explanation across the top: connecting, or why it failed.
/// A line across the top when something has gone wrong. Connecting has its own
/// full-width state in the middle of the screen; this is only for failures.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message});

  final String message;
  static const bool failed = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(AppSpacing.pageH, 0, AppSpacing.pageH, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: failed ? const Color(0xFFFFEDED) : AppColors.brandWash,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            failed ? Icons.error_outline_rounded : Icons.wifi_tethering_rounded,
            size: 17,
            color: failed ? const Color(0xFFC0392B) : AppColors.brand,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                color: failed ? const Color(0xFFC0392B) : AppColors.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallRound extends StatelessWidget {
  const _SmallRound({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, size: 21, color: AppColors.inkSoft),
          ),
        ),
      ),
    );
  }
}

class _ChatBar extends StatelessWidget {
  const _ChatBar({
    required this.title,
    required this.saved,
    required this.onBack,
    required this.onSave,
    required this.onDelete,
  });

  final String title;
  final bool saved;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageH,
        8,
        AppSpacing.pageH,
        10,
      ),
      child: Row(
        children: <Widget>[
          _RoundButton(
            icon: Icons.arrow_back_rounded,
            onTap: onBack,
            tooltip: 'Back',
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: AppColors.ink,
              ),
            ),
          ),
          _RoundButton(
            icon: saved
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            onTap: onSave,
            tooltip: saved ? 'Saved' : 'Save this trip',
            background: saved ? const Color(0xFFFFC93C) : AppColors.surface,
            foreground: saved ? Colors.white : AppColors.ink,
          ),
          const SizedBox(width: 8),
          // Last, and the furthest from the back button. It is the one control
          // here you cannot undo, so it should not sit where a thumb reaching
          // for "back" lands.
          _RoundButton(
            icon: Icons.delete_outline_rounded,
            onTap: onDelete,
            tooltip: 'Delete this conversation',
            foreground: const Color(0xFFC0392B),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.background = AppColors.surface,
    this.foreground = AppColors.ink,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, size: 21, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// What the screen shows while the assistant is on its way.
///
/// It takes the middle of the screen rather than a strip at the top, because
/// for the ten-odd seconds it lasts it is the only thing happening: the app is
/// in the LiveKit room, but the agent negotiates its own connection separately
/// and takes about that long to arrive. Showing the usual "tap and tell me
/// where to" through that window invites someone to talk to an empty room.
class _ConnectingState extends StatelessWidget {
  const _ConnectingState({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ExcludeSemantics(
              child: RezolveOrb(
                size: 92,
                headroom: 0,
                mood: OrbMood.thinking,
                playfulness: 0,
                quality: OrbQuality.balanced,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              message ?? 'Connecting…',
              textAlign: TextAlign.center,
              style: AppText.section,
            ),
            const SizedBox(height: 8),
            const Text(
              'Getting your assistant on the line. This takes a few seconds '
              'the first time.',
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
          ],
        ),
      ),
    );
  }
}

/// A blank conversation: tell the user what they can ask for.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.45),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Where are we going?',
              style: AppText.section,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Hold nothing back — dates, budget, a vague feeling about '
              'mountains. Talking is easiest.',
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
          ],
        ),
      ),
    );
  }
}

/// Fade, rise and settle — played once, when a message first appears.
class _Entrance extends StatefulWidget {
  const _Entrance({super.key, required this.child});

  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}
