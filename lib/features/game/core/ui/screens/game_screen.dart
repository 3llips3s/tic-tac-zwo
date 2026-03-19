import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:tic_tac_zwo/features/game/core/data/models/game_config.dart';
import 'package:tic_tac_zwo/features/game/core/data/models/german_noun.dart';
import 'package:tic_tac_zwo/features/game/core/logic/game_state.dart';
import 'package:tic_tac_zwo/features/game/core/ui/widgets/article_buttons.dart';
import 'package:tic_tac_zwo/features/game/core/ui/widgets/dual_progress_indicator.dart';
import 'package:tic_tac_zwo/features/game/core/ui/widgets/game_board.dart';
import 'package:tic_tac_zwo/features/game/core/ui/widgets/game_over_dialog.dart';
import 'package:tic_tac_zwo/features/game/core/ui/widgets/glassmorphic_dialog.dart';
import 'package:tic_tac_zwo/features/game/core/ui/widgets/player_info.dart';
import 'package:tic_tac_zwo/features/game/core/ui/widgets/timer_display.dart';
import 'package:tic_tac_zwo/features/game/core/ui/widgets/turn_noun_display.dart';
import 'package:tic_tac_zwo/features/game/online/logic/online_game_notifier.dart';
import 'package:tic_tac_zwo/features/navigation/logic/navigation_provider.dart';
import 'package:tic_tac_zwo/features/wortschatz/logic/saved_nouns_notifier.dart';

import '../../../../../config/game_config/config.dart';
import '../../../../../config/game_config/constants.dart';
import '../../../../../config/game_config/game_providers.dart';
import '../../../../navigation/routes/route_names.dart';
import '../../../../settings/logic/audio_manager.dart';
import '../../../../settings/logic/haptics_manager.dart';
import '../../../online/ui/widgets/online_game_over_dialog.dart';

class GameScreen extends ConsumerStatefulWidget {
  final GameConfig gameConfig;

  const GameScreen({
    super.key,
    required this.gameConfig,
  });

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
  bool _isCurrentNounSaved = false;

  void _showSnackBar(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Color? textColor,
  }) {
    final activeBackgroundColor =
        backgroundColor ?? colorBlack.withOpacity(0.8);
    final activeTextColor = textColor ?? colorWhite;

    final snackBar = SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 1),
      margin: EdgeInsets.symmetric(horizontal: 40).copyWith(
        bottom: kToolbarHeight / 2,
      ),
      content: Container(
        height: kToolbarHeight,
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: activeBackgroundColor,
          border: Border.all(color: activeTextColor.withOpacity(0.1)),
          borderRadius: const BorderRadius.all(Radius.circular(9)),
        ),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: activeTextColor,
                ),
          ),
        ),
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  Future<void> _checkIfCurrentNounIsSaved(String nounId) async {
    if (!mounted) return;
    final savedNounsNotifier = ref.read(savedNounsProvider.notifier);
    final bool isSaved = await savedNounsNotifier.isNounSaved(nounId);
    if (mounted) {
      setState(() {
        _isCurrentNounSaved = isSaved;
      });
    }
  }

  void _showHomeNavigationDialog() {
    final isOnlineMode = widget.gameConfig.gameMode == GameMode.online;
    final gameState =
        ref.read(GameProviders.getStateProvider(ref, widget.gameConfig));

    if (isOnlineMode &&
        (gameState.opponentConnectionStatus !=
                OpponentConnectionStatus.connected ||
            gameState.localConnectionStatus ==
                LocalConnectionStatus.disconnected)) {
      return;
    }

    String title;
    String content;
    Future<void> Function() onConfirm;

    if (isOnlineMode && !gameState.isGameOver) {
      final notifier =
          ref.read(onlineGameStateNotifierProvider(widget.gameConfig).notifier);
      title = 'Aufgeben?';
      content = 'Das Spiel wird als Niederlage gewertet.';
      onConfirm = () async {
        Navigator.of(context).pop();
        await notifier.requestForfeit();
      };
    } else {
      title = 'Spiel verlassen?';
      content = gameState.isGameOver
          ? 'Zurück zum Home?'
          : 'Dein Spielfortschritt ist dann futsch.';
      onConfirm = () async {
        Navigator.of(context).pop();
        ref.read(navigationTargetProvider.notifier).state =
            NavigationTarget.home;
      };
    }

    showCustomDialog(
      context: context,
      height: 300,
      width: 300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: colorBlack,
                ),
          ),
          const SizedBox(height: 40),
          Text(
            content,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                ),
          ),
          const SizedBox(height: 32),
        ],
      ),
      actions: [
        GlassMorphicButton(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(
            Icons.close_rounded,
            color: colorRed,
            size: 36,
          ),
        ),
        GlassMorphicButton(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          onPressed: onConfirm,
          child: const Icon(
            Icons.check_rounded,
            color: colorYellowAccent,
            size: 36,
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // pause background music
    AudioManager.instance.pauseBackgroundMusic(fade: true);

    // navigation listener
    ref.listenManual<NavigationTarget?>(
      navigationTargetProvider,
      (previous, next) {
        if (next != null) {
          String routeName;
          switch (next) {
            case NavigationTarget.home:
              routeName = RouteNames.home;
              break;
            case NavigationTarget.matchmaking:
              routeName = RouteNames.matchmaking;
              break;
          }

          Navigator.pushNamedAndRemoveUntil(
              context, routeName, (route) => false);
          ref.read(navigationTargetProvider.notifier).state = null;
        }
      },
      fireImmediately: false,
    );

    // game over dialog listener
    ref.listenManual<GameState>(
      GameProviders.getStateProvider(ref, widget.gameConfig),
      (previous, next) {
        final wasGameOver = previous?.isGameOver ?? false;

        if (next.isGameOver && !wasGameOver) {
          print(
              'Game over detected - status: ${next.gameStatus}, isLocalPlayer winner: ${next.winningPlayer?.userId == Supabase.instance.client.auth.currentUser?.id}');
          WidgetsBinding.instance.addPostFrameCallback(
            (_) {
              if (context.mounted) {
                if (widget.gameConfig.gameMode == GameMode.online) {
                  // only show dialog for naturally completed games
                  if (next.gameStatus == GameStatus.completed) {
                    showOnlineGameOverDialog(context, ref, widget.gameConfig);
                  }
                } else {
                  final gameNotifier = ref.read(
                      GameProviders.getStateProvider(ref, widget.gameConfig)
                          .notifier);

                  showGameOverDialog(
                    context,
                    widget.gameConfig,
                    next,
                    () => gameNotifier.rematch(),
                  );
                }
              }
            },
          );
        } else if (wasGameOver &&
            !next.isGameOver &&
            widget.gameConfig.gameMode == GameMode.online) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }

          final nextStartingPlayer = next.currentPlayer;
          final supabase = Supabase.instance.client;
          final localUserId = supabase.auth.currentUser?.id;
          final isLocalUser = nextStartingPlayer.userId == localUserId;
          final message = isLocalUser
              ? 'Du beginnst.'
              : '${nextStartingPlayer.username} beginnt.';

          _showSnackBar(context, message);
        }

        if (previous?.localConnectionStatus ==
                LocalConnectionStatus.disconnected &&
            next.localConnectionStatus == LocalConnectionStatus.connected &&
            next.isGameOver &&
            next.gameStatus == GameStatus.forfeited) {
          _showSnackBar(
            context,
            'Leider ist das Spiel schon vorbei.',
            backgroundColor: colorRed,
            textColor: colorWhite,
          );

          Timer(
            Duration(seconds: 2),
            () {
              if (mounted) {
                ref.read(navigationTargetProvider.notifier).state =
                    NavigationTarget.home;
              }
            },
          );
        }
      },
      fireImmediately: false,
    );

    // current noun listener
    ref.listenManual<GermanNoun?>(
      GameProviders.getStateProvider(ref, widget.gameConfig)
          .select((state) => state.currentNoun),
      (previousNoun, nextNoun) {
        if (nextNoun != null) {
          _checkIfCurrentNounIsSaved(nextNoun.id);
        } else {
          setState(() {
            _isCurrentNounSaved = false;
          });
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AudioManager.instance.resumeBackgroundMusic(fade: false);
    super.dispose();
  }

  // gonna: implement this fore and background functionality
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // when app goes to the background (e.g., pause game)
    } else if (state == AppLifecycleState.resumed) {
      // when app comes to the foreground (e.g., resume game)
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState =
        ref.watch(GameProviders.getStateProvider(ref, widget.gameConfig));

    final opponentStatus = gameState.opponentConnectionStatus;
    final localStatus = gameState.localConnectionStatus;

    final isOnlineMode = widget.gameConfig.gameMode == GameMode.online;
    final onlineNotifier = isOnlineMode
        ? ref.read(onlineGameStateNotifierProvider(widget.gameConfig).notifier)
        : null;

    final savedNounsNotifier = ref.read(savedNounsProvider.notifier);

    final currentNoun = gameState.currentNoun;

    final bool activateSaveButton =
        gameState.selectedCellIndex != null && gameState.isTimerActive;

    final space = SizedBox(height: kToolbarHeight);
    final halfSpace = SizedBox(height: kToolbarHeight / 2);
    final quarterSpace = SizedBox(height: kToolbarHeight / 4);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        _showHomeNavigationDialog();
      },
      child: Scaffold(
        backgroundColor: colorGrey300,
        body: Stack(
          children: [
            Container(
              color: colorGrey300,
              padding: EdgeInsets.only(bottom: 10),
              child: Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      space,

                      // timer
                      Align(
                        alignment: Alignment.center,
                        child: AnimatedSwitcher(
                          duration: Duration(milliseconds: 600),
                          switchInCurve: Curves.easeInOut,
                          switchOutCurve: Curves.easeInOut,
                          child: _buildTimerWidget(
                              context,
                              ref,
                              widget.gameConfig,
                              gameState,
                              isOnlineMode,
                              onlineNotifier),
                        ),
                      ).animate().fadeIn(
                            delay: 3300.ms,
                            duration: 600.ms,
                            curve: Curves.easeInOut,
                          ),

                      halfSpace,

                      // players
                      PlayerInfo(gameConfig: widget.gameConfig)
                          .animate(delay: 1800.ms)
                          .slideY(
                            begin: -0.5,
                            end: 0.0,
                            duration: 1500.ms,
                            curve: Curves.easeInOut,
                          )
                          .fadeIn(
                            duration: 1500.ms,
                            curve: Curves.easeInOut,
                          ),

                      quarterSpace,

                      // word display
                      TurnNounDisplay(gameConfig: widget.gameConfig)
                          .animate()
                          .fadeIn(
                            delay: 3300.ms,
                            duration: 600.ms,
                            curve: Curves.easeInOut,
                          ),

                      quarterSpace,

                      // game board
                      Center(
                        child: GameBoard(
                          gameConfig: widget.gameConfig,
                        ),
                      )
                          .animate(
                            delay: 300.ms,
                          )
                          .scale(
                            duration: 1500.ms,
                            curve: Curves.easeInOut,
                          )
                          .fadeIn(
                            begin: 0.0,
                            duration: 1500.ms,
                            curve: Curves.easeInOut,
                          ),

                      space,

                      // article buttons
                      ArticleButtons(
                        gameConfig: widget.gameConfig,
                        overlayColor: gameState
                            .getArticleOverlayColor(gameState.currentPlayer),
                      ),

                      halfSpace,

                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8, right: 64),
                          child: GestureDetector(
                            onTap: activateSaveButton
                                ? () async {
                                    HapticsManager.light();

                                    // save word
                                    if (_isCurrentNounSaved) {
                                      if (context.mounted) {
                                        _showSnackBar(
                                          context,
                                          '${currentNoun!.noun} ist schon gespeichert!',
                                          backgroundColor: colorWhite,
                                          textColor: Colors.black54,
                                        );
                                      }
                                    } else {
                                      final bool saved =
                                          await savedNounsNotifier
                                              .addNoun(currentNoun!);
                                      if (saved) {
                                        if (context.mounted) {
                                          _showSnackBar(
                                            context,
                                            '${currentNoun.noun} gespeichert!',
                                            backgroundColor: colorWhite,
                                            textColor: colorBlack,
                                          );
                                        }
                                        if (mounted) {
                                          setState(() {
                                            _isCurrentNounSaved = true;
                                          });
                                        }
                                      } else {
                                        if (context.mounted) {
                                          _showSnackBar(
                                            context,
                                            '${currentNoun.noun} nicht gespeichert!',
                                            backgroundColor: colorRed,
                                            textColor: colorWhite,
                                          );
                                        }
                                      }
                                    }
                                  }
                                : null,
                            child: Container(
                              height: 40,
                              width: 40,
                              color: Colors.transparent,
                              child: Center(
                                child: SvgPicture.asset(
                                  'assets/images/bookmark.svg',
                                  colorFilter: activateSaveButton
                                      ? ColorFilter.mode(
                                          _isCurrentNounSaved
                                              ? Colors.green.shade600
                                              : colorBlack,
                                          BlendMode.srcIn,
                                        )
                                      : ColorFilter.mode(
                                          Colors.black26,
                                          BlendMode.srcIn,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: kToolbarHeight),
                    ],
                  ),

                  // back button
                  Positioned(
                    bottom: 16,
                    left: 24,
                    child: SizedBox(
                      height: 52,
                      width: 52,
                      child: FloatingActionButton(
                        onPressed: _showHomeNavigationDialog,
                        backgroundColor: colorBlack.withOpacity(0.75),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.home_rounded,
                          color: colorWhite,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // opponent status overlay
            if (isOnlineMode &&
                opponentStatus != OpponentConnectionStatus.connected)
              Container(
                color: colorBlack.withOpacity(0.1),
                child: Center(
                  child: _buildOpponentStatusOverlay(
                    context,
                    opponentStatus,
                    onlineNotifier!,
                  ),
                ),
              ),

            // local disconnection overlay
            if (isOnlineMode &&
                localStatus == LocalConnectionStatus.disconnected)
              _buildLocalDisconnectionOverlay(
                context,
                localStatus,
                onlineNotifier?.localDisconnectionRemainingSeconds ?? 0,
              )
          ],
        ),
      ),
    );
  }

  Widget _buildTimerWidget(
    BuildContext context,
    WidgetRef ref,
    GameConfig gameConfig,
    GameState gameState,
    bool isOnlineMode,
    OnlineGameNotifier? onlineNotifier,
  ) {
    const double textSize = 18.0;
    const double padding = 9.0;
    const double timerSize = textSize + (padding * 2);

    Widget timerContainer({required Widget child}) {
      return SizedBox(
        height: timerSize,
        width: timerSize,
        child: Center(
          child: child,
        ),
      );
    }

    if (!isOnlineMode) {
      final key = gameState.isTimerActive ? 'active' : 'inactive';
      return timerContainer(
        child: TimerDisplay(
          gameConfig: gameConfig,
          key: ValueKey(key),
        ),
      );
    }

    final timerState =
        onlineNotifier?.timerDisplayState ?? TimerDisplayState.static;

    final outerCircleColors = const [
      colorYellowAccent,
      colorRed,
      colorWhite,
    ];
    final innerCircleColors = const [
      colorRed,
      colorYellowAccent,
      colorBlack,
    ];

    switch (timerState) {
      case TimerDisplayState.inactivity:
        return timerContainer(
          child: DualProgressIndicator(
            key: ValueKey('inactivity'),
            size: timerSize * 0.7,
            outerStrokeWidth: 1,
            innerStrokeWidth: 1,
            outerCircleColors: outerCircleColors,
            innerCircleColors: innerCircleColors,
            circleGap: 0.8,
          ),
        );
      case TimerDisplayState.countdown:
        return timerContainer(
          child: TimerDisplay(
            gameConfig: gameConfig,
            key: ValueKey('countdown'),
          ),
        );
      case TimerDisplayState.static:
        return timerContainer(
          child: TimerDisplay(
            gameConfig: gameConfig,
            key: ValueKey('static'),
          ),
        );
    }
  }

  Widget _buildOpponentStatusOverlay(
    BuildContext context,
    OpponentConnectionStatus status,
    OnlineGameNotifier notifier,
  ) {
    String title;
    Widget content;
    List<Widget>? actions;

    switch (status) {
      case OpponentConnectionStatus.reconnecting:
        final onlineNotifier = ref
            .read(onlineGameStateNotifierProvider(widget.gameConfig).notifier);

        if (onlineNotifier.hasShownDisconnectionOptions) {
          title = 'Gegner*in ist nicht zurückgekehrt';
          content = Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Text(
              'Was möchtest du tun?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 16,
                    color: Colors.black54,
                  ),
            ),
          );
          actions = [
            GlassMorphicButton(
              onPressed: () => notifier.goHomeAndCleanupSession(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                child: const Icon(
                  Icons.home_rounded,
                  color: Colors.black87,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(width: 24),
            GlassMorphicButton(
              onPressed: () => notifier.findNewOpponent(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                child: const Icon(
                  Icons.search_rounded,
                  color: colorYellowAccent,
                  size: 30,
                ),
              ),
            ),
          ];
        } else {
          title = 'Gegner*in verbindet sich neu...';
          content = const Padding(
            padding: EdgeInsets.symmetric(vertical: 56.0),
            child: Center(
              child: DualProgressIndicator(),
            ),
          );
          actions = null;
        }
        break;
      case OpponentConnectionStatus.forfeited:
        final gameState =
            ref.watch(GameProviders.getStateProvider(ref, widget.gameConfig));
        final pointsEarned = gameState.pointsEarnedPerGame != null
            ? gameState.pointsEarnedPerGame.toString()
            : '0';

        title = 'Gegner*in hat aufgegeben :(';
        content = Padding(
          padding: EdgeInsets.symmetric(vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'kassierte Artikelpunkte:',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 16,
                      color: colorBlack,
                    ),
              ),
              const SizedBox(width: 8),
              Text(
                '+ $pointsEarned',
                style: TextStyle(
                  fontSize: 24,
                  color: colorDarkGreen,
                  shadows: [
                    Shadow(
                      color: Colors.lightGreenAccent,
                      blurRadius: 10.0,
                    ),
                    Shadow(
                      color: colorBlack.withOpacity(0.5),
                      blurRadius: 1.0,
                      offset: Offset(1, 1),
                    )
                  ],
                ),
              )
                  .animate(delay: 300.ms)
                  .fadeIn(duration: 600.ms, curve: Curves.easeOut)
                  .scale(
                      duration: 900.ms,
                      curve: Curves.elasticOut,
                      begin: const Offset(0.1, 0.1))
                  .then(delay: 200.ms)
                  .shimmer(duration: 600.ms, color: colorWhite, angle: 45)
                  .shake(hz: 5, duration: 600.ms, curve: Curves.easeInOut)
            ],
          ),
        );
        actions = [
          // go home
          GlassMorphicButton(
            onPressed: () => notifier.goHomeAndCleanupSession(),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              child: const Icon(
                Icons.home_rounded,
                color: Colors.black87,
                size: 30,
              ),
            ),
          ),
          GlassMorphicButton(
            onPressed: () => notifier.findNewOpponent(),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              child: const Icon(
                Icons.search_rounded,
                color: colorYellowAccent,
                size: 30,
              ),
            ),
          ),
        ];
        break;
      case OpponentConnectionStatus.connected:
        return const SizedBox.shrink();
    }

    return GlassmorphicDialog(
      height: 300,
      width: 300,
      actions: actions,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: colorRed,
                ),
          ),
          const SizedBox(height: 32),
          content,
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLocalDisconnectionOverlay(
    BuildContext context,
    LocalConnectionStatus status,
    int remainingSeconds,
  ) {
    if (status != LocalConnectionStatus.disconnected) {
      return const SizedBox.shrink();
    }

    final hasTimeRunOut = remainingSeconds <= 0;

    return Container(
      color: colorBlack.withOpacity(0.1),
      child: Center(
        child: GlassmorphicDialog(
          height: 350,
          width: 300,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Text(
                hasTimeRunOut ? 'Spiel aufgegeben' : 'Verbindung verloren!',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: colorRed,
                    ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 48),
                child: Text(
                  hasTimeRunOut
                      ? 'Du wurdest vom Spiel getrennt'
                      : 'Prüfe deine Internetverbindung.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                ),
              ),
              if (!hasTimeRunOut) ...[
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Sekunden bis Aufgabe:',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                          ),
                    ),
                    SizedBox(width: 16),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorRed.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: colorRed.withOpacity(0.3), width: 2),
                      ),
                      child: Center(
                        child: Text(
                          remainingSeconds.toString(),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: colorBlack,
                                  ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
