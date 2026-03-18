import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tic_tac_zwo/features/settings/logic/settings_notifier.dart';
import 'package:vibration/vibration.dart';

class HapticsManager {
  static bool? _hasVibrator;
  static WidgetRef? _ref;

  static void initialize(WidgetRef ref) {
    if (kIsWeb) return;

    _ref = ref;
    _checkVibrator();
  }

  static Future<void> _checkVibrator() async {
    _hasVibrator = await Vibration.hasVibrator();
  }

  static bool get _isEnabled {
    if (_ref == null) return false;
    return _ref!.read(settingsProvider).hapticsEnabled;
  }

  static Future<void> light() async {
    if (kIsWeb || !_isEnabled) return;
    if (_hasVibrator == null) await _checkVibrator();
    if (_hasVibrator == true) {
      await Vibration.vibrate(duration: 15, amplitude: 128);
    }
  }

  static Future<void> medium() async {
    if (kIsWeb || !_isEnabled) return;
    if (_hasVibrator == null) await _checkVibrator();
    if (_hasVibrator == true) {
      await Vibration.vibrate(duration: 30, amplitude: 128);
    }
  }
}
