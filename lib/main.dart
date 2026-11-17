import 'package:flutter/cupertino.dart';

import 'screens/home_screen.dart';
import 'config.dart';

void main() {
  runApp(const ErrorcloudApp());
}

class ErrorcloudApp extends StatelessWidget {
  const ErrorcloudApp({super.key});

  static const Color _background = Color(0xFF000000);
  static const Color _bar = Color(0xF20A0A0C);

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: CupertinoColors.activeBlue,
        scaffoldBackgroundColor: _background,
        barBackgroundColor: _bar,
        textTheme: CupertinoTextThemeData(
          navLargeTitleTextStyle: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
