import { NextResponse } from 'next/server';
import { getAdminClient, checkAdminAuth } from '@/lib/supabaseAdmin';

export async function POST(request) {
  if (!checkAdminAuth(request)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const { action, userId, planType, expiresAt, ban } = await request.json();
    if (!userId) {
      return NextResponse.json({ error: 'userId wajib diisi' }, { status: 400 });
    }

    const supabase = getAdminClient();

    if (action === 'update_plan') {
      // Upsert profiles
      const { data, error } = await supabase
        .from('profiles')
        .upsert({
          id: userId,
          plan_type: planType,
          trial_expires_at: expiresAt,
        })
        .select()
        .single();

      if (error) throw error;
      return NextResponse.json({ success: true, profile: data });
    }

    if (action === 'toggle_ban') {
      // Ban atau unban user di Supabase Auth
      // 876600h = 100 tahun
      const banDuration = ban ? '876600h' : 'none';
      const { data, error } = await supabase.auth.admin.updateUserById(userId, {
        ban_duration: banDuration,
      });

      if (error) throw error;
      return NextResponse.json({ success: true, user: data.user });
    }

    if (action === 'delete_user') {
      // Hapus data dan user di Auth
      const { error } = await supabase.auth.admin.deleteUser(userId);
      if (error) throw error;
      return NextResponse.json({ success: true, deleted: true });
    }

    return NextResponse.json({ error: 'Action tidak dikenal' }, { status: 400 });
  } catch (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
