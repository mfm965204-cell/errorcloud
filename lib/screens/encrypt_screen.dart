import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models/share_link.dart';
import '../services/api_client.dart';
import '../services/crypto_service.dart';
import '../widgets/panel.dart';
import 'home_screen.dart';

/// Tab 1: pick a file, seal it on-device, upload the sealed blob, get a link.
class EncryptScreen extends StatefulWidget {
  const EncryptScreen({super.key});

  @override
  State<EncryptScreen> createState() => _EncryptScreenState();
}

class _EncryptScreenState extends State<EncryptScreen> {
  PlatformFile? _file;
  bool _busy = false;
  bool _copied = false;
  String? _status;
  String? _link;

  Future<void> _pickFile() async {
    if (_busy) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      setState(() {
        _file = result.files.first;
        _link = null;
        _copied = false;
        _status = null;
      });
    } catch (error) {
      if (!mounted) return;
      await _showError('Could not open the file picker: ${describeError(error)}');
    }
  }

  Future<Uint8List> _readBytes(PlatformFile file) async {
    final cached = file.bytes;
    if (cached != null && cached.isNotEmpty) return cached;
    final path = file.path;
    if (path == null) {
      throw const ApiException('That file could not be read from disk.');
    }
    return Uint8List.fromList(await File(path).readAsBytes());
  }

  Future<void> _sealAndUpload() async {
    final picked = _file;
    if (picked == null || _busy) return;

    setState(() {
      _busy = true;
      _link = null;
      _copied = false;
      _status = 'Reading file…';
    });

    try {
      final plain = await _readBytes(picked);
      if (!mounted) return;
      setState(() => _status = 'Sealing with AES-256-GCM…');

      final sealed = CryptoService.seal(plain);

      if (!mounted) return;
      setState(() => _status = 'Uploading sealed blob…');

      final fileId = await ApiClient.upload(sealed.bytes);
      final link = ShareLink.build(
        fileId: fileId,
        keyBase64: sealed.keyBase64,
        fileName: picked.name,
      );

      if (!mounted) return;
      setState(() {
        _link = link;
        _status = null;
      });
      await _showLinkDialog(link);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = null);
      await _showError(describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  Future<void> _showLinkDialog(String link) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Sealed and uploaded'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'This link is the only copy of the key. Anyone who has it can '
                  'decrypt the file; nobody else can, including the server.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    link,
                    style: const TextStyle(fontSize: 11, fontFamily: 'Menlo'),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                if (mounted) setState(() => _copied = true);
              },
              child: const Text('Copy link'),
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
          title: const Text('Something went wrong'),
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
    final picked = _file;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Encrypt & Upload'),
        trailing: aboutButton(context),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: <Widget>[
            Panel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    CupertinoIcons.lock_shield_fill,
                    size: 28,
                    color: CupertinoColors.activeBlue,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Zero-knowledge vault',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'AES-256-GCM. The key is generated on this device and '
                          'never leaves it — the server only ever stores ciphertext.',
                          style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.systemGrey.resolveFrom(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('File'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (picked == null)
                    const Text(
                      'No file selected.',
                      style: TextStyle(fontSize: 14),
                    )
                  else
                    Row(
                      children: <Widget>[
                        const Icon(CupertinoIcons.doc_fill, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                picked.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatBytes(picked.size),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    color: const Color(0xFF2C2C2E),
                    disabledColor: const Color(0xFF1C1C1E),
                    onPressed: _busy ? null : _pickFile,
                    child: Text(picked == null ? 'Choose a file' : 'Change file'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: (picked == null || _busy) ? null : _sealAndUpload,
              child: _busy
                  ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                  : const Text('Encrypt & Upload'),
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
            if (_link != null) ...<Widget>[
              const SizedBox(height: 28),
              const SectionLabel('Share link'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _link!,
                      style: const TextStyle(fontSize: 11, fontFamily: 'Menlo'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => _copyLink(_link!),
                          child: Text(_copied ? 'Copied' : 'Copy link'),
                        ),
                        const SizedBox(width: 20),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => setState(() => _link = null),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Size limit per file: ${formatBytes(AppConfig.maxTransferBytes)}.',
                style: const TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemGrey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
