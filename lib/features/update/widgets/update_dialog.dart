import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../models/update_info.dart';
import '../services/update_service.dart';

/// Shows the update dialog. If [info.forceUpdate] is true, dialog cannot be dismissed.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !info.forceUpdate,
    builder: (_) => PopScope(
      canPop: !info.forceUpdate,
      child: _UpdateDialogContent(info: info),
    ),
  );
}

class _UpdateDialogContent extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialogContent({required this.info});

  @override
  State<_UpdateDialogContent> createState() => _UpdateDialogContentState();
}

class _UpdateDialogContentState extends State<_UpdateDialogContent> {
  bool _downloading = false;
  double _progress = 0;
  int _received = 0;
  int _total = 0;
  String? _error;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    final ok = await UpdateService.instance.downloadAndInstall(
      widget.info,
      onProgress: (p, r, t) {
        if (mounted) {
          setState(() {
            _progress = p;
            _received = r;
            _total = t;
          });
        }
      },
    );

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _downloading = false;
        _error = 'Gagal mendownload atau menginstall update. Pastikan izin install dari sumber tidak dikenal aktif.';
      });
    }
  }

  String _fmtMB(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header icon + title
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.forceUpdate ? 'Update Wajib' : 'Update Tersedia',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${info.currentVersion}  →  ${info.latestVersion}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // Changelog
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    info.changelog.isEmpty ? 'Tidak ada catatan rilis.' : info.changelog,
                    style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ),

            if (info.apkSize != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.download_rounded, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text('Ukuran: ${_fmtMB(info.apkSize!)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ]),
            ],

            if (info.forceUpdate) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Update ini wajib. App tidak bisa digunakan sebelum update.',
                      style: TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ],

            if (_downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(_progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  if (_total > 0)
                    Text('${_fmtMB(_received)} / ${_fmtMB(_total)}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ],

            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!info.forceUpdate && !_downloading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Nanti Saja'),
                  ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _downloading ? null : _startDownload,
                  icon: _downloading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(_downloading ? 'Mengunduh...' : 'Update Sekarang'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
