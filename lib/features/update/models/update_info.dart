/// Information about an available update.
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String changelog;
  final String apkUrl;
  final int? apkSize;
  final bool forceUpdate;
  final DateTime publishedAt;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.changelog,
    required this.apkUrl,
    this.apkSize,
    required this.forceUpdate,
    required this.publishedAt,
  });

  bool get hasUpdate => _isNewer(latestVersion, currentVersion);

  /// Compare semver-ish strings (e.g. "1.0.10" vs "1.0.9").
  /// Strips leading "v" and any "+build" suffix.
  static bool _isNewer(String latest, String current) {
    final l = _parts(latest);
    final c = _parts(current);
    final maxLen = l.length > c.length ? l.length : c.length;
    for (var i = 0; i < maxLen; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  static List<int> _parts(String v) {
    final cleaned = v.replaceFirst(RegExp(r'^v'), '').split('+').first;
    return cleaned.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  }
}
