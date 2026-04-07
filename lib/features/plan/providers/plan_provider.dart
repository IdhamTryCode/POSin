import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/plan_model.dart';
import '../services/plan_service.dart';

final planServiceProvider = Provider<PlanService>((ref) => PlanService());

final planProvider = FutureProvider.family<PlanModel, String>((ref, userId) async {
  return ref.read(planServiceProvider).fetchPlan(userId);
});
