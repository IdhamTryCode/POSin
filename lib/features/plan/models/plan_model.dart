enum PlanType { free, premium }

class PlanModel {
  final String userId;
  final PlanType planType;

  /// Batas masa aktif — berlaku untuk trial MAUPUN premium.
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
}

enum PlanLockReason {
  /// Masa aktif (trial / premium) sudah lewat.
  expired,

  /// Sudah terlalu lama tidak bisa memverifikasi langganan ke server.
  needsVerification,
}

/// Status langganan yang dipakai UI. Dihitung dengan [effectiveNow] — perkiraan
/// jam SERVER, bukan jam HP mentah — supaya tidak bisa diakali dengan
/// memundurkan tanggal HP.
class PlanStatus {
  final PlanModel plan;
  final DateTime effectiveNow;

  /// true kalau status ini dari cache (belum terverifikasi ke server barusan).
  final bool fromCache;
  final PlanLockReason? lockReason;

  const PlanStatus({
    required this.plan,
    required this.effectiveNow,
    required this.fromCache,
    this.lockReason,
  });

  bool get isActive => lockReason == null;
  bool get isPremium => plan.isPremium;
  DateTime get trialExpiresAt => plan.trialExpiresAt;

  int get daysLeft {
    final diff = plan.trialExpiresAt.difference(effectiveNow);
    if (diff.isNegative) return 0;
    return (diff.inHours / 24).ceil();
  }

  /// Tampilkan pengingat perpanjangan di kasir.
  bool get expiresSoon => isActive && daysLeft <= 3;
}

/// Berapa lama app boleh dipakai tanpa pernah tersambung ke server.
const offlineGrace = Duration(days: 14);

/// Hitung status dari data plan + waktu.
///
/// * [serverNow] / [deviceNowAtFetch]: jam server & jam HP saat terakhir
///   berhasil cek ke server → dipakai untuk mengoreksi jam HP.
/// * Jam efektif tidak pernah mundur melewati jam server terakhir yang diketahui,
///   jadi memundurkan tanggal HP tidak membuka kunci.
PlanStatus evaluatePlan({
  required PlanModel plan,
  required DateTime serverNow,
  required DateTime deviceNowAtFetch,
  required DateTime deviceNow,
  required bool fromCache,
}) {
  final offset = serverNow.difference(deviceNowAtFetch);
  var effectiveNow = deviceNow.add(offset);
  if (effectiveNow.isBefore(serverNow)) effectiveNow = serverNow;

  PlanLockReason? reason;
  if (!effectiveNow.isBefore(plan.trialExpiresAt)) {
    reason = PlanLockReason.expired;
  } else if (fromCache && effectiveNow.difference(serverNow) > offlineGrace) {
    reason = PlanLockReason.needsVerification;
  }

  return PlanStatus(
    plan: plan,
    effectiveNow: effectiveNow,
    fromCache: fromCache,
    lockReason: reason,
  );
}
