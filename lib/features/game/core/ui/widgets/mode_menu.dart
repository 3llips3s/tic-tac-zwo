import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tic_tac_zwo/features/auth/logic/auth_providers.dart';

import '../../../../../config/game_config/config.dart';
import '../../../../../config/game_config/constants.dart';
import '../../../../navigation/routes/route_names.dart';
import '../../../../settings/logic/audio_manager.dart';
import 'neu_button.dart';

class ModeMenu extends ConsumerStatefulWidget {
  const ModeMenu({super.key});

  @override
  ConsumerState<ModeMenu> createState() => _ModeMenuState();
}

class _ModeMenuState extends ConsumerState<ModeMenu> {
  bool _isMenuVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startMenuAnimation();
    });
  }

  void _startMenuAnimation() async {
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() {
      _isMenuVisible = true;
    });
  }

  // navigate to turn selection
  int? _pressedNeuButtonIndex;

  Future<void> _handleMenuButtonTap(int index) async {
    if (kIsWeb) {
      AudioManager.instance.ensureMusicPlaying();
    }

    if (_pressedNeuButtonIndex == index) return;

    setState(() => _pressedNeuButtonIndex = index);
    if (!mounted) return;

    try {
      final GameMode selectedGameMode = gameModeIcons[index]['gameMode'];
      await _navigateToSelectedGameMode(selectedGameMode);
    } finally {
      // single point for resetting button state
      if (mounted) {
        setState(() => _pressedNeuButtonIndex = null);
      }
    }
  }

  Future<void> _navigateToSelectedGameMode(GameMode gameMode) async {
    if (!mounted) return;

    switch (gameMode) {
      case GameMode.wordle:
        await Navigator.pushNamed(context, RouteNames.wordle);
        break;

      case GameMode.online:
        final connectivityResult = await Connectivity().checkConnectivity();
        if (!mounted) return;

        final isConnected =
            !connectivityResult.contains(ConnectivityResult.none);
        if (!isConnected) {
          _showSnackBar('Keine Internetverbindung!');
          return;
        }

        // determine route based on auth
        final authService = ref.read(authServiceProvider);
        final route = authService.isAuthenticated
            ? RouteNames.matchmaking
            : RouteNames.login;

        await Navigator.pushNamed(context, route);
        break;

      default:
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;

        await Navigator.pushNamed(context, RouteNames.turnSelection,
            arguments: {'gameMode': gameMode});
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: EdgeInsets.only(
          left: 40,
          right: 40,
        ),
        content: Container(
          padding: EdgeInsets.all(12),
          height: kToolbarHeight,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.all(Radius.circular(9)),
          ),
          child: Center(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorWhite,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      width: 250,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: gameModeIcons.length,
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 45,
          crossAxisSpacing: 45,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) {
          return AnimatedOpacity(
            opacity: _isMenuVisible ? 1 : 0,
            duration: Duration(milliseconds: 900),
            curve: Curves.easeIn,
            child: NeuButton(
              iconPath: gameModeIcons[index]['imagePath'],
              gameMode: gameModeIcons[index]['gameMode'],
              isNeuButtonPressed: _pressedNeuButtonIndex == index,
              onTap: () => _handleMenuButtonTap(index),
            ),
          );
        },
      ),
    );
  }
}

// list of game modes
final gameModeIcons = <Map<String, dynamic>>[
  {
    'imagePath': 'assets/images/pass.svg',
    'gameMode': GameMode.pass,
  },
  {
    'imagePath': 'assets/images/offline.svg',
    'gameMode': GameMode.offline,
  },
  {
    'imagePath': 'assets/images/grid.svg',
    'gameMode': GameMode.wordle,
  },
  {
    'imagePath': 'assets/images/online.svg',
    'gameMode': GameMode.online,
  }
];
