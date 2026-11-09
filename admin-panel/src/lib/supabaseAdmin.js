import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://zjsuaniatdjroklgxyuy.supabase.co';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SECRET_KEY || '';

export function getAdminClient() {
  if (!supabaseKey) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY belum diset di Environment Variables.');
  }
  return createClient(supabaseUrl, supabaseKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

export function checkAdminAuth(req) {
  const adminSecret = process.env.ADMIN_PASSWORD || 'admin123';
  const authHeader = req.headers.get('x-admin-token');
  return authHeader === adminSecret;
}
