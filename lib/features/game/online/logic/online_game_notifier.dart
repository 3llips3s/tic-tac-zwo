import 'dart:developer' as developer;
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tic_tac_zwo/config/game_config/config.dart';
import 'package:tic_tac_zwo/features/game/core/data/models/game_config.dart';
import 'package:tic_tac_zwo/features/game/core/data/models/german_noun.dart';
import 'package:tic_tac_zwo/features/game/core/data/repositories/german_noun_repo.dart';
import 'package:tic_tac_zwo/features/game/core/logic/game_notifier.dart';
import 'package:tic_tac_zwo/features/game/core/logic/game_state.dart';
import 'package:tic_tac_zwo/features/game/online/data/services/matchmaking_service.dart';
import 'package:tic_tac_zwo/features/game/online/data/services/online_game_service.dart';
import 'package:tic_tac_zwo/features/navigation/logic/navigation_provider.dart';

import '../../../settings/logic/audio_manager.dart';
import '../../core/data/models/player.dart';

class OnlineGameNotifier extends GameNotifier {
  final SupabaseClient supabase;
  Timer? _turnTimer;
  Timer? _rematchOfferTimer;
  Timer? _inactivityTimer;
  Timer? _gracePeriodTimer;
  Timer? _localDisconnectionTimer;

  bool _isInactivityTimerActive = false;
  int _inactivityRemainingSeconds = GameState.turnDurationSeconds;
  int _localDisconnectionRemainingSeconds = 15;

  final String gameSessionId;
  String? currentUserId;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasConnected = true;

  DateTime? _lastUpdateTimestamp;

  StreamSubscription? _gameStateSubscription;
  bool _processingRemoteUpdate = false;
  bool _isLocalPlayerTurn = false;
  bool _isInitialGameLoad = true;
  bool _gameOverHandled = false;
  bool _hasShownDisconnectionOptions = false;

  RealtimeChannel? _gameChannel;

  OnlineGameService get _gameService => ref.read(onlineGameServiceProvider);

  OnlineGameNotifier(Ref ref, GameConfig gameConfig, this.supabase)
      : gameSessionId = gameConfig.gameSessionId ?? '',
        currentUserId = supabase.auth.currentUser?.id,
        super(
          ref,
          gameConfig.players,
          gameConfig.startingPlayer,
          initialOnlineGamePhase: OnlineGamePhase.waiting,
          currentPlayerId: gameConfig.startingPlayer.userId,
          initialLastStarterId: gameConfig.startingPlayer.userId,
        ) {
    _isLocalPlayerTurn = gameConfig.startingPlayer.userId == currentUserId;

    if (gameSessionId.isNotEmpty && currentUserId != null) {
      _listenToGameSessionUpdates();
      _initializePresence();
      _startConnectivityMonitoring();
      _gameService.updateGameSessionState(
        gameSessionId,
        lastStarterId: state.startingPlayer.userId,
      );

      _startInitialDelayTimer();
    } else {
      if (gameSessionId.isEmpty) {
        developer.log(
            '[OnlineGameNotifier] Game Session ID is empty. Cannot initialize online game.');
      }
      if (currentUserId == null) {
        developer.log(
            '[OnlineGameNotifier] Current User ID is null. Cannot initialize online game.');
      }
    }
  }

  void _startConnectivityMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> result) {
        final isConnected = !result.contains(ConnectivityResult.none);

        if (_wasConnected && !isConnected && !state.isGameOver) {
          _startLocalDisconnectionTimer();
        } else if (!_wasConnected && isConnected) {
          _handleReconnection();
        }

        _wasConnected = isConnected;
      },
    );
  }

  Future<void> _handleReconnection() async {
    _cancelLocalDisconnectionTimer();
    _hasShownDisconnectionOptions = false;

    try {
      final latestGameData = await _gameService.getGameSession(gameSessionId);

      if (latestGameData.isEmpty) {
        if (mounted) {
          ref.read(navigationTargetProvider.notifier).state =
              NavigationTarget.home;
        }
        return;
      }

      final isGameOver = latestGameData['is_game_over'] ?? false;
      final gameStatus = GameStatusExtension.fromString(
          latestGameData['status'] ?? 'in_progress');

      if (isGameOver && gameStatus == GameStatus.forfeited) {
        // game ended while disconnected

        if (mounted) {
          state = state.copyWith(
            localConnectionStatus: LocalConnectionStatus.connected,
            isGameOver: true,
            gameStatus: gameStatus,
          );
        }
      } else if (isGameOver) {
        // handle game completing normally while away
        if (mounted) {
          state = state.copyWith(
            localConnectionStatus: LocalConnectionStatus.connected,
            isGameOver: true,
            gameStatus: gameStatus,
          );
        }
      } else {
        // resume normally if game still active
        if (mounted) {
          state = state.copyWith(
            localConnectionStatus: LocalConnectionStatus.connected,
          );
        }
      }
    } catch (e) {
      developer.log('[OnlineGameNotifier] Error handling reconnection: $e');
      // on error, just mark as connected and let normal flow handle it
      if (mounted) {
        state = state.copyWith(
          localConnectionStatus: LocalConnectionStatus.connected,
        );
      }
    }
  }

  void _startInitialDelayTimer() {
    Timer(
      Duration(milliseconds: 3900),
      () {
        if (!mounted) return;
        _isInitialGameLoad = false;

        if (_isLocalPlayerTurn && !state.isGameOver) {
          _startInactivityTimer();
        }
      },
    );
  }

  void _startTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = Timer.periodic(
      Duration(seconds: 1),
      (timer) {
        if (state.remainingSeconds > 0) {
          state = state.copyWith(
            remainingSeconds: state.remainingSeconds - 1,
          );
        } else {
          forfeitTurn();
        }
      },
    );
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _isInactivityTimerActive = true;
    _inactivityRemainingSeconds = GameState.turnDurationSeconds;

    state = state.copyWith(
      remainingSeconds: GameState.turnDurationSeconds,
    );

    _inactivityTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (_inactivityRemainingSeconds > 0) {
          _inactivityRemainingSeconds--;
        } else {
          _handleInactivityTimeout();
        }
      },
    );
  }

  void _handleInactivityTimeout() {
    _inactivityTimer?.cancel();
    _isInactivityTimerActive = false;

    state = state.copyWith(
      isTimerActive: true,
      remainingSeconds: GameState.turnDurationSeconds,
    );
    _startTurnTimer();
  }

  void _cancelInactivityTimer() {
    _inactivityTimer?.cancel();
    _isInactivityTimerActive = false;
    _inactivityRemainingSeconds = GameState.turnDurationSeconds;
  }

  void _startLocalDisconnectionTimer() {
    _localDisconnectionTimer?.cancel();
    _localDisconnectionRemainingSeconds = 15;

    state = state.copyWith(
      localConnectionStatus: LocalConnectionStatus.disconnected,
    );

    _localDisconnectionTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (_localDisconnectionRemainingSeconds > 0) {
          _localDisconnectionRemainingSeconds--;

          if (mounted) {
            state = state.copyWith();
          }
        } else {
          _handleLocalDisconnectionTimeout();
        }
      },
    );
  }

  Future<void> _handleLocalDisconnectionTimeout() async {
    _cancelLocalDisconnectionTimer();

    if (state.isGameOver) return;

    try {
      await supabase.functions.invoke(
        'request-forfeit',
        body: {'gameSessionId': gameSessionId},
      );

      if (mounted) {
        state = state.copyWith(
          isGameOver: true,
          gameStatus: GameStatus.forfeited,
        );

        await Future.delayed(Duration(seconds: 2));
        if (mounted) {
          ref.read(navigationTargetProvider.notifier).state =
              NavigationTarget.home;
        }
      }
    } catch (e) {
      developer.log(
          '[OnlineGameNotifier] Error forfeiting due to disconnection timeout: $e');
      if (mounted) {
        ref.read(navigationTargetProvider.notifier).state =
            NavigationTarget.home;
      }
    }
  }

  void _cancelLocalDisconnectionTimer() {
    _localDisconnectionTimer?.cancel();
    _localDisconnectionRemainingSeconds = 15;
  }

  int get localDisconnectionRemainingSeconds =>
      _localDisconnectionRemainingSeconds;

  void _initializePresence() {
    if (gameSessionId.isEmpty) return;

    _gameChannel = supabase.channel('game:$gameSessionId');

    _gameChannel!.onPresenceJoin((payload) {
      final isOpponent = payload.newPresences
          .any((p) => p.payload['user_id'] != currentUserId);

      if (isOpponent) {
        _gracePeriodTimer?.cancel();
        if (mounted) {
          state = state.copyWith(
              opponentConnectionStatus: OpponentConnectionStatus.connected);
        }
        supabase.functions.invoke('set-disconnection-time',
            body: {'gameSessionId': gameSessionId, 'isConnecting': true});
      }
    }).onPresenceLeave((payload) {
      final isOpponent = payload.leftPresences
          .any((p) => p.payload['user_id'] != currentUserId);

      if (isOpponent && !state.isGameOver && mounted) {
        state = state.copyWith(
            opponentConnectionStatus: OpponentConnectionStatus.reconnecting);

        supabase.functions.invoke('set-disconnection-time',
            body: {'gameSessionId': gameSessionId, 'isConnecting': false});

        _gracePeriodTimer?.cancel();
        _gracePeriodTimer = Timer(const Duration(seconds: 15), () {
          if (mounted &&
              state.opponentConnectionStatus ==
                  OpponentConnectionStatus.reconnecting &&
              !state.isGameOver) {
            _hasShownDisconnectionOptions = true;
            _forfeitOpponentDueToTimeout();
          }
        });
      }
    }).subscribe(
      (status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          // track current user joining the channel + share their id
          await _gameChannel!.track({'user_id': currentUserId});
        }
      },
    );
  }

  Future<void> selectCellOnline(int index) async {
    if (_isInitialGameLoad ||
        state.isGameOver ||
        _processingRemoteUpdate ||
        !_isLocalPlayerTurn ||
        state.board[index] != null ||
        state.selectedCellIndex != null) {
      developer.log(
          '[OnlineGameNotifier] Cannot select cell: Game over, processing remote update, not local player\'s turn, or cell already taken.');
      return;
    }

    _cancelInactivityTimer();

    AudioManager.instance.playClickSound();

    final noun = await ref.read(germanNounRepoProvider).loadRandomNoun();

    // mark noun as seen
    await ref.read(germanNounRepoProvider).markNounAsSeen(noun.id);

    state = state.copyWith(
      selectedCellIndex: index,
      currentNoun: noun,
      isTimerActive: true,
      onlineGamePhase: OnlineGamePhase.cellSelected,
      remainingSeconds: GameState.turnDurationSeconds,
    );

    try {
      await _gameService.updateGameSessionState(
        gameSessionId,
        selectedCellIndex: index,
        currentNounId: noun.id,
        onlineGamePhaseString: OnlineGamePhase.cellSelected.string,
      );
    } catch (e) {
      if (e is FunctionException && e.status == 400) {
        developer.log(
            '[OnlineGameNotifier] Game already over when selecting cell: ${e.details}');
        _handleReconnection();
        return;
      }

      developer.log(
          '[OnlineGameNotifier] Error sending cell selection to server: $e');

      state = state.copyWith(
        selectedCellIndex: null,
        allowNullSelectedCellIndex: true,
        currentNoun: null,
        allowNullCurrentNoun: true,
        isTimerActive: false,
        onlineGamePhase: OnlineGamePhase.waiting,
      );
    }

    if (_isLocalPlayerTurn) {
      _startTurnTimer();
    }
  }

  @override
  Future<void> makeMove(String selectedArticle) async {
    if (state.selectedCellIndex == null ||
        state.currentNoun == null ||
        !_isLocalPlayerTurn ||
        state.isGameOver ||
        _processingRemoteUpdate) {
      developer.log(
          '[OnlineGameNotifier] Cannot make move: Invalid state for making a move.');
      return;
    }

    _turnTimer?.cancel();

    final int cellIndex = state.selectedCellIndex!;
    final GermanNoun currentNoun = state.currentNoun!;
    final bool isCorrectMove = currentNoun.article == selectedArticle;
    final Player previousPlayer = state.currentPlayer;

    var updatedBoard = List<String?>.from(state.board);
    if (isCorrectMove) {
      updatedBoard[cellIndex] = previousPlayer.symbolString;
      AudioManager.instance.playCorrectSound();
    } else {
      AudioManager.instance.playIncorrectSound();
    }

    state = state.copyWith(
      board: updatedBoard,
      revealedArticle: selectedArticle,
      revealedArticleIsCorrect: isCorrectMove,
      articleRevealedAt: DateTime.now(),
      isTimerActive: false,
      onlineGamePhase: OnlineGamePhase.articleRevealed,
      lastPlayedPlayer: previousPlayer,
    );

    final (gameResult, winningPattern) = state.checkWinner(board: updatedBoard);
    final bool isGameOver = gameResult != null;

    await _gameService.recordGameRound(
      gameSessionId,
      playerId: currentUserId!,
      selectedArticle: selectedArticle,
      isCorrect: isCorrectMove,
    );

    if (isGameOver) {
      _handleLocalWinOrDraw(gameResult, winningPattern, updatedBoard);
    } else {
      final Player nextPlayer = state.players
          .firstWhere((player) => player.userId != previousPlayer.userId);

      await _gameService.updateGameSessionState(
        gameSessionId,
        board: updatedBoard,
        currentPlayerId: nextPlayer.userId,
        revealedArticle: selectedArticle,
        revealedArticleIsCorrect: isCorrectMove,
        selectedCellIndex: cellIndex,
        currentNounId: currentNoun.id,
        onlineGamePhaseString: OnlineGamePhase.articleRevealed.string,
      );
    }

    Timer(
      Duration(milliseconds: 1500),
      () async {
        if (!state.isGameOver && mounted) {
          try {
            await _gameService.updateGameSessionState(
              gameSessionId,
              selectedCellIndex: null,
              currentNounId: null,
              revealedArticle: null,
              revealedArticleIsCorrect: null,
              onlineGamePhaseString: OnlineGamePhase.waiting.string,
            );
          } catch (e) {
            developer.log(
                '[OnlineGameNotifier] Error resetting phase to waiting: $e');
          }
        }
      },
    );
  }

  void _handleLocalWinOrDraw(
      String? gameResult, List<int>? winningPattern, List<String?> board) {
    if (_gameOverHandled) return;
    _gameOverHandled = true;

    Player? winner;
    int p1Score = state.player1Score;
    int p2Score = state.player2Score;

    if (gameResult != 'Draw' && gameResult != null) {
      winner = state.players.firstWhere((p) => p.symbolString == gameResult);

      final dbPlayer1Id = state.players[0].userId;
      if (winner.userId == dbPlayer1Id) {
        p1Score++;
      } else {
        p2Score++;
      }
    }

    if (gameResult != 'Draw' &&
        winner != null &&
        winner.userId == currentUserId) {
      AudioManager.instance.playWinSound();
    }

    state = state.copyWith(
      isGameOver: true,
      winningPlayer: winner,
      allowNullWinningPlayer: true,
      winningCells: winningPattern,
      board: board,
      player1Score: p1Score,
      player2Score: p2Score,
      gameStatus: GameStatus.completed,
    );

    _calculatePointsForDialog();

    _gameService.updateGameSessionState(
      gameSessionId,
      isGameOver: true,
      winnerId: winner?.userId,
      board: board,
      player1Score: p1Score,
      player2Score: p2Score,
      gameStatus: 'completed',
    );
  }

  void _handleRemoteWinOrDraw() {
    if (_gameOverHandled) return;
    _gameOverHandled = true;
    _calculatePointsForDialog();
  }

  void _calculatePointsForDialog() async {
    if (currentUserId == null) return;
    final correctMoves =
        await _gameService.getCorrectMoves(gameSessionId, currentUserId!);
    int pointsPerGame = correctMoves;

    if (state.gameStatus == GameStatus.completed) {
      if (state.winningPlayer?.userId == currentUserId) {
        pointsPerGame += 3;
      } else if (state.winningPlayer == null) {
        pointsPerGame += 1;
      }
    }

    if (mounted) {
      state = state.copyWith(pointsEarnedPerGame: pointsPerGame);
    }
  }

  @override
  Future<void> forfeitTurn() async {
    _turnTimer?.cancel();
    _cancelInactivityTimer();

    if (!_isLocalPlayerTurn || _processingRemoteUpdate || state.isGameOver) {
      developer.log(
          '[OnlineGameNotifier] Cannot forfeit turn: Invalid state for forfeiture.');
      return;
    }

    state = state.copyWith(
      selectedCellIndex: null,
      allowNullSelectedCellIndex: true,
      currentNoun: null,
      allowNullCurrentNoun: true,
      isTimerActive: false,
      onlineGamePhase: OnlineGamePhase.waiting,
    );

    developer.log(
        '[DEBUG FORFEIT] Phase: ${state.onlineGamePhase}, SelectedIndex: ${state.selectedCellIndex}');

    final Player previousPlayer = state.currentPlayer;
    final Player nextPlayer = state.players
        .firstWhere((player) => player.userId != previousPlayer.userId);

    await _gameService.updateGameSessionState(
      gameSessionId,
      currentPlayerId: nextPlayer.userId,
      onlineGamePhaseString: OnlineGamePhase.waiting.string,
      selectedCellIndex: null,
      currentNounId: null,
      revealedArticle: null,
      revealedArticleIsCorrect: null,
    );

    await _gameService.recordGameRound(
      gameSessionId,
      playerId: currentUserId!,
      selectedArticle: null,
      isCorrect: false,
    );
  }

  void _listenToGameSessionUpdates() {
    _gameStateSubscription =
        _gameService.getGameStateStream(gameSessionId).listen((gameData) async {
      final newTimeStamp = gameData['updated_at'] != null
          ? DateTime.tryParse(gameData['updated_at'])
          : null;

      if (newTimeStamp != null &&
          _lastUpdateTimestamp != null &&
          (newTimeStamp.isBefore(_lastUpdateTimestamp!) ||
              newTimeStamp == _lastUpdateTimestamp)) {
        return;
      }

      _processingRemoteUpdate = true;

      _lastUpdateTimestamp = newTimeStamp;

      try {
        await _handleRemoteUpdate(gameData);
      } catch (e) {
        developer.log('Error handling remote update: $e');
      }
      _processingRemoteUpdate = false;
    }, onError: (e) {
      developer.log('[OnlineGameNotifier] Error listening to game session: $e');
      _processingRemoteUpdate = false;
    });
  }

  Future<void> _handleRemoteUpdate(Map<String, dynamic> gameData) async {
    if (!mounted) return;

    final GameState previousState = state;

    final int? newSelectedCell = gameData['selected_cell_index'];
    if (newSelectedCell != null &&
        previousState.selectedCellIndex != newSelectedCell) {
      AudioManager.instance.playClickSound();
    }

    // detect article reveal
    final String? newRevealedArticle = gameData['revealed_article'];
    final bool? isCorrect = gameData['revealed_article_is_correct'];

    if (newRevealedArticle != null &&
        previousState.revealedArticle == null &&
        isCorrect != null) {
      if (isCorrect) {
        AudioManager.instance.playCorrectSound();
      } else {
        AudioManager.instance.playIncorrectSound();
      }
    }

    final String? serverCurrentPlayerId = gameData['current_player_id'];
    final bool wasLocalPlayerTurn = _isLocalPlayerTurn;
    _isLocalPlayerTurn = serverCurrentPlayerId == currentUserId;

    if (_isLocalPlayerTurn != wasLocalPlayerTurn) {
      if (_isLocalPlayerTurn && !state.isGameOver) {
        // check incoming server phase
        OnlineGamePhase serverPhase =
            OnlineGamePhaseExtension.fromString(gameData['online_game_phase']);
        developer.log('[DEBUG TURN CHANGE] serverPhase: $serverPhase');

        if (!_isInitialGameLoad) {
          _startInactivityTimer();
        } else {
          developer.log(
              '[DEBUG TURN CHANGE] Skipping inactivity timer - still initial load');
        }
      } else if (!_isLocalPlayerTurn) {
        _cancelInactivityTimer();
        _turnTimer?.cancel();
      }
    }

    OnlineGamePhase serverPhase =
        OnlineGamePhaseExtension.fromString(gameData['online_game_phase']);

    final int? incomingSelectedCellIndex = gameData['selected_cell_index'];
    final int? selectedCellToApply = (serverPhase == OnlineGamePhase.waiting)
        ? null
        : incomingSelectedCellIndex;

    GermanNoun? noun;
    final String? currentNounId = gameData['current_noun_id'];

    if (currentNounId != null && currentNounId != state.currentNoun?.id) {
      final currentNoun =
          await ref.read(germanNounRepoProvider).getNounById(currentNounId);
      noun = currentNoun;
    } else if (currentNounId == null) {
      noun = null;
    } else {
      noun = state.currentNoun;
    }

    bool serverIsGameOver = gameData['is_game_over'] ?? false;
    GameStatus serverGameStatus =
        GameStatusExtension.fromString(gameData['status'] ?? 'in_progress');

    if (serverIsGameOver && serverGameStatus == GameStatus.inProgress) {
      serverGameStatus = GameStatus.completed;
    }

    // handle rematch logic
    OnlineRematchStatus newOnlineRematchStatus = OnlineRematchStatus.none;

    if (serverIsGameOver) {
      final p1Ready = gameData['player1_ready'] ?? false;
      final p2Ready = gameData['player2_ready'] ?? false;
      final String? dbPlayer1Id = gameData['player1_id'];
      final localUserIsDbPlayer1 = dbPlayer1Id == currentUserId;

      final localPlayerWantsRematch = localUserIsDbPlayer1 ? p1Ready : p2Ready;
      final remotePlayerWantsRematch = localUserIsDbPlayer1 ? p2Ready : p1Ready;

      if (localPlayerWantsRematch && remotePlayerWantsRematch) {
        newOnlineRematchStatus = OnlineRematchStatus.bothAccepted;
      } else if (localPlayerWantsRematch) {
        newOnlineRematchStatus = OnlineRematchStatus.localOffered;
      } else if (remotePlayerWantsRematch) {
        newOnlineRematchStatus = OnlineRematchStatus.remoteOffered;
      } else {
        newOnlineRematchStatus = OnlineRematchStatus.none;
      }
    }

    // update state with incoming data
    state = state.copyWith(
      board: List<String?>.from(gameData['board'] ?? List.filled(9, null)),
      selectedCellIndex: selectedCellToApply,
      allowNullSelectedCellIndex: true,
      currentNoun: noun,
      allowNullCurrentNoun: true,
      isGameOver: serverIsGameOver,
      winningPlayer: gameData['winner_id'] != null
          ? state.players.firstWhere(
              (player) => player.userId == gameData['winner_id'],
            )
          : null,
      allowNullWinningPlayer: true,
      currentPlayerId: serverCurrentPlayerId,
      revealedArticle: gameData['revealed_article'],
      allowNullRevealedArticle: true,
      revealedArticleIsCorrect: gameData['revealed_article_is_correct'],
      allowNullRevealedArticleIsCorrect: true,
      articleRevealedAt: (gameData['revealed_article'] != null &&
              serverPhase == OnlineGamePhase.articleRevealed)
          ? DateTime.now()
          : null,
      allowNullArticleRevealedAt: true,
      player1Score: gameData['player1_score'] ?? previousState.player1Score,
      player2Score: gameData['player2_score'] ?? previousState.player2Score,
      isTimerActive:
          _isLocalPlayerTurn && (serverPhase == OnlineGamePhase.cellSelected),
      onlineGamePhase: serverPhase,
      lastStarterId: gameData['last_starter_id'] ?? state.lastStarterId,
      gameStatus: serverGameStatus,
      onlineRematchStatus: newOnlineRematchStatus,
    );

    if (serverIsGameOver &&
        serverGameStatus == GameStatus.forfeited &&
        !previousState.isGameOver) {
      state = state.copyWith(
        opponentConnectionStatus: OpponentConnectionStatus.forfeited,
      );

      _calculatePointsForDialog();
    }

    if (state.isGameOver && !previousState.isGameOver) {
      _handleRemoteWinOrDraw();
    }

    if (state.onlineRematchStatus == OnlineRematchStatus.bothAccepted &&
        previousState.onlineRematchStatus != OnlineRematchStatus.bothAccepted) {
      initiateNewGameAfterRematch();
    }

    // reset ui and symbols for rematch
    if (!serverIsGameOver && previousState.isGameOver) {
      _gameOverHandled = false;

      final String? dbPlayer1Id = gameData['player1_id'];
      final String? dbPlayer2Id = gameData['player2_id'];

      if (dbPlayer1Id == null || dbPlayer2Id == null) {
        developer.log(
            '[OnlineGameNotifier] Missing player IDs during rematch reset');
      }

      final Player dbPlayer1 = state.players.firstWhere(
        (player) => player.userId == dbPlayer1Id,
        orElse: () => state.players[0],
      );
      final Player dbPlayer2 = state.players.firstWhere(
        (player) => player.userId == dbPlayer2Id,
        orElse: () => state.players[1],
      );

      final newStarterId = gameData['last_starter_id'] ?? state.lastStarterId;

      final Player starter =
          dbPlayer1.userId == newStarterId ? dbPlayer1 : dbPlayer2;
      final Player other =
          dbPlayer1.userId == newStarterId ? dbPlayer2 : dbPlayer1;

      final List<Player> newPlayersList = [
        starter.copyWith(symbol: PlayerSymbol.X),
        other.copyWith(symbol: PlayerSymbol.O),
      ];

      final newStartingPlayer =
          newPlayersList.firstWhere((player) => player.userId == newStarterId);

      state = state.copyWith(
        pointsEarnedPerGame: null,
        allowNullPointsEarnedPerGame: true,
        winningCells: null,
        winningPlayer: null,
        allowNullWinningPlayer: true,
        players: newPlayersList,
        startingPlayer: newStartingPlayer,
      );

      Timer(Duration(milliseconds: 3900), () {
        if (!mounted) return;
        _isInitialGameLoad = false;

        if (_isLocalPlayerTurn && !state.isGameOver) {
          _startInactivityTimer();
        }
      });
    }
  }

  // rematch methods
  Future<void> requestRematch() async {
    if (!state.isGameOver || currentUserId == null) return;
    await _gameService.setPlayerRematchStatus(
        gameSessionId, currentUserId!, true);
  }

  Future<void> cancelRematchRequest() async {
    if (!state.isGameOver || currentUserId == null) return;
    await _gameService.setPlayerRematchStatus(
        gameSessionId, currentUserId!, false);
  }

  Future<void> acceptRematch() async {
    if (!state.isGameOver || currentUserId == null) return;
    await _gameService.setPlayerRematchStatus(
        gameSessionId, currentUserId!, true);
  }

  Future<void> declineRematch() async {
    if (!state.isGameOver || currentUserId == null) return;
    await _gameService.setPlayerRematchStatus(
        gameSessionId, currentUserId!, false);
  }

  Future<void> initiateNewGameAfterRematch() async {
    if (state.lastStarterId == null) return;

    _rematchOfferTimer?.cancel();

    // The new starter is the one who was NOT the last starter.
    final newStarterId = state.players
        .firstWhere((p) => p.userId != state.lastStarterId)
        .userId!;

    try {
      await _gameService.resetSessionForRematch(gameSessionId, newStarterId);
    } catch (e) {
      developer.log(
          "[OnlineGameNotifier] Error initiating new game after rematch: $e");
    }
  }

  Future<void> requestForfeit() async {
    if (state.isGameOver) return;

    try {
      if (mounted) {
        state = state.copyWith(
          gameStatus: GameStatus.forfeited,
        );
      }

      _turnTimer?.cancel();
      _inactivityTimer?.cancel();
      _rematchOfferTimer?.cancel();
      _gracePeriodTimer?.cancel();
      _localDisconnectionTimer?.cancel();

      await supabase.functions.invoke(
        'request-forfeit',
        body: {'gameSessionId': gameSessionId},
      );

      if (mounted) {
        await Future.delayed(Duration(milliseconds: 300));

        // navigate home after successful forfeit
        ref.read(navigationTargetProvider.notifier).state =
            NavigationTarget.home;
      }
    } catch (e) {
      developer.log('Error forfeiting game:$e');
      if (mounted) {
        // navigate home after successful forfeit
        ref.read(navigationTargetProvider.notifier).state =
            NavigationTarget.home;
      }
    }
  }

  Future<void> _forfeitOpponentDueToTimeout() async {
    if (state.isGameOver) return;
    try {
      await supabase.functions.invoke(
        'request-forfeit',
        body: {'gameSessionId': gameSessionId},
      );
    } catch (e) {
      if (e is FunctionException && e.status == 400) {
        developer.log(
            '[OnlineGameNotifier] Game already over when trying to forfeit opponent: ${e.details}');
        _handleReconnection();
      } else {
        developer.log('Error forfeiting opponent due to timeout:$e');
      }
    }
  }

  Future<void> findNewOpponent() async {
    if (currentUserId != null) {
      await _gameService.setPlayerRematchStatus(
          gameSessionId, currentUserId!, false);
    }
    ref.read(navigationTargetProvider.notifier).state =
        NavigationTarget.matchmaking;
  }

  Future<void> goHomeAndCleanupSession() async {
    if (currentUserId != null) {
      await _gameService.setPlayerRematchStatus(
          gameSessionId, currentUserId!, false);
    }
    ref.read(navigationTargetProvider.notifier).state = NavigationTarget.home;
  }

  TimerDisplayState get timerDisplayState {
    if (state.isGameOver || !_isLocalPlayerTurn) {
      return TimerDisplayState.static;
    }
    if (state.selectedCellIndex != null) {
      return state.isTimerActive
          ? TimerDisplayState.countdown
          : TimerDisplayState.static;
    }
    return _isInactivityTimerActive
        ? TimerDisplayState.inactivity
        : TimerDisplayState.static;
  }

  bool get canLocalPlayerMakeMove {
    final result =
        _isLocalPlayerTurn && !state.isGameOver && !_processingRemoteUpdate;
    return result;
  }

  bool get isInactivityTimerActive => _isInactivityTimerActive;

  bool get hasShownDisconnectionOptions => _hasShownDisconnectionOptions;

  @override
  void dispose() {
    _turnTimer?.cancel();
    _inactivityTimer?.cancel();
    _rematchOfferTimer?.cancel();
    _localDisconnectionTimer?.cancel();
    _gracePeriodTimer?.cancel();
    _connectivitySubscription?.cancel();
    _gameStateSubscription?.cancel();
    _gameStateSubscription = null;
    if (_gameChannel != null) {
      supabase.removeChannel(_gameChannel!);
      _gameChannel = null;
    }
    final gameService = ref.read(onlineGameServiceProvider);
    if (gameSessionId.isNotEmpty) {
      gameService.clientDisposeGameSessionResources(gameSessionId);
    }
    super.dispose();
  }
}

// providers
final onlineGameStateNotifierProvider =
    StateNotifierProvider.family<OnlineGameNotifier, GameState, GameConfig>(
  (ref, config) {
    final supabase = ref.watch(supabaseProvider);
    return OnlineGameNotifier(ref, config, supabase);
  },
);
