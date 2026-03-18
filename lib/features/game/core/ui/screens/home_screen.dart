import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../settings/logic/audio_manager.dart';
import '../../../../settings/logic/haptics_manager.dart';
import '../widgets/app_title.dart';
import '../widgets/mode_menu.dart';

class HomeScreen extends StatefulWidget {
  final bool isDrawerOpen;
  final VoidCallback onToggleDrawer;

  const HomeScreen({
    super.key,
    this.isDrawerOpen = false,
    this.onToggleDrawer = _defaultToggle,
  });

  static void _defaultToggle() {}

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _webMusicUnlocked = false;

  void _unlockMusicOnWeb() {
    if (kIsWeb && !_webMusicUnlocked) {
      _webMusicUnlocked = true;
      AudioManager.instance.ensureMusicPlaying();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/background.webp'), context);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            // app title
            AppTitle(),

            Spacer(),

            // mode menu
            Padding(
              padding: const EdgeInsets.only(bottom: kToolbarHeight * 1.5),
              child: ModeMenu(),
            ),
          ],
        ),

        // menu icon
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 16),
            child: IconButton(
              onPressed: () {
                _unlockMusicOnWeb();
                HapticsManager.light();
                widget.onToggleDrawer();
              },
              icon: widget.isDrawerOpen
                  ? SvgPicture.asset(
                      'assets/images/close_menu.svg',
                      colorFilter: const ColorFilter.mode(
                          Colors.black87, BlendMode.srcIn),
                      height: 40,
                      width: 40,
                    )
                  : SvgPicture.asset(
                      'assets/images/open_menu.svg',
                      colorFilter: const ColorFilter.mode(
                        Colors.black54,
                        BlendMode.srcIn,
                      ),
                      height: 40,
                      width: 40,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
