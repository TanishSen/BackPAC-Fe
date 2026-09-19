import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/trip_data.dart';
import '../../app/transitions.dart';
import '../chat/chat_page.dart';
import '../voice/voice_controller.dart';
import '../voice/widgets/mic_button.dart';
import 'widgets/history_section.dart';
import 'widgets/home_header.dart';
import 'widgets/pro_card.dart';
import 'widgets/stagger.dart';
import 'widgets/travel_modes.dart';
import 'widgets/trip_ideas_row.dart';

/// Where "Let's Start" lands: everything the user can point the assistant at.
///
/// Every route out of this screen ends in the same place — a conversation —
/// so the page is a set of ways to open one, not a set of separate features.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.name = 'Jasmin'});

  final String name;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _credits = 24;

  /// The home mic never listens itself — it hands the microphone to the chat,
  /// which slides up over this page. This notifier only feeds the idle visuals.
  final ValueNotifier<double> _idleLevel = ValueNotifier<double>(0);

  @override
  void dispose() {
    _idleLevel.dispose();
    super.dispose();
  }

  Future<void> _openChat({
    String? opener,
    String title = 'New trip',
    bool listen = false,
  }) async {
    await Navigator.of(context).push(
      SlideUpRoute<void>(
        page: ChatPage(title: title, opener: opener, autoListen: listen),
      ),
    );
  }

  void _soon(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$what is next on the list.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: AppColors.ink,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final TextScaler scaler = media.textScaler.clamp(maxScaleFactor: 1.3);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: MediaQuery(
        data: media.copyWith(textScaler: scaler),
        child: SafeArea(
          bottom: false,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: <Widget>[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageH,
                      8,
                      AppSpacing.pageH,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Stagger(
                        index: 0,
                        child: HomeHeader(
                          name: widget.name,
                          onBell: () => _soon('Notifications'),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageH,
                      18,
                      AppSpacing.pageH,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Stagger(
                        index: 1,
                        child: ProCard(
                          credits: _credits,
                          onUpgrade: () => _soon('Pro'),
                          onOrbTap: () => _openChat(),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Stagger(
                      index: 2,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: TravelModes(
                          onPick: (TravelMode m) =>
                              _openChat(opener: m.prompt, title: m.label),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Stagger(
                      index: 3,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.pageH,
                          22,
                          AppSpacing.pageH,
                          12,
                        ),
                        child: Row(
                          children: <Widget>[
                            const Expanded(
                              child: Text(
                                'Plan something new',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.section,
                              ),
                            ),
                            TextButton(
                              onPressed: () => _soon('The full list'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.brand,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'View all',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Stagger(
                      index: 4,
                      child: TripIdeasRow(
                        ideas: kTripIdeas,
                        onPick: (TripIdea idea) =>
                            _openChat(opener: idea.prompt, title: idea.place),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Stagger(
                      index: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 26),
                        child: HistorySection(
                          entries: kHistory,
                          onViewAll: () => _soon('Full history'),
                          onOpen: (TripHistoryEntry e) =>
                              _openChat(opener: e.preview, title: e.title),
                        ),
                      ),
                    ),
                  ),
                  // Room for the bloom and the mic that float over the list.
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
              // The mic sits in the corner and stays out of the way: the page
              // behind it is a list, and a list should be readable.
              Positioned(
                right: -8,
                bottom: -6,
                child: MicButton(
                  state: VoiceState.idle,
                  level: _idleLevel,
                  size: 62,
                  onTap: () => _openChat(listen: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
