import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/update_info.dart';
import '../services/update_service.dart';

/// Auto-runs once at app start, checks GitHub for newer release.
/// Returns null if up-to-date or check failed (silent).
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  return UpdateService.instance.checkForUpdate();
});
