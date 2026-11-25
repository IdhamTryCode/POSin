import { createClient } from '@supabase/supabase-js';
import { createHmac, timingSafeEqual } from 'crypto';

const supabaseUrl = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://zjsuaniatdjroklgxyuy.supabase.co';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SECRET_KEY || '';

// Sesi admin berlaku 12 jam, setelah itu harus login ulang.
const TOKEN_TTL_MS = 12 * 60 * 60 * 1000;
const MIN_PASSWORD_LENGTH = 12;

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

/**
 * Password admin WAJIB diset lewat env. Tidak ada nilai default: repo ini publik,
 * jadi default apa pun sama saja dengan tanpa password.
 */
function getAdminPassword() {
  const pw = process.env.ADMIN_PASSWORD || '';
  if (pw.length < MIN_PASSWORD_LENGTH) {
    throw new Error(`ADMIN_PASSWORD belum diset atau kurang dari ${MIN_PASSWORD_LENGTH} karakter.`);
  }
  return pw;
}

function sign(payload) {
  // Kunci HMAC diturunkan dari password: ganti password = semua sesi lama otomatis batal.
  return createHmac('sha256', `posin-admin:${getAdminPassword()}`).update(payload).digest('base64url');
}

function safeEqual(a, b) {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  return ba.length === bb.length && timingSafeEqual(ba, bb);
}

export function verifyPassword(input) {
  return typeof input === 'string' && safeEqual(input, getAdminPassword());
}

export function issueAdminToken() {
  const exp = String(Date.now() + TOKEN_TTL_MS);
  return `${exp}.${sign(exp)}`;
}

export function checkAdminAuth(req) {
  try {
    const token = req.headers.get('x-admin-token') || '';
    const [exp, sig] = token.split('.');
    if (!exp || !sig) return false;
    if (Number(exp) < Date.now()) return false;
    return safeEqual(sig, sign(exp));
  } catch {
    // ADMIN_PASSWORD tidak valid → tolak semua akses.
    return false;
  }
}
