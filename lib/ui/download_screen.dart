import 'dart:io';

import 'package:errorcloud/core/crypto_service.dart';
import 'package:errorcloud/core/link_codec.dart';
import 'package:errorcloud/core/ssl_pinning.dart';
import 'package:errorcloud/core/vault_api.dart';
import 'package:errorcloud/ui/common.dart';
import 'package:errorcloud/ui/settings_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final VaultApi _api = VaultApi();
  final TextEditingController _controller = TextEditingController();

  bool _busy = false;
  String _step = '';
  String? _savedPath;

  @override
  void dispose() {
    _api.close();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() => _controller.text = data.text!.trim());
    }
  }

  Future<Directory> _outputDirectory() async {
    Directory? base = await getDownloadsDirectory();
    base ??= await getApplicationDocumentsDirectory();
    final Directory target = Directory('${base.path}/Errorcloud');
    if (!target.existsSync()) target.createSync(recursive: true);
    return target;
  }

  Future<void> _downloadAndDecrypt() async {
    final VaultLink link;
    try {
      link = VaultLink.parse(_controller.text);
    } on FormatException catch (error) {
      await showInfoDialog(context, title: 'Check the link', message: error.message);
      return;
    }

    setState(() {
      _busy = true;
      _step = 'Fetching ciphertext…';
      _savedPath = null;
    });

    try {
      final Uint8List blob = await _api.download(link.fileId);

      if (mounted) setState(() => _step = 'Decrypting on device…');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final Uint8List plain = CryptoService.open(blob, link.key);

      if (mounted) setState(() => _step = 'Saving…');
      final Directory dir = await _outputDirectory();
      final String safeName = (link.fileName == null || link.fileName!.isEmpty)
          ? 'errorcloud-${link.fileId}'
          : link.fileName!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      File file = File('${dir.path}/$safeName');
      if (file.existsSync()) {
        final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
        file = File('${dir.path}/${stamp}_$safeName');
      }
      await file.writeAsBytes(plain, flush: true);

      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = '';
        _savedPath = file.path;
      });

      await showCupertinoDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => CupertinoAlertDialog(
          title: const Text('Decrypted'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${formatBytes(plain.length)} written to your device.'),
                const SizedBox(height: 8),
                Text(
                  file.path,
                  style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on PinningException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = '';
      });
      await showInfoDialog(
        context,
        title: 'Connection blocked',
        message: '${error.message}\n\nNothing was downloaded.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = '';
      });
      await showInfoDialog(
        context,
        title: 'Could not open that file',
        message: '$error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: kSurface,
        middle: const Text('Errorcloud'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
          child: const Icon(CupertinoIcons.gear_alt, color: kMuted),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: <Widget>[
            const Text(
              'Download & Decrypt',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Paste the vault link you were given. The key inside it is used locally to unwrap the file.',
              style: TextStyle(fontSize: 13, color: kMuted, height: 1.4),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF202A35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'VAULT LINK',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                      color: kMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CupertinoTextField(
                    controller: _controller,
                    enabled: !_busy,
                    maxLines: 3,
                    minLines: 2,
                    placeholder: 'vault://XXXXXX?key=…',
                    padding: const EdgeInsets.all(12),
                    style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
                    decoration: BoxDecoration(
                      color: kSurfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    suffix: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        onPressed: _busy ? null : _paste,
                        child: const Text('Paste', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      color: kAccent,
                      disabledColor: kSurfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      onPressed: _busy ? null : _downloadAndDecrypt,
                      child: Text(
                        _busy ? _step : 'Download & Decrypt',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.white,
                        ),
                      ),
                    ),
                  ),
                  if (_busy) ...<Widget>[
                    const SizedBox(height: 14),
                    const Center(child: CupertinoActivityIndicator(radius: 11)),
                  ],
                ],
              ),
            ),
            if (_savedPath != null) ...<Widget>[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: CupertinoColors.systemGreen.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(CupertinoIcons.checkmark_circle_fill,
                        color: CupertinoColors.systemGreen, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _savedPath!,
                        style: const TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 11,
                          color: kMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
