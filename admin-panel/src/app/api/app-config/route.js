import { NextResponse } from 'next/server';
import { getAdminClient, checkAdminAuth } from '@/lib/supabaseAdmin';

export const dynamic = 'force-dynamic';

// Info versi aplikasi yang dibaca app untuk popup update / wajib update.
export async function GET(request) {
  if (!checkAdminAuth(request)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const { data, error } = await getAdminClient().from('app_config').select('*').eq('id', 1).maybeSingle();
    if (error) throw error;
    return NextResponse.json({ config: data });
  } catch (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function POST(request) {
  if (!checkAdminAuth(request)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  try {
    const body = await request.json();
    const latest = Number(body.latestVersionCode);
    const min = Number(body.minVersionCode);
    if (!Number.isInteger(latest) || !Number.isInteger(min) || latest < 1 || min < 1) {
      return NextResponse.json({ error: 'Version code harus bilangan bulat >= 1' }, { status: 400 });
    }
    if (min > latest) {
      return NextResponse.json({ error: 'Versi minimum tidak boleh lebih tinggi dari versi terbaru' }, { status: 400 });
    }
    const { data, error } = await getAdminClient()
      .from('app_config')
      .upsert({
        id: 1,
        latest_version_code: latest,
        latest_version_name: String(body.latestVersionName || '').slice(0, 30),
        min_version_code: min,
        release_notes: String(body.releaseNotes || '').slice(0, 500),
        updated_at: new Date().toISOString(),
      })
      .select()
      .single();
    if (error) throw error;
    return NextResponse.json({ config: data });
  } catch (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
