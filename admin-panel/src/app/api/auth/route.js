import { NextResponse } from 'next/server';
import { issueAdminToken, verifyPassword } from '@/lib/supabaseAdmin';

export async function POST(request) {
  try {
    const { password } = await request.json();

    if (verifyPassword(password)) {
      return NextResponse.json({ success: true, token: issueAdminToken() });
    }

    // Perlambat tebakan password (brute force).
    await new Promise((r) => setTimeout(r, 1500));
    return NextResponse.json({ error: 'Password Admin salah!' }, { status: 401 });
  } catch (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
