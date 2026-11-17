import 'package:flutter/cupertino.dart';

import 'about_screen.dart';
import 'decrypt_screen.dart';
import 'encrypt_screen.dart';

/// Root screen: a two-tab iOS-style scaffold.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: const Color(0xF20A0A0C),
        activeColor: CupertinoColors.activeBlue,
        inactiveColor: CupertinoColors.systemGrey,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.lock_fill),
            label: 'Encrypt',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.tray_arrow_down_fill),
            label: 'Decrypt',
          ),
        ],
      ),
      tabBuilder: (BuildContext context, int index) {
        return CupertinoTabView(
          builder: (BuildContext context) =>
              index == 0 ? const EncryptScreen() : const DecryptScreen(),
        );
      },
    );
  }
}

/// Shared nav bar trailing button that opens Settings / About.
Widget aboutButton(BuildContext context) {
  return CupertinoButton(
    padding: EdgeInsets.zero,
    onPressed: () {
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute<void>(builder: (_) => const AboutScreen()),
      );
    },
    child: const Icon(CupertinoIcons.gear_alt_fill, size: 22),
  );
}
