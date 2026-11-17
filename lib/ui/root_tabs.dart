import 'package:errorcloud/ui/common.dart';
import 'package:errorcloud/ui/download_screen.dart';
import 'package:errorcloud/ui/encrypt_screen.dart';
import 'package:flutter/cupertino.dart';

class RootTabs extends StatelessWidget {
  const RootTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: kSurface,
        activeColor: kAccent,
        inactiveColor: kMuted,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.lock_shield),
            activeIcon: Icon(CupertinoIcons.lock_shield_fill),
            label: 'Encrypt & Upload',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.arrow_down_doc),
            activeIcon: Icon(CupertinoIcons.arrow_down_doc_fill),
            label: 'Download & Decrypt',
          ),
        ],
      ),
      tabBuilder: (BuildContext context, int index) {
        return index == 0 ? const EncryptScreen() : const DownloadScreen();
      },
    );
  }
}
