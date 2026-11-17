import 'dart:io';
import 'dart:typed_data';

import 'package:errorcloud/core/crypto_service.dart';
import 'package:errorcloud/core/link_codec.dart';
import 'package:errorcloud/core/ssl_pinning.dart';
import 'package:errorcloud/core/vault_api.dart';
import 'package:errorcloud/ui/common.dart';
import 'package:errorcloud/ui/settings_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class UploadRecord {
  UploadRecord({
    required this.fileId,
    required this.fileName,
    required this.plainBytes,
    required this.link,
    required this.at,
  });

  final String fileId;
  final String fileName;
  final int plainBytes;
  final String link;
  final DateTime at;
}

class EncryptScreen extends StatefulWidget {
  const EncryptScreen({super.key});

  @override
  State<EncryptScreen> createState() => _EncryptScreenState();
}

class _EncryptScreenState extends State<EncryptScreen> {
  final VaultApi _api = VaultApi();

  Uint8List? _bytes;
  String? _fileName;
  bool _busy = false;
  String _step = '';
  final List<UploadRecord> _history = <UploadRecord>[];

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
        withReadStream: false,
      );
      if (result == null || result.files.isEmpty) return;
      final PlatformFile picked = result.files.first;

      Uint8List? bytes;
      if (picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      } else if (picked.bytes != null) {
        bytes = picked.bytes;
      }
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        await showInfoDialog(context, title: 'Empty file', message: 'That file has no contents.');
        return;
      }
      setState(() {
        _bytes = bytes;
        _fileName = picked.name;
      });
    } catch (error) {
      if (!mounted) return;
      await showInfoDialog(
        context,
        title: 'Could not read the file',
        message: '$error',
      );
    }
  }

  Future<void> _encryptAndUpload() async {
    final Uint8List? bytes = _bytes;
    final String? name = _fileName;
    if (bytes == null || name == null) return;

    setState(() {
      _busy = true;
      _step = 'Encrypting on device…';
    });

    try {
      // Give the progress line a frame to paint before the CPU-bound work.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final SealedFile sealed = CryptoService.seal(bytes);

      if (mounted) setState(() => _step = 'Uploading ciphertext…');
      final String fileId = await _api.upload(sealed.blob);

      final String link = VaultLink(
        fileId: fileId,
        key: sealed.key,
        fileName: name,
      ).encode();

      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = '';
        _history.insert(
          0,
          UploadRecord(
            fileId: fileId,
            fileName: name,
            plainBytes: bytes.length,
            link: link,
            at: DateTime.now(),
          ),
        );
      });
      await _showLinkDialog(link, fileId, name);
    } on PinningException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = '';
      });
      await showInfoDialog(
        context,
        title: 'Connection blocked',
        message: '${error.message}\n\nNothing was uploaded.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = '';
      });
      await showInfoDialog(
        context,
        title: 'Upload failed',
        message: '$error',
      );
    }
  }

  Future<void> _showLinkDialog(String link, String fileId, String name) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => CupertinoAlertDialog(
        title: const Text('Encrypted and stored'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'File ID $fileId — the server only holds ciphertext.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  link,
                  style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Anyone with this link can decrypt the file. Share it like a password.',
                style: TextStyle(fontSize: 12, color: kMuted),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            child: const Text('Done'),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (!mounted) return;
              await showInfoDialog(
                context,
                title: 'Copied',
                message: 'The vault link for $name is on your clipboard.',
              );
            },
            child: const Text('Copy to clipboard'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = _bytes;

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
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Encrypt & Upload',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                ),
                StatusPill(
                  label: 'AES-256-GCM',
                  color: CupertinoColors.systemGreen.resolveFrom(context),
                  icon: CupertinoIcons.lock_fill,
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Files are encrypted on this device. The key never leaves your phone — the server stores an unreadable blob.',
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
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: kSurfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          bytes == null
                              ? CupertinoIcons.doc
                              : CupertinoIcons.doc_fill,
                          color: kAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _fileName ?? 'No file selected',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              bytes == null
                                  ? 'Pick something to seal'
                                  : formatBytes(bytes.length),
                              style: const TextStyle(fontSize: 12, color: kMuted),
                            ),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: kSurfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        onPressed: _busy ? null : _pickFile,
                        child: const Text('Choose', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      color: bytes == null ? kSurfaceAlt : kAccent,
                      disabledColor: kSurfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      onPressed: (bytes == null || _busy) ? null : _encryptAndUpload,
                      child: Text(
                        _busy ? _step : 'Encrypt & Upload',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: bytes == null
                              ? kMuted
                              : CupertinoColors.white,
                        ),
                      ),
                    ),
                  ),
                  if (_busy) ...<Widget>[
                    const SizedBox(height: 14),
                    const CupertinoActivityIndicator(radius: 11),
                  ],
                ],
              ),
            ),
            if (_history.isNotEmpty) ...<Widget>[
              const SizedBox(height: 26),
              const Text(
                'THIS SESSION',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                  color: kMuted,
                ),
              ),
              const SizedBox(height: 10),
              ..._history.map(
                (UploadRecord record) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(CupertinoIcons.checkmark_seal_fill,
                              size: 16, color: CupertinoColors.systemGreen),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              record.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            record.fileId,
                            style: const TextStyle(
                              fontFamily: 'Menlo',
                              fontSize: 12,
                              color: kAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Text(
                            formatBytes(record.plainBytes),
                            style: const TextStyle(fontSize: 12, color: kMuted),
                          ),
                          const Spacer(),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minSize: 0,
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: record.link),
                              );
                              if (!mounted) return;
                              await showInfoDialog(
                                context,
                                title: 'Copied',
                                message: 'Vault link copied.',
                              );
                            },
                            child: const Text(
                              'Copy link',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
