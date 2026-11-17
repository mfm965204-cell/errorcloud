import 'dart:io';

import 'package:errorcloud/core/config.dart';
import 'package:errorcloud/core/ssl_pinning.dart';
import 'package:errorcloud/ui/common.dart';
import 'package:flutter/cupertino.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checking = false;
  String? _result;
  bool _resultOk = false;

  Future<void> _verifyConnection() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final HttpClient client = SslPinning.newClient();
    try {
      await SslPinning.assertEndpointPinned(client, AppConfig.healthUri);
      setState(() {
        _resultOk = true;
        _result = 'Pinned certificate verified for ${Uri.parse(AppConfig.workerBaseUrl).host}.';
      });
    } catch (error) {
      setState(() {
        _resultOk = false;
        _result = '$error';
      });
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String host = Uri.parse(AppConfig.workerBaseUrl).host;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Settings'),
        backgroundColor: kSurface,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: <Widget>[
            const SizedBox(height: 24),
            Center(
              child: Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF3E9BFF), Color(0xFF1F6FE0)],
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.cloud_fill,
                  size: 40,
                  color: CupertinoColors.white,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Center(
              child: Text(
                AppConfig.appName,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'v${AppConfig.version} (${AppConfig.build})',
                style: const TextStyle(fontSize: 13, color: kMuted),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kAccent.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  AppConfig.signature,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: kAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            CupertinoListSection.insetGrouped(
              header: const Text('SECURITY'),
              backgroundColor: kBackground,
              children: <Widget>[
                CupertinoListTile(
                  title: const Text('Encryption'),
                  trailing: const Text(
                    'AES-256-GCM',
                    style: TextStyle(color: kMuted, fontSize: 13),
                  ),
                ),
                CupertinoListTile(
                  title: const Text('Key handling'),
                  trailing: const Text(
                    'Device only',
                    style: TextStyle(color: kMuted, fontSize: 13),
                  ),
                ),
                CupertinoListTile(
                  title: const Text('SSL pinning'),
                  trailing: Text(
                    SslPinning.isConfigured
                        ? '${SslPinning.pins.length} pin(s)'
                        : 'not configured',
                    style: TextStyle(
                      color: SslPinning.isConfigured
                          ? CupertinoColors.systemGreen
                          : CupertinoColors.systemRed,
                      fontSize: 13,
                    ),
                  ),
                ),
                CupertinoListTile(
                  title: const Text('Link scheme'),
                  trailing: Text(
                    '${AppConfig.linkScheme}://',
                    style: const TextStyle(color: kMuted, fontSize: 13),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('BACKEND'),
              backgroundColor: kBackground,
              children: <Widget>[
                CupertinoListTile(
                  title: const Text('Storage host'),
                  subtitle: Text(
                    host,
                    style: const TextStyle(fontSize: 11, fontFamily: 'Menlo'),
                  ),
                  trailing: const Icon(
                    CupertinoIcons.cloud,
                    color: kMuted,
                    size: 18,
                  ),
                ),
                CupertinoListTile(
                  title: const Text('Verify pinned connection'),
                  onTap: _checking ? null : _verifyConnection,
                  trailing: _checking
                      ? const CupertinoActivityIndicator(radius: 8)
                      : const Icon(
                          CupertinoIcons.arrow_right,
                          color: kMuted,
                          size: 16,
                        ),
                ),
              ],
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (_resultOk
                              ? CupertinoColors.systemGreen
                              : CupertinoColors.systemRed)
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _result!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: _resultOk
                          ? CupertinoColors.systemGreen
                          : CupertinoColors.systemRed,
                    ),
                  ),
                ),
              ),
            CupertinoListSection.insetGrouped(
              header: const Text('PINNED FINGERPRINTS'),
              backgroundColor: kBackground,
              children: <Widget>[
                if (!SslPinning.isConfigured)
                  const CupertinoListTile(
                    title: Text(
                      'No pins in this build',
                      style: TextStyle(fontSize: 13, color: kMuted),
                    ),
                  )
                else
                  ...SslPinning.pins.map(
                    (String pin) => CupertinoListTile(
                      title: Text(
                        pin.length > 24 ? '${pin.substring(0, 24)}…' : pin,
                        style: const TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 11,
                          color: kMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Text(
                'Files are encrypted on this device before upload. The backend '
                'stores ciphertext only and never receives your key.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: kMuted, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
