// Satu-satunya sumber harga langganan di admin-panel.
// HARUS sama dengan PlanConfig.monthlyPrice di lib/features/plan/plan_config.dart (app).
export const MONTHLY_PRICE = 10000;

export const formatRupiah = (n) => `Rp${n.toLocaleString('id-ID')}`;

export const priceForMonths = (months) => MONTHLY_PRICE * months;
