import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';

import 'settings_notifier.dart';

class AudioManager {
  static AudioManager? _instance;
  static AudioManager get instance {
    _instance ??= AudioManager._();
    return _instance!;
  }

  AudioManager._();

  late AudioPlayer _musicPlayer;
  late AudioPlayer _clickPlayer;
  late AudioPlayer _correctPlayer;
  late AudioPlayer _incorrectPlayer;
  late AudioPlayer _winPlayer;

  WidgetRef? _ref;
  bool _isInitialized = false;

  bool _musicShouldBePlaying = true;

  Future<void> initialize(WidgetRef ref) async {
    if (_isInitialized) return;

    _ref = ref;
    _musicPlayer = AudioPlayer();
    _clickPlayer = AudioPlayer();
    _correctPlayer = AudioPlayer();
    _incorrectPlayer = AudioPlayer();
    _winPlayer = AudioPlayer();

    try {
      // set release modes
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _clickPlayer.setReleaseMode(ReleaseMode.stop);
      await _correctPlayer.setReleaseMode(ReleaseMode.stop);
      await _incorrectPlayer.setReleaseMode(ReleaseMode.stop);
      await _winPlayer.setReleaseMode(ReleaseMode.stop);

      // preload sound effects
      await _clickPlayer.setSource(AssetSource('sounds/click.mp3'));
      await _correctPlayer.setSource(AssetSource('sounds/correct.mp3'));
      await _incorrectPlayer.setSource(AssetSource('sounds/incorrect.mp3'));
      await _winPlayer.setSource(AssetSource('sounds/win.mp3'));

      _isInitialized = true;
      developer.log('Audio initialized successfully', name: 'AudioManager');
    } catch (e) {
      developer.log('Error initializing audio: $e', name: 'AudioManager');
      _isInitialized = false;
    }
  }

  bool get musicShouldBePlaying => _musicShouldBePlaying;

  bool get _isMusicEnabled {
    if (_ref == null) return false;
    return _ref!.read(settingsProvider).musicEnabled;
  }

  bool get _areSoundEffectsEnabled {
    if (_ref == null) return false;
    return _ref!.read(settingsProvider).soundEffectsEnabled;
  }

  Future<void> playBackgroundMusic({bool fade = false}) async {
    if (!_isInitialized || !_isMusicEnabled) return;

    _musicShouldBePlaying = true;

    try {
      await _musicPlayer.setSource(AssetSource('sounds/background.mp3'));

      if (fade) {
        await _musicPlayer.setVolume(0.0);
        await _musicPlayer.resume();
        _fadeVolume(_musicPlayer, 0.0, 1.0, Duration(milliseconds: 900));
      } else {
        await _musicPlayer.setVolume(1.0);
        await _musicPlayer.resume();
      }
    } catch (e) {
      developer.log('Error playing background music: $e', name: 'AudioManager');
    }
  }

  Future<void> ensureMusicPlaying() async {
    if (!_isInitialized || !_isMusicEnabled || !_musicShouldBePlaying) return;

    if (_musicPlayer.state != PlayerState.playing) {
      try {
        await playBackgroundMusic(fade: true);
      } catch (e) {
        developer.log('Could not start music on web: $e', name: 'AudioManager');
      }
    }
  }

  Future<void> pauseBackgroundMusic(
      {bool fade = false, bool userPaused = true}) async {
    if (!_isInitialized) return;

    if (userPaused) {
      _musicShouldBePlaying = false;
    }

    try {
      if (fade) {
        // fade out
        await _fadeVolume(_musicPlayer, 1.0, 0.0, Duration(milliseconds: 900));
        await _musicPlayer.pause();
        // reset for next play
        await _musicPlayer.setVolume(1.0);
      } else {
        await _musicPlayer.pause();
      }
    } catch (e) {
      developer.log('Error pausing background music: $e', name: 'AudioManager');
    }
  }

  Future<void> resumeBackgroundMusic({bool fade = false}) async {
    if (!_isInitialized || !_isMusicEnabled) {
      return;
    }

    _musicShouldBePlaying = true;

    try {
      if (fade) {
        await _musicPlayer.setVolume(0.0);
        await _musicPlayer.resume();
        _fadeVolume(_musicPlayer, 0.0, 1.0, Duration(milliseconds: 900));
      } else {
        await _musicPlayer.setVolume(1.0);
        await _musicPlayer.resume();
      }
    } catch (e) {
      developer.log('Error resuming background music: $e',
          name: 'AudioManager');
    }
  }

  Future<void> _fadeVolume(
      AudioPlayer player, double from, double to, Duration duration) async {
    const steps = 90;
    final stepDuration = duration.inMilliseconds ~/ steps;
    final volumeStep = (to - from) / steps;

    for (int i = 0; i <= steps; i++) {
      await _musicPlayer.setVolume(from + (volumeStep * i));
      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  Future<void> playClickSound() async {
    if (!_isInitialized || !_areSoundEffectsEnabled) return;

    try {
      await _clickPlayer.seek(Duration.zero);
      _clickPlayer.resume();
    } catch (e) {
      developer.log('Error playing click sound: $e', name: 'AudioManager');
    }
  }

  Future<void> playCorrectSound() async {
    if (!_isInitialized || !_areSoundEffectsEnabled) return;

    try {
      await _correctPlayer.seek(Duration.zero);
      _correctPlayer.setVolume(0.5);
      _correctPlayer.resume();
    } catch (e) {
      developer.log('Error playing correct sound: $e', name: 'AudioManager');
    }
  }

  Future<void> playIncorrectSound() async {
    if (!_isInitialized || !_areSoundEffectsEnabled) {
      return;
    }

    try {
      await _incorrectPlayer.seek(Duration.zero);
      _incorrectPlayer.resume();
    } catch (e) {
      developer.log('Error playing incorrect sound: $e', name: 'AudioManager');
    }
  }

  Future<void> playWinSound() async {
    if (!_isInitialized || !_areSoundEffectsEnabled) return;

    try {
      await _winPlayer.seek(Duration.zero);
      _winPlayer.resume();
      _fadeVolume(_winPlayer, 1.0, 0.0, Duration(milliseconds: 900));
    } catch (e) {
      developer.log('Error playing win sound: $e', name: 'AudioManager');
    }
  }

  void dispose() {
    _musicPlayer.dispose();
    _clickPlayer.dispose();
    _correctPlayer.dispose();
    _incorrectPlayer.dispose();
    _winPlayer.dispose();
  }
}
