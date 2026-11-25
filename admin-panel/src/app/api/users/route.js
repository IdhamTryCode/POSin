import { NextResponse } from 'next/server';
import { getAdminClient, checkAdminAuth } from '@/lib/supabaseAdmin';

export const dynamic = 'force-dynamic';

export async function GET(request) {
  if (!checkAdminAuth(request)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const supabase = getAdminClient();

    // 1. Ambil SEMUA user dari Supabase Auth (listUsers dipaginasi, default 50/halaman)
    const authUsers = [];
    for (let page = 1; ; page++) {
      const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) throw error;
      authUsers.push(...(data.users || []));
      if (!data.users || data.users.length < 1000) break;
    }

    // 2. Ambil semua profiles
    const { data: profiles, error: profileError } = await supabase
      .from('profiles')
      .select('*');
    if (profileError) throw profileError;

    const profileMap = new Map();
    (profiles || []).forEach((p) => profileMap.set(p.id, p));

    // 3. Statistik per user dihitung di database (select semua baris terpotong di 1000)
    const { data: stats, error: statsError } = await supabase.rpc('admin_user_stats');
    if (statsError) throw statsError;
    const countMap = new Map();
    (stats || []).forEach((r) => countMap.set(r.user_id, {
      categories: Number(r.categories) || 0,
      products: Number(r.products) || 0,
      orders: Number(r.orders) || 0,
    }));

    // 4. Gabungkan data
    const now = new Date();
    const users = authUsers.map((user) => {
      const profile = profileMap.get(user.id) || {};
      const planType = profile.plan_type || 'free';
      const expiresAt = profile.trial_expires_at ? new Date(profile.trial_expires_at) : null;
      const isExpired = expiresAt ? now > expiresAt : true;
      const isActive = !isExpired;
      const isBanned = !!user.banned_until && new Date(user.banned_until) > now;
      const counts = countMap.get(user.id) || { categories: 0, products: 0, orders: 0 };

      return {
        id: user.id,
        email: user.email,
        createdAt: user.created_at,
        lastSignInAt: user.last_sign_in_at,
        banned: isBanned,
        bannedUntil: user.banned_until,
        planType,
        trialExpiresAt: profile.trial_expires_at,
        isActive,
        isExpired,
        counts,
      };
    });

    return NextResponse.json({
      users,
      summary: {
        total: users.length,
        premium: users.filter((u) => u.planType === 'premium' && !u.isExpired).length,
        freeActive: users.filter((u) => u.planType === 'free' && !u.isExpired).length,
        expired: users.filter((u) => u.isExpired).length,
        banned: users.filter((u) => u.banned).length,
      },
    });
  } catch (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
