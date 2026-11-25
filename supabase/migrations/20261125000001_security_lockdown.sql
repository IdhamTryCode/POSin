-- ============================================================================
-- Tahap 0: Keamanan
-- 1. User tidak boleh lagi mengubah plan/masa aktifnya sendiri.
--    Sebelumnya policy "Users can update own profile" tanpa batasan kolom membuat
--    siapa pun yang login bisa PATCH plan_type='premium' lewat REST API.
-- 2. Profil dibuat HANYA oleh trigger handle_new_user (trial 3 bulan).
-- 3. Fungsi SECURITY DEFINER tidak boleh dipanggil publik lewat /rest/v1/rpc.
-- 4. admin_user_stats(): statistik per user untuk admin-panel (service_role saja).
-- Aman untuk APK lama: semua user sudah punya profil, jadi jalur insert dari
-- client (plan_service.dart versi lama) tidak pernah terpakai lagi.
-- ============================================================================

-- ── profiles: client hanya boleh membaca profil sendiri ────────────────────
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "Users can view own profile"   on public.profiles;

revoke insert, update, delete, truncate, references, trigger
  on public.profiles from anon, authenticated;
revoke all on public.profiles from anon;
grant select on public.profiles to authenticated;

create policy "Users can view own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

alter table public.profiles
  alter column trial_expires_at set default (now() + interval '3 months');

-- ── Trigger pembuat profil: trial 3 bulan, search_path dikunci ─────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, plan_type, trial_expires_at)
  values (new.id, 'free', now() + interval '3 months')
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

-- ── Statistik admin (dipanggil admin-panel dengan service_role) ─────────────
create or replace function public.admin_user_stats()
returns table (user_id uuid, categories bigint, products bigint, orders bigint)
language sql
stable
security definer  -- butuh akses ke auth.users; EXECUTE hanya untuk service_role
set search_path = ''
as $$
  select u.id,
         (select count(*) from public.categories c where c.user_id = u.id),
         (select count(*) from public.products   p where p.user_id = u.id),
         (select count(*) from public.orders     o where o.user_id = u.id)
  from auth.users u;
$$;

revoke execute on function public.admin_user_stats() from public, anon, authenticated;
grant execute on function public.admin_user_stats() to service_role;
