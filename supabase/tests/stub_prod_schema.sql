-- Tiruan minimal skema produksi Supabase POSin (per 2026-11-25, sebelum Tahap 1)
-- untuk mengetes migration secara lokal. BUKAN untuk dijalankan di Supabase.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role authenticator login noinherit;
grant anon, authenticated, service_role to authenticator;

create schema auth;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

create publication supabase_realtime;

create table public.categories (
  id text primary key, name text not null, color bigint not null, created_at text not null,
  user_id uuid references auth.users(id) on delete cascade);
create table public.products (
  id text primary key, name text not null, price real not null, category_id text, image_path text,
  is_active integer not null default 1, created_at text not null,
  user_id uuid references auth.users(id) on delete cascade);
create table public.product_variant_groups (
  id text primary key, product_id text not null references public.products(id) on delete cascade,
  name text not null, is_required integer not null default 1, created_at text not null,
  user_id uuid references auth.users(id) on delete cascade);
create table public.product_variant_options (
  id text primary key, group_id text not null references public.product_variant_groups(id) on delete cascade,
  name text not null, price_modifier real not null default 0, created_at text not null,
  user_id uuid references auth.users(id) on delete cascade);
create table public.orders (
  id text primary key, order_number text not null, total real not null, payment_method text not null,
  amount_paid real, change_amount real, note text, created_at text not null,
  user_id uuid references auth.users(id) on delete cascade, daily_number text);
create table public.order_items (
  id text primary key, order_id text not null references public.orders(id),
  product_id text not null, product_name text not null, price real not null, qty integer not null,
  subtotal real not null, variant_label text,
  user_id uuid references auth.users(id) on delete cascade, note text);
create table public.settings (
  user_id uuid not null references auth.users(id) on delete cascade, key text not null,
  value text not null default '', primary key (user_id, key));

do $$
declare t text; pname text;
begin
  foreach t in array array['categories','products','product_variant_groups','product_variant_options',
                           'orders','order_items','settings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('grant all on public.%I to anon, authenticated, service_role', t);
    pname := case t
      when 'product_variant_groups' then 'User can manage own variant groups'
      when 'product_variant_options' then 'User can manage own variant options'
      when 'order_items' then 'User can manage own order items'
      else 'User can manage own ' || t end;
    execute format('create policy %I on public.%I for all using (auth.uid() = user_id) with check (auth.uid() = user_id)', pname, t);
  end loop;
end $$;

-- profiles setelah Tahap 0 (security_lockdown): client hanya bisa SELECT.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  plan_type text not null default 'free',
  trial_expires_at timestamptz not null default (now() + interval '3 months'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
alter table public.profiles enable row level security;
grant select on public.profiles to authenticated;
create policy "Users can view own profile" on public.profiles for select to authenticated
  using ((select auth.uid()) = id);
