import { NextResponse } from 'next/server';
import { getAdminClient, checkAdminAuth } from '@/lib/supabaseAdmin';

export const dynamic = 'force-dynamic';

export async function GET(request) {
  if (!checkAdminAuth(request)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const supabase = getAdminClient();

    // 1. Ambil list users dari Supabase Auth
    const { data: authData, error: authError } = await supabase.auth.admin.listUsers();
    if (authError) throw authError;

    // 2. Ambil semua profiles
    const { data: profiles, error: profileError } = await supabase
      .from('profiles')
      .select('*');
    if (profileError) throw profileError;

    const profileMap = new Map();
    (profiles || []).forEach((p) => profileMap.set(p.id, p));

    // 3. Ambil statistik total produk, kategori, order per user jika memungkinkan
    const [catRes, prodRes, ordRes] = await Promise.all([
      supabase.from('categories').select('user_id'),
      supabase.from('products').select('user_id'),
      supabase.from('orders').select('user_id'),
    ]);

    const countMap = new Map();
    const countItems = (items, key) => {
      (items || []).forEach((item) => {
        if (!item.user_id) return;
        const curr = countMap.get(item.user_id) || { categories: 0, products: 0, orders: 0 };
        curr[key] = (curr[key] || 0) + 1;
        countMap.set(item.user_id, curr);
      });
    };

    countItems(catRes.data, 'categories');
    countItems(prodRes.data, 'products');
    countItems(ordRes.data, 'orders');

    // 4. Gabungkan data
    const now = new Date();
    const users = (authData.users || []).map((user) => {
      const profile = profileMap.get(user.id) || {};
      const planType = profile.plan_type || 'free';
      const expiresAt = profile.trial_expires_at ? new Date(profile.trial_expires_at) : null;
      const isExpired = expiresAt ? now > expiresAt : true;
      const isActive = planType === 'premium' ? !isExpired : (!isExpired);
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
