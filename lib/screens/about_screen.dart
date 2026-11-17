import 'package:flutter/cupertino.dart';

import '../config.dart';
import '../widgets/panel.dart';

/// Settings / About, including the developer credit.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const List<String> _securityNotes = <String>[
    'Files are encrypted with AES-256-GCM before they leave the device.',
    'The 256-bit key is generated with a secure RNG and lives only in the share link.',
    'The server stores an opaque blob: it never sees the key or the file name.',
    'Cleartext HTTP is disabled in the app manifest and the API host is locked.',
    'The link is the key. Lose it and the file cannot be recovered by anyone.',
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Settings'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: <Widget>[
            Column(
              children: <Widget>[
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x1AFFFFFF)),
                  ),
                  child: const Icon(
                    CupertinoIcons.lock_shield_fill,
                    size: 36,
                    color: CupertinoColors.activeBlue,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  AppConfig.appName,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'v${AppConfig.appVersion}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  AppConfig.developerLine,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const SectionLabel('Security'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final note in _securityNotes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              CupertinoIcons.checkmark_circle_fill,
                              size: 15,
                              color: CupertinoColors.activeBlue,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              note,
                              style: const TextStyle(fontSize: 13, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Server'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    Uri.parse(AppConfig.apiBaseUrl).host,
                    style: const TextStyle(fontSize: 13, fontFamily: 'Menlo'),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Cloudflare Worker with R2 blind storage.',
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Center(
              child: Text(
                AppConfig.developerLine,
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemGrey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
