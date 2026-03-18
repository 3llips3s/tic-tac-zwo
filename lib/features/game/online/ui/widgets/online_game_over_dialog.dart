import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tic_tac_zwo/config/game_config/config.dart';
import 'package:tic_tac_zwo/config/game_config/game_providers.dart';
import 'package:tic_tac_zwo/features/auth/logic/auth_providers.dart';
import 'package:tic_tac_zwo/features/game/core/data/models/game_config.dart';
import 'package:tic_tac_zwo/features/game/core/ui/widgets/glassmorphic_dialog.dart';
import 'package:tic_tac_zwo/features/game/online/logic/online_game_notifier.dart';

import '../../../../../config/game_config/constants.dart';

class _OnlineGameOverDialogContent extends ConsumerStatefulWidget {
  final GameConfig gameConfig;
  const _OnlineGameOverDialogContent({required this.gameConfig});

  @override
  ConsumerState<_OnlineGameOverDialogContent> createState() =>
      _OnlineGameOverDialogContentState();
}

class _OnlineGameOverDialogContentState
    extends ConsumerState<_OnlineGameOverDialogContent> {
  late OnlineRematchStatus _uiStatus;

  @override
  void initState() {
    super.initState();
    _uiStatus = ref
        .read(GameProviders.getStateProvider(ref, widget.gameConfig))
        .onlineRematchStatus;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<OnlineRematchStatus>(
      GameProviders.getStateProvider(ref, widget.gameConfig)
          .select((state) => state.onlineRematchStatus),
      (previous, next) {
        if (_uiStatus != OnlineRematchStatus.bothAccepted) {
          if (mounted) {
            setState(() {
              _uiStatus = next;
            });
          }
        }
      },
    );

    Widget currentView;

    if (_uiStatus == OnlineRematchStatus.localOffered ||
        _uiStatus == OnlineRematchStatus.remoteOffered ||
        _uiStatus == OnlineRematchStatus.bothAccepted) {
      currentView = _OnlineRematchStatusView(
          key: const ValueKey('rematch_view'), gameConfig: widget.gameConfig);
    } else {
      currentView = _InitialGameOverView(
          key: const ValueKey('initial_view'), gameConfig: widget.gameConfig);
    }

    return AnimatedSwitcher(
      duration: 600.ms,
      reverseDuration: 600.ms,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: currentView,
    );
  }
}

class _InitialGameOverView extends ConsumerWidget {
  final GameConfig gameConfig;
  const _InitialGameOverView({super.key, required this.gameConfig});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState =
        ref.watch(GameProviders.getStateProvider(ref, gameConfig));
    final notifier =
        ref.read(GameProviders.getStateProvider(ref, gameConfig).notifier)
            as OnlineGameNotifier;
    final localPlayerId = ref.watch(currentUserIdProvider);

    String title;
    if (gameState.winningPlayer != null) {
      title = gameState.winningPlayer!.userId == localPlayerId
          ? 'Du gewinnst!'
          : '${gameState.winningPlayer!.username} gewinnt!';
    } else {
      title = 'Unentschieden!';
    }

    final dbPlayer1Id = gameState.players[0].userId;
    final localPlayerIsDbPlayer1 = dbPlayer1Id == localPlayerId;

    final localScore = localPlayerIsDbPlayer1
        ? gameState.player1Score
        : gameState.player2Score;
    final opponentScore = localPlayerIsDbPlayer1
        ? gameState.player2Score
        : gameState.player1Score;

    final pointsEarned = gameState.pointsEarnedPerGame;

    return Stack(
      children: [
        Container(
          height: 280,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              SizedBox(height: 28),
              // game outcome
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      fontSize: 20,
                    ),
              ),

              // scores and points earned
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 40),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$localScore - $opponentScore',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  if (pointsEarned != null)
                    _displayPointsEarned(pointsEarned)
                  else
                    const SizedBox(width: 40),
                ],
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  GlassMorphicButton(
                    onPressed: () => notifier.findNewOpponent(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12.0, vertical: 6.0),
                      child: const Icon(
                        Icons.search_rounded,
                        color: Colors.black87,
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  GlassMorphicButton(
                    onPressed: () => notifier.requestRematch(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12.0, vertical: 6.0),
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: colorYellowAccent,
                        size: 30,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: IconButton(
            icon: Icon(
              Icons.home_rounded,
              color: colorRed.withOpacity(0.7),
              size: 36,
            ),
            onPressed: () => notifier.goHomeAndCleanupSession(),
          ),
        ),
      ],
    );
  }

  Widget _displayPointsEarned(int points) {
    return Text(
      '+ $points',
      style: TextStyle(
        fontSize: 22,
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
        .shake(hz: 5, duration: 600.ms, curve: Curves.easeInOut);
  }
}

class _OnlineRematchStatusView extends ConsumerWidget {
  final GameConfig gameConfig;
  const _OnlineRematchStatusView({super.key, required this.gameConfig});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState =
        ref.watch(GameProviders.getStateProvider(ref, gameConfig));
    final notifier =
        ref.watch(GameProviders.getStateProvider(ref, gameConfig).notifier)
            as OnlineGameNotifier;
    final localUserId = ref.watch(currentUserIdProvider);

    final opponent =
        gameState.players.firstWhere((player) => player.userId != localUserId);
    final opponentName = opponent.username;

    String message = '';
    List<Widget> actionButtons = [];

    switch (gameState.onlineRematchStatus) {
      case OnlineRematchStatus.localOffered:
        message = 'Warte auf $opponentName...';
        actionButtons = [
          GlassMorphicButton(
            onPressed: () => notifier.cancelRematchRequest(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Text(
              'Abbrechen',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black87,
                    fontSize: 18,
                  ),
            ),
          ),
        ];
        break;
      case OnlineRematchStatus.remoteOffered:
        message = '$opponentName möchte eine Revanche!';
        actionButtons = [
          GlassMorphicButton(
            onPressed: () => notifier.declineRematch(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Icon(
              Icons.close_rounded,
              color: colorBlack,
              size: 30,
            ),
          ),
          const SizedBox(width: 40),
          GlassMorphicButton(
            onPressed: () => notifier.acceptRematch(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Icon(
              Icons.check_rounded,
              color: colorYellowAccent,
              size: 30,
            ),
          ),
        ];
        break;
      case OnlineRematchStatus.bothAccepted:
        message = 'Lade neues Spiel...';
      default:
        message = 'Status wird geladen...';
        break;
    }

    return Stack(
      children: [
        Container(
          height: 280,
          padding: const EdgeInsets.fromLTRB(16, 112, 16, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // rematch status
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color:
                          _rematchMessageColor(gameState.onlineRematchStatus),
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: actionButtons,
              ),
            ],
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => notifier.goHomeAndCleanupSession(),
                icon: Icon(
                  Icons.home_rounded,
                  color: colorRed.withOpacity(0.5),
                  size: 30,
                ),
              ),
              SizedBox(height: 8),
              IconButton(
                onPressed: () => notifier.findNewOpponent(),
                icon: Icon(
                  Icons.search_rounded,
                  color: colorBlack.withOpacity(0.5),
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _rematchMessageColor(OnlineRematchStatus status) {
    switch (status) {
      case OnlineRematchStatus.localOffered:
        return Colors.black54;
      case OnlineRematchStatus.remoteOffered:
        return colorDarkGreen;
      case OnlineRematchStatus.bothAccepted:
        return Colors.lightGreenAccent;
      default:
        return Colors.blueGrey;
    }
  }
}

void showOnlineGameOverDialog(
  BuildContext context,
  WidgetRef ref,
  GameConfig gameConfig,
) async {
  await Future.delayed(const Duration(milliseconds: 600));

  final currentGameState =
      ref.read(GameProviders.getStateProvider(ref, gameConfig));

  if (context.mounted && currentGameState.isGameOver) {
    await showCustomDialog(
        context: context,
        height: 320,
        width: 320,
        child: _OnlineGameOverDialogContent(gameConfig: gameConfig));
  }
}
