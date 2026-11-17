import 'dart:async';

import 'package:errorcloud/core/config.dart';
import 'package:errorcloud/ui/common.dart';
import 'package:errorcloud/ui/root_tabs.dart';
import 'package:flutter/cupertino.dart';

class ErrorcloudApp extends StatelessWidget {
  const ErrorcloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: kAccent,
        scaffoldBackgroundColor: kBackground,
        barBackgroundColor: Color(0xF20B0F14),
        textTheme: CupertinoTextThemeData(
          navLargeTitleTextStyle: TextStyle(
            color: CupertinoColors.white,
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute<void>(builder: (_) => const RootTabs()),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF101822), kBackground],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF3E9BFF), Color(0xFF1F6FE0)],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: kAccent.withValues(alpha: 0.35),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.cloud_fill,
                  size: 54,
                  color: CupertinoColors.white,
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                AppConfig.appName,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: CupertinoColors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Zero-knowledge encrypted cloud',
                style: TextStyle(fontSize: 14, color: kMuted),
              ),
              const SizedBox(height: 44),
              const Text(
                AppConfig.signature,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kAccent,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
