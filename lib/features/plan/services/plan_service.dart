import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/plan_model.dart';

class PlanService {
  final _client = Supabase.instance.client;

  Future<PlanModel> fetchPlan(String userId) async {
    final res = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (res == null) {
      // User belum ada di profiles → insert free trial
      final now = DateTime.now().toUtc();
      final expires = DateTime.utc(now.year, now.month + 3, now.day,
          now.hour, now.minute, now.second);
      await _client.from('profiles').insert({
        'id': userId,
        'plan_type': 'free',
        'trial_expires_at': expires.toIso8601String(),
      });
      return PlanModel(
        userId: userId,
        planType: PlanType.free,
        trialExpiresAt: expires.toLocal(),
      );
    }

    return PlanModel.fromMap(res);
  }
}
