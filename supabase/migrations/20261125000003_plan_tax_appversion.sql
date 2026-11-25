-- ============================================================================
-- Tahap 2 & 3
--   1. get_my_plan(): status langganan + JAM SERVER (anti akal-akalan jam HP).
--   2. Diskon & pajak opsional per pesanan (kolom baru, default kosong → APK
--      lama tidak terpengaruh).
--   3. app_config: info versi terbaru di Play Store untuk popup update /
--      wajib update di app.
-- ============================================================================

-- ── 1. Status langganan dengan jam server ───────────────────────────────────
create or replace function public.get_my_plan()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'plan_type',  p.plan_type,
    'expires_at', p.trial_expires_at,
    'server_now', now()
  )
  from public.profiles p
  where p.id = (select auth.uid());
$$;
revoke execute on function public.get_my_plan() from public, anon;
grant execute on function public.get_my_plan() to authenticated;

-- ── 2. Diskon & pajak ───────────────────────────────────────────────────────
alter table public.orders
  add column if not exists subtotal        numeric(14,2),
  add column if not exists discount_amount numeric(14,2) not null default 0,
  add column if not exists tax_name        text,
  add column if not exists tax_percent     numeric(5,2),
  add column if not exists tax_amount      numeric(14,2) not null default 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'orders_discount_tax_check') then
    alter table public.orders add constraint orders_discount_tax_check
      check (discount_amount >= 0 and tax_amount >= 0
             and (tax_percent is null or (tax_percent >= 0 and tax_percent <= 100)));
  end if;
end $$;

-- ── 3. Info versi aplikasi (satu baris) ─────────────────────────────────────
create table if not exists public.app_config (
  id                  int primary key default 1 check (id = 1),
  latest_version_code int  not null default 1,   -- build number terbaru di Play Store
  latest_version_name text not null default '',
  min_version_code    int  not null default 1,   -- di bawah ini WAJIB update
  release_notes       text not null default '',
  updated_at          timestamptz not null default now()
);
alter table public.app_config enable row level security;
drop policy if exists app_config_read on public.app_config;
create policy app_config_read on public.app_config for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public.app_config from anon, authenticated;
grant select on public.app_config to anon, authenticated;

-- Versi yang sedang beredar = 1.1.0 (build 5). Naikkan setelah 1.2.0 LIVE di Play Store.
insert into public.app_config (id, latest_version_code, latest_version_name, min_version_code)
values (1, 5, '1.1.0', 1)
on conflict (id) do nothing;
