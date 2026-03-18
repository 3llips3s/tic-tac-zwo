import 'dart:developer' as developer;
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tic_tac_zwo/features/game/online/data/services/matchmaking_service.dart';

import '../../../../../config/game_config/config.dart';

class OnlineGameService {
  final SupabaseClient _supabase;

  // stream subscriptions
  final Map<String, StreamSubscription> _gameStreamSubscriptions = {};

  // Cache for last received data to prevent redundant processing if Supabase stream sends duplicates
  final Map<String, Map<String, dynamic>> _lastReceivedStreamData = {};

  // Debounce timers for updates to Supabase
  final Map<String, Timer> _updateDebounceTimers = {};

  OnlineGameService(this._supabase);

  String? get _localUserId => _supabase.auth.currentUser?.id;

  Future<void> setPlayerReady(String gameSessionId) async {
    if (_localUserId == null) {
      developer.log(
          '[OnlineGameService] setPlayerReady: Local user ID is null. Cannot set ready state.');
      return;
    }

    try {
      // fetch game sessions
      final gameSession = await _supabase
          .from('game_sessions')
          .select('player1_id, player2_id')
          .eq('id', gameSessionId)
          .single();

      final isPlayerOne = gameSession['player1_id'] == _localUserId;
      final readyField = isPlayerOne ? 'player1_ready' : 'player2_ready';

      developer.log(
          '[OnlineGameService] Setting player ready: $_localUserId (${isPlayerOne ? 'player1' : 'player2'}) in session $gameSessionId.');

      // update ready field
      await _supabase.from('game_sessions').update({
        readyField: true,
      }).eq('id', gameSessionId);
    } catch (e) {
      developer.log(
          '[OnlineGameService] Error setting player ready for session $gameSessionId: $e');
    }
  }

  Future<void> setPlayerNotReady(String gameSessionId) async {
    if (_localUserId == null) {
      developer
          .log('[OnlineGameService] setPlayerNotReady: Local user ID is null.');
      return;
    }

    try {
      // fetch game sessions
      final gameSession = await _supabase
          .from('game_sessions')
          .select('player1_id, player2_id')
          .eq('id', gameSessionId)
          .single();

      final isPlayerOne = gameSession['player1_id'] == _localUserId;
      final readyField = isPlayerOne ? 'player1_ready' : 'player2_ready';

      // update ready field
      await _supabase.from('game_sessions').update({
        readyField: false,
      }).eq('id', gameSessionId);
      developer.log(
          '[OnlineGameService] Player $_localUserId set to not ready for session $gameSessionId.');
    } catch (e) {
      developer.log(
          '[OnlineGameService] Error setting player not ready for session $gameSessionId: $e');
    }
  }

  // stream for general game state updates
  Stream<Map<String, dynamic>> getGameStateStream(String gameSessionId) {
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final String streamKey = 'gameState_$gameSessionId';

    _gameStreamSubscriptions[streamKey]?.cancel();

    developer.log(
        '[OnlineGameService] Setting up game state stream for session: $gameSessionId');

    _gameStreamSubscriptions[streamKey] = _supabase
        .from('game_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', gameSessionId)
        .listen((dataList) {
          if (controller.isClosed) return;

          if (dataList.isEmpty) {
            developer.log(
                '[OnlineGameService] Game state stream for $gameSessionId received empty data list.');
            // handle as error / session ended
            return;
          }

          final gameData = dataList.first;
          developer.log(
              '[OnlineGameService] RAW STREAM DATA RECEIVED for $gameSessionId: $gameData');

          // Prevent processing identical consecutive updates if Supabase sends them
          final String lastDataKey = 'lastStreamData_$gameSessionId';
          final lastData = _lastReceivedStreamData[lastDataKey];

          if (lastData != null &&
              lastData['updated_at'] == gameData['updated_at'] &&
              _areMapsEqual(lastData, gameData)) {
            return;
          }

          _lastReceivedStreamData[lastDataKey] =
              Map<String, dynamic>.from(gameData);
          controller.add(Map<String, dynamic>.from(gameData));
        }, onError: (error) {
          developer.log('Error in game state stream: $error');
          controller.addError(error);
        });

    return controller.stream;
  }

  // Helper to compare values
  bool _areMapsEqual(Map<String, dynamic> map1, Map<String, dynamic> map2) {
    if (map1.length != map2.length) return false;
    for (final key in map1.keys) {
      if (!map2.containsKey(key)) return false;

      if (key == 'board') {
        if (map1[key].toString() != map2[key].toString()) return false;
      } else if (map1[key] != map2[key]) {
        return false;
      }
    }
    return true;
  }

// fetch game session
  Future<Map<String, dynamic>> getGameSession(String gameSessionId) async {
    try {
      developer
          .log('[OnlineGameService] Fetching game session: $gameSessionId');

      final response = await _supabase
          .from('game_sessions')
          .select()
          .eq('id', gameSessionId)
          .single();
      return response;
    } catch (e) {
      developer.log(
          '[OnlineGameService] Error getting game session $gameSessionId: $e');
      return {};
    }
  }

  // update game state after a move
  Future<void> updateGameSessionState(
    String gameSessionId, {
    List<String?>? board,
    dynamic selectedCellIndex,
    String? currentPlayerId,
    dynamic currentNounId,
    bool? isGameOver,
    dynamic winnerId,
    String? revealedArticle,
    bool? revealedArticleIsCorrect,
    String? onlineGamePhaseString,
    String? lastStarterId,
    bool? player1Ready,
    bool? player2Ready,
    int? player1Score,
    int? player2Score,
    String? gameStatus,
  }) async {
    const debounceDuration = Duration(milliseconds: 100);

    if (_updateDebounceTimers[gameSessionId]?.isActive ?? false) {
      _updateDebounceTimers[gameSessionId]!.cancel();
    }

    _updateDebounceTimers[gameSessionId] = Timer(debounceDuration, () async {
      try {
        // prevent empty updates
        final updatePayload = <String, dynamic>{};

        if (board != null) updatePayload['board'] = board;
        updatePayload['selected_cell_index'] = selectedCellIndex;
        updatePayload['current_noun_id'] = currentNounId;
        updatePayload['winner_id'] = winnerId;
        updatePayload['revealed_article'] = revealedArticle;
        updatePayload['revealed_article_is_correct'] = revealedArticleIsCorrect;

        if (currentPlayerId != null) {
          updatePayload['current_player_id'] = currentPlayerId;
        }

        if (onlineGamePhaseString != null) {
          updatePayload['online_game_phase'] = onlineGamePhaseString;
        }

        if (lastStarterId != null) {
          updatePayload['last_starter_id'] = lastStarterId;
        }

        if (gameStatus != null) {
          updatePayload['status'] = gameStatus;
        }

        if (isGameOver != null) {
          updatePayload['is_game_over'] = isGameOver;
          if (isGameOver == true) {
            updatePayload['status'] = 'completed';
            updatePayload['player1_ready'] = false;
            updatePayload['player2_ready'] = false;
          }
        }

        if (winnerId != null) {
          updatePayload['winner_id'] = winnerId;
        }

        if (player1Score != null) updatePayload['player1_score'] = player1Score;
        if (player2Score != null) updatePayload['player2_score'] = player2Score;

        if (player1Ready != null) updatePayload['player1_ready'] = player1Ready;
        if (player2Ready != null) updatePayload['player2_ready'] = player2Ready;
        updatePayload['updated_at'] = DateTime.now().toIso8601String();

        int meaningfulKeysCount = 0;
        updatePayload.forEach(
          (key, value) {
            if (key != 'updated_at') {
              meaningfulKeysCount++;
            }
          },
        );
        if (meaningfulKeysCount == 0) {
          developer.log(
              '[OnlineGameService] updateGameState for $gameSessionId: No actual game data to update (besides meta activity/timestamp). Skipping DB call.');
          return;
        }

        if (updatePayload.isEmpty) {
          return;
        }

        developer.log(
            '[OnlineGameService] Debounced update executing for $gameSessionId. Payload: $updatePayload');

        await _supabase
            .from('game_sessions')
            .update(updatePayload)
            .eq('id', gameSessionId);

        developer.log(
            '[OnlineGameService] Game state update completed via debounce for $gameSessionId.');
      } catch (e) {
        developer.log(
            '[OnlineGameService] Error in debounced game state update for $gameSessionId: $e');
      }
    });
  }

  // record game move
  Future<void> recordGameRound(
    String gameSessionId, {
    required String playerId,
    required String? selectedArticle,
    required bool isCorrect,
  }) async {
    try {
      developer.log(
          '[OnlineGameService] Recording game round for session $gameSessionId, player $playerId.');

      await _supabase.from('game_rounds').insert({
        'game_id': gameSessionId,
        'player_id': playerId,
        'selected_article': selectedArticle,
        'is_correct': isCorrect,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      developer.log(
          '[OnlineGameService] Error recording game round for session $gameSessionId: $e');
    }
  }

  // fetch points per round
  Future<int> getCorrectMoves(String gameSessionId, String playerId) async {
    try {
      final sessionData = await _supabase
          .from('game_sessions')
          .select('current_game_started_at')
          .eq('id', gameSessionId)
          .single();

      final String? gameStartTime = sessionData['current_game_started_at'];

      if (gameStartTime == null) return 0;

      final count = await _supabase
          .from('game_rounds')
          .count(CountOption.exact)
          .eq('game_id', gameSessionId)
          .eq('player_id', playerId)
          .eq('is_correct', true)
          .gt('created_at', gameStartTime);

      return count;
    } catch (e) {
      developer.log(
          '[OnlineGameService] Error fetching correct moves for player $playerId: $e');
      return 0;
    }
  }

  Future<void> setPlayerRematchStatus(
      String gameSessionId, String playerIdToSetReady, bool isReady) async {
    final sessionDetails = await _supabase
        .from('game_sessions')
        .select('player1_id, player2_id')
        .eq('id', gameSessionId)
        .single();

    String? readyFieldKey;
    if (sessionDetails['player1_id'] == playerIdToSetReady) {
      readyFieldKey = 'player1_ready';
    } else if (sessionDetails['player2_id'] == playerIdToSetReady) {
      readyFieldKey = 'player2_ready';
    }

    if (readyFieldKey == null) return;

    try {
      developer.log(
          '[OnlineGameService] Setting $readyFieldKey to $isReady for session $gameSessionId.');
      await _supabase.from('game_sessions').update({
        readyFieldKey: isReady,
      }).eq('id', gameSessionId);
    } catch (e) {
      developer.log(
          '[OnlineGameService] Error setting player rematch status for session $gameSessionId: $e');
    }
  }

  Future<void> resetSessionForRematch(
      String gameSessionId, String newStarterId) async {
    if (_updateDebounceTimers[gameSessionId]?.isActive ?? false) {
      _updateDebounceTimers[gameSessionId]!.cancel();
    }
    _updateDebounceTimers.remove(gameSessionId);
    try {
      developer.log(
          '[OnlineGameService] Resetting session $gameSessionId for rematch. New starter: $newStarterId.');

      final currentSession = await _supabase
          .from('game_sessions')
          .select('player1_score, player2_score')
          .eq('id', gameSessionId)
          .single();

      await _supabase.from('game_sessions').update({
        'board': List.filled(9, null),
        'selected_cell_index': null,
        'current_noun_id': null,
        'is_game_over': false,
        'winner_id': null,
        'revealed_article': null,
        'revealed_article_is_correct': null,
        'current_player_id': newStarterId,
        'last_starter_id': newStarterId,
        'player1_ready': false,
        'player2_ready': false,
        'online_game_phase': OnlineGamePhase.waiting.string,
        'current_game_started_at': DateTime.now().toIso8601String(),
        'status': 'in_progress',
        'player1_score': currentSession['player1_score'] ?? 0,
        'player2_score': currentSession['player2_score'] ?? 0,
      }).eq('id', gameSessionId);
      developer.log(
          '[OnlineGameService] Session $gameSessionId reset successfully.');
    } catch (e) {
      developer.log(
          '[OnlineGameService] Error resetting session $gameSessionId for rematch: $e');
    }
  }

  // clean up subs
  void clientDisposeGameSessionResources(String gameSessionId) {
    developer.log(
        '[OnlineGameService] Disposing client-specific resources for game session $gameSessionId.');

    final gameStateStreamKey = 'gameState_$gameSessionId';

    _gameStreamSubscriptions[gameStateStreamKey]?.cancel();
    _gameStreamSubscriptions.remove(gameStateStreamKey);
    _lastReceivedStreamData.remove('lastStreamData_$gameSessionId');

    _updateDebounceTimers[gameSessionId]?.cancel();
    _updateDebounceTimers.remove(gameSessionId);
  }

  // dispose subs
  void dispose() {
    for (var timer in _updateDebounceTimers.values) {
      timer.cancel();
    }
    _updateDebounceTimers.clear();

    for (var subscription in _gameStreamSubscriptions.values) {
      subscription.cancel();
    }
    _gameStreamSubscriptions.clear();
    _lastReceivedStreamData.clear();
  }
}

// providers
final onlineGameServiceProvider = Provider(
  (ref) {
    final supabase = ref.watch(supabaseProvider);
    final service = OnlineGameService(supabase);
    ref.onDispose(() => service.dispose());
    return service;
  },
);

final onlineGameStateProvider =
    StreamProvider.family<Map<String, dynamic>, String>(
  (ref, gameSessionId) {
    final service = ref.watch(onlineGameServiceProvider);
    return service.getGameStateStream(gameSessionId);
  },
);
