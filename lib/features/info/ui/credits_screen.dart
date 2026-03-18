import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/game_config/constants.dart';

class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  Future<void> _launchURL(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!context.mounted) return;
        _showErrorSnackBar(context, 'Link konnte nicht geöffnet werden.');
      }
    } catch (e) {
      if (!context.mounted) return;
      _showErrorSnackBar(context, 'Linkfehler.');
    }
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: EdgeInsets.only(
          bottom: kToolbarHeight,
          left: 40,
          right: 40,
        ),
        content: Container(
            padding: EdgeInsets.all(12),
            height: kToolbarHeight,
            decoration: BoxDecoration(
              color: colorBlack,
              borderRadius: BorderRadius.all(Radius.circular(9)),
            ),
            child: Center(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorWhite,
                    ),
              ),
            )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorGrey300,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Stack(
          children: [
            // title
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 32.0).copyWith(top: 24),
              child: Column(
                children: [
                  // title
                  SizedBox(
                    height: kToolbarHeight * 2,
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        'Danksagungen & Quelle',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colorBlack,
                            ),
                      ),
                    ),
                  ),
                  Text(
                    'Tic Tac Zwö wurde durch die Arbeit und die Beiträge von großartigen Entwicklern und Kreativen ermöglicht.\n'
                    '\nEin großes Dankeschön an alle!   🖤♥️💛',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: 48),

                  // technologies
                  _buildHeading(context, 'Technologie'),
                  const SizedBox(height: 8),

                  _buildCreditText(context,
                      'Entwickelt mit Flutter, dem UI-Toolkit von Google.'),
                  _buildCreditText(context,
                      'Backend-Dienste bereitgestellt durch Supabase.'),
                  _buildCreditText(
                      context, 'State-Management mit dem Riverpod-Framework.'),
                  _buildCreditText(
                      context, 'Lokale Speicherung mit Hive-Community Edition'),
                  _buildCreditText(context,
                      'In-App Feedback und Bug-Reporting durch Wiredash.'),
                  const SizedBox(height: 40),

                  // words
                  _buildHeading(context, 'Wortschatz'),
                  const SizedBox(height: 8),

                  _buildCreditLink(
                    context,
                    'Die Lister der deutschen Nomen basiert auf den ',
                    'Frequency Lists von Neri',
                    'https://frequencylists.blogspot.com/2016/01/the-2980-most-frequently-used-german.html',
                  ),
                  const SizedBox(height: 40),

                  // icons
                  _buildHeading(context, 'Icons'),
                  const SizedBox(height: 8),

                  _buildCreditLink(
                      context,
                      'Meeting von ',
                      'Nubaia Karim Barsha - Noun Project',
                      'https://thenounproject.com/icon/meeting-2465898/'),
                  _buildCreditLink(
                      context,
                      'Profile von ',
                      'Sentya Irma - Noun Project',
                      'https://thenounproject.com/icon/profile-6282718/'),
                  _buildCreditLink(context, 'Grid von ', 'Ariso - Noun Project',
                      'https://thenounproject.com/icon/grid-7573885/'),
                  _buildCreditLink(
                      context,
                      'WiFi von ',
                      'Manglayang Studio - Noun Project',
                      'https://thenounproject.com/icon/wifi-4262430/'),
                  _buildCreditLink(
                      context,
                      'Boxing von ',
                      'Basith Ibrahim - Noun Project',
                      'https://thenounproject.com/icon/boxing-3681295/'),
                  _buildCreditLink(
                      context,
                      'Edit von ',
                      'Kosong Tujuh - Noun Project',
                      'https://thenounproject.com/icon/edit-7511823/'),
                  _buildCreditLink(
                      context,
                      'Favorites von ',
                      'Dmitry Podluzny - Noun Project',
                      'https://thenounproject.com/icon/favorites-7219360/'),
                  _buildCreditLink(
                    context,
                    'Game Coin von ',
                    'HRF07 - Noun Project',
                    'https://thenounproject.com/icon/game-coin-7576266/',
                  ),
                  const SizedBox(height: 40),

                  // music
                  _buildHeading(context, 'Sound'),
                  const SizedBox(height: 8),

                  _buildCreditLink(
                    context,
                    'Padsound von ',
                    'Samuel F. Johanns - Pixabay',
                    'https://pixabay.com/sound-effects/padsound-meditation-21384/',
                  ),
                  _buildCreditLink(
                    context,
                    'Water Drip von ',
                    'Spanrucker - Pixabay',
                    'https://pixabay.com/sound-effects/water-drip-45622/',
                  ),
                  _buildCreditLink(
                    context,
                    'Marimba Bloop von ',
                    'Floraphonic - Pixabay',
                    'https://pixabay.com/sound-effects/marimba-bloop-2-188149/',
                  ),
                  _buildCreditLink(
                    context,
                    'Bubblepop von ',
                    'Linhmitto - Pixabay',
                    'https://pixabay.com/sound-effects/bubblepop-254773/',
                  ),
                  _buildCreditLink(
                    context,
                    'Applause von ',
                    'Nick Rave - Pixabay',
                    'https://pixabay.com/sound-effects/moreclaps-104533/',
                  ),
                  const SizedBox(height: 40),

                  // special thanks
                  _buildHeading(context, 'Morio Anzenzen'),
                  const SizedBox(height: 8),

                  Text(
                    'All my love and gratitude, and then some, for the unshaken faith, nonstop hype and always holding it down heavy. 🫶🏾\n\nThis one\'s for you:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: 16),

                  _buildCreditText(context, 'Munmun'),
                  _buildCreditText(context, 'Munesh'),
                  _buildCreditText(context, 'Bo'),
                  _buildCreditText(context, 'Mwaki'),
                  _buildCreditText(context, 'Mwangizzle'),
                  _buildCreditText(context, 'Betty'),
                  _buildCreditText(context, 'Munj'),
                  const SizedBox(height: 80),
                ],
              ),
            )
                .animate(delay: 500.ms)
                .slideY(
                  begin: 0.3,
                  duration: 1500.ms,
                  curve: Curves.easeOut,
                )
                .fadeIn(
                  duration: 1500.ms,
                  curve: Curves.easeOut,
                ),

            // back button
            Positioned(
              bottom: 16,
              right: 16,
              child: SizedBox(
                height: 52,
                width: 52,
                child: FloatingActionButton(
                  onPressed: () => Navigator.pop(context),
                  backgroundColor: colorBlack.withOpacity(0.75),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: colorWhite,
                    size: 26,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeading(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: Colors.black87,
            ),
      ),
    );
  }

  Widget _buildCreditLink(
      BuildContext context, String prefix, String linkText, String url) {
    final textStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorGrey600);
    final linkStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.blue,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '•   ',
            style: TextStyle(
              color: colorGrey600,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: RichText(
              textAlign: TextAlign.start,
              text: TextSpan(
                children: [
                  TextSpan(text: prefix, style: textStyle),
                  TextSpan(
                      text: linkText,
                      style: linkStyle,
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _launchURL(context, url)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCreditText(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '•   ',
            style: TextStyle(
              color: colorGrey600,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.start,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 17,
                    color: colorGrey600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
