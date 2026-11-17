import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/share_link.dart';
import '../services/api_client.dart';
import '../services/crypto_service.dart';
import '../services/file_service.dart';
import '../widgets/panel.dart';
import 'home_screen.dart';

/// Tab 2: paste a share link, fetch the sealed blob, decrypt on-device, save.
class DecryptScreen extends StatefulWidget {
  const DecryptScreen({super.key});

  @override
  State<DecryptScreen> createState() => _DecryptScreenState();
}

class _DecryptScreenState extends State<DecryptScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _status;
  String? _savedPath;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    setState(() => _controller.text = text);
  }

  Future<void> _downloadAndDecrypt() async {
    if (_busy) return;

    final link = ShareLink.parse(_controller.text);
    if (link == null) {
      await _showError(
        'That does not look like an Errorcloud link. Expected '
        'errorcloud://FILEID?key=KEY',
      );
      return;
    }

    setState(() {
      _busy = true;
      _savedPath = null;
      _status = 'Downloading sealed blob…';
    });

    try {
      final blob = await ApiClient.download(link.fileId);
      if (!mounted) return;
      setState(() => _status = 'Decrypting on this device…');

      final plain = CryptoService.open(blob, link.keyBase64);

      final name = (link.fileName ?? '').isNotEmpty
          ? link.fileName!
          : 'errorcloud_${link.fileId}';

      if (!mounted) return;
      setState(() => _status = 'Saving…');

      final savedPath = await FileService.save(plain, name);

      if (!mounted) return;
      setState(() {
        _status = null;
        _savedPath = savedPath;
      });

      if (savedPath != null) {
        await _showSuccess(savedPath);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = null);
      await _showError(describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSuccess(String path) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Decrypted'),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Saved to:\n$path',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showError(String message) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Could not decrypt'),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(message, style: const TextStyle(fontSize: 13)),
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Download & Decrypt'),
        trailing: aboutButton(context),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: <Widget>[
            const SectionLabel('Share link'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CupertinoTextField(
                    controller: _controller,
                    placeholder: 'errorcloud://X7F9A2?key=…',
                    minLines: 3,
                    maxLines: 5,
                    style: const TextStyle(fontSize: 12, fontFamily: 'Menlo'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121214),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x1AFFFFFF)),
                    ),
                    keyboardType: TextInputType.multiline,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _busy ? null : _paste,
                        child: const Text('Paste'),
                      ),
                      const SizedBox(width: 20),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _controller.clear();
                                  _savedPath = null;
                                }),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: _busy ? null : _downloadAndDecrypt,
              child: _busy
                  ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                  : const Text('Download & Decrypt'),
            ),
            if (_status != null) ...<Widget>[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const CupertinoActivityIndicator(radius: 8),
                  const SizedBox(width: 10),
                  Text(
                    _status!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ),
            ],
            if (_savedPath != null) ...<Widget>[
              const SizedBox(height: 24),
              Panel(
                child: Row(
                  children: <Widget>[
                    const Icon(
                      CupertinoIcons.checkmark_seal_fill,
                      color: Color(0xFF30D158),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Saved to $_savedPath',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              'Decryption happens on this device. Nothing is sent to the server '
              'except the file id in the link.',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.systemGrey.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
