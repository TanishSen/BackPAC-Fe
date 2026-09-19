import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../voice/speech_service.dart';
import '../voice/voice_controller.dart';
import '../voice/widgets/mic_dock.dart';
import 'chat_controller.dart';
import 'data/agent_service.dart';
import 'model/chat_message.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_message_view.dart';
import 'widgets/typing_indicator.dart';

/// The conversation.
///
/// Voice first: the mic sits alone at the bottom over its bloom of colour, and
/// the keyboard is one tap away for anyone who would rather type. Speech comes
/// in through [SpeechService], so swapping the simulator for a real recogniser
/// touches nothing on this screen.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    this.title = 'New trip',
    this.opener,
    this.agent,
    this.speech,
    this.autoListen = false,
  });

  final String title;
  final String? opener;

  /// Who answers. Defaults to the built-in [ScriptedAgent].
  final AgentService? agent;

  /// Where the words come from. Defaults to [SimulatedSpeechService].
  final SpeechService? speech;

  /// Open the mic as soon as the screen has slid into place — what the mic
  /// button on the home screen wants.
  final bool autoListen;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController _chat = ChatController(
    service: widget.agent ?? ScriptedAgent(),
    opener: widget.opener,
  )..addListener(_onChatChanged);

  late final VoiceController _voice = VoiceController(
    service: widget.speech ?? SimulatedSpeechService(),
  )..addListener(_onVoiceChanged);

  void _onVoiceChanged() => setState(() {});

  final ScrollController _scroll = ScrollController();
  bool _saved = false;
  bool _typingMode = false;
  int _spokenUpTo = 0;

  @override
  void initState() {
    super.initState();
    if (widget.autoListen) {
      // After the slide-up has finished, so the first thing the user sees is
      // the mic arriving, not already listening.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 520), () {
          if (mounted) _voice.startListening();
        });
      });
    }
  }

  @override
  void dispose() {
    _chat.removeListener(_onChatChanged);
    _voice.removeListener(_onVoiceChanged);
    _chat.dispose();
    _voice.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChatChanged() {
    // Keep the dock in step with the conversation: thinking while the reply is
    // being written, speaking once it lands.
    if (_chat.isTyping) {
      _voice.think();
    } else {
      final List<ChatMessage> all = _chat.messages;
      if (all.length > _spokenUpTo) {
        _spokenUpTo = all.length;
        final ChatMessage last = all.last;
        if (!last.isUser) {
          _voice.speak(last.text);
        } else {
          _voice.settle();
        }
      } else {
        _voice.settle();
      }
    }
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

  /// One button, four meanings — whatever is happening, tapping the mic does
  /// the obvious next thing.
  Future<void> _onMic() async {
    switch (_voice.state) {
      case VoiceState.idle:
        await _voice.startListening();
      case VoiceState.listening:
        // Speech-to-text is the input method: what comes back is just a
        // message, indistinguishable from a typed one.
        final String? said = await _voice.stopListening();
        if (said == null) return;
        await _chat.send(said);
      case VoiceState.speaking:
        _voice.stopSpeaking();
      case VoiceState.thinking:
        break; // let it finish
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<ChatMessage> messages = _chat.messages;
    final bool empty = messages.isEmpty && !_chat.isTyping;

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
              onSave: () => setState(() => _saved = !_saved),
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  if (empty)
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
                      itemCount: messages.length + (_chat.isTyping ? 1 : 0),
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
                            onReply: _chat.send,
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
                        state: _voice.state,
                        level: _voice.level,
                        partial: _voice.partial,
                        onTap: _onMic,
                        auraHeight: 268,
                        idleHint: 'Tap and tell me where to',
                      ),
                    ),
                  if (!_typingMode)
                    Positioned(
                      left: AppSpacing.pageH,
                      bottom: 34,
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
                enabled: !_chat.isTyping,
                onSend: _chat.send,
                onSwitchToVoice: () => setState(() => _typingMode = false),
              ),
          ],
        ),
      ),
    );
  }

  /// Tighter spacing inside one speaker's run, looser between speakers.
  static double _gapAfter(List<ChatMessage> messages, int i) {
    if (i + 1 >= messages.length) return 20;
    return messages[i].author == messages[i + 1].author ? 10 : 22;
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
  });

  final String title;
  final bool saved;
  final VoidCallback onBack;
  final VoidCallback onSave;

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
