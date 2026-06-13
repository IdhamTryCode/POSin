enum PlanType { free, premium }

class PlanModel {
  final String userId;
  final PlanType planType;
  final DateTime trialExpiresAt;

  const PlanModel({
    required this.userId,
    required this.planType,
    required this.trialExpiresAt,
  });

  factory PlanModel.fromMap(Map<String, dynamic> map) {
    return PlanModel(
      userId: map['id'] as String,
      planType: map['plan_type'] == 'premium' ? PlanType.premium : PlanType.free,
      trialExpiresAt: DateTime.parse(map['trial_expires_at'] as String).toLocal(),
    );
  }

  bool get isPremium => planType == PlanType.premium;

  bool get isActive {
    // App gratis selamanya — paywall dinonaktifkan.
    // Untuk mengembalikan ke mode berbayar, hapus `return true;` di bawah
    // dan aktifkan kembali 2 baris pengecekan trial.
    return true;
    // if (isPremium) return true;
    // return DateTime.now().isBefore(trialExpiresAt);
  }

  int get daysLeft {
    final diff = trialExpiresAt.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }
}
