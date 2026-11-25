-- ============================================================================
-- Tahap 1: Fondasi sinkronisasi multi-HP
--
-- Masalah lama: app menarik SEMUA data lalu menghapus isi lokal (pesanan offline
-- yang belum ter-upload bisa hilang), tidak ada realtime, N+1 request per order,
-- dan terpotong 1000 baris.
--
-- Desain baru (APK lama TETAP jalan — semua perubahan bersifat menambah):
--   * updated_at (diisi server) + deleted_at (soft delete) di semua tabel data.
--   * push_changes(ops)  : app baru mengirim antrean perubahan dalam 1 transaksi.
--   * pull_changes(...)  : app baru menarik HANYA yang berubah sejak kursor terakhir,
--                          termasuk "tombstone" penghapusan, dengan paginasi.
--   * DELETE dari APK lama otomatis diubah jadi soft delete (jejak audit tetap ada).
--   * Order bisa di-VOID (status='void' + alasan) alih-alih dihapus.
--   * devices + register_device(): kode per HP (A, B, C...) untuk nomor antrean
--     yang tidak bentrok antar kasir, walau offline.
--   * Uang: real (float 32-bit, ~7 digit) -> numeric(14,2).
--   * Index + RLS memakai (select auth.uid()) agar tetap cepat saat data besar.
--   * Tabel data masuk publication supabase_realtime.
-- ============================================================================

-- ── 1. Kolom sinkronisasi ───────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['categories','products','product_variant_groups',
                           'product_variant_options','orders','order_items','settings']
  loop
    execute format('alter table public.%I add column if not exists updated_at timestamptz not null default now()', t);
    execute format('alter table public.%I add column if not exists deleted_at timestamptz', t);
    execute format('alter table public.%I alter column user_id set default auth.uid()', t);
  end loop;
end $$;

alter table public.orders
  add column if not exists status        text not null default 'paid',
  add column if not exists voided_at     timestamptz,
  add column if not exists void_reason   text,
  add column if not exists device_id     text,
  add column if not exists cashier_name  text,
  add column if not exists customer_name text,
  add column if not exists created_at_ts timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'orders_status_check') then
    alter table public.orders add constraint orders_status_check check (status in ('paid', 'void'));
  end if;
end $$;

-- ── 2. Uang: real -> numeric ────────────────────────────────────────────────
-- Data produksi berisi harga mustahil (mis. 5.47e+27 dari salah input, belum
-- pernah dipesan) yang tidak muat di numeric(14,2). Harga >= Rp10 miliar
-- dinolkan & produknya dinonaktifkan supaya pemilik toko memperbaikinya.
update public.products set price = 0, is_active = 0 where abs(price) >= 1e10;
update public.product_variant_options set price_modifier = 0 where abs(price_modifier) >= 1e10;

alter table public.orders
  alter column total         type numeric(14,2),
  alter column amount_paid   type numeric(14,2),
  alter column change_amount type numeric(14,2);
alter table public.order_items
  alter column price    type numeric(14,2),
  alter column subtotal type numeric(14,2);
alter table public.products
  alter column price type numeric(14,2);
alter table public.product_variant_options
  alter column price_modifier type numeric(14,2);

-- Cegah harga mustahil masuk lagi (form di app juga sudah dibatasi).
alter table public.products drop constraint if exists products_price_range;
alter table public.products add constraint products_price_range
  check (price >= 0 and price < 10000000000);
alter table public.product_variant_options drop constraint if exists variant_options_price_range;
alter table public.product_variant_options add constraint variant_options_price_range
  check (price_modifier > -10000000000 and price_modifier < 10000000000);

-- ── 3. Trigger: updated_at selalu dari jam server ───────────────────────────
create or replace function public.sync_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- created_at lama berupa teks waktu lokal tanpa zona. created_at_ts = versi
-- timestamptz yang benar (teks tanpa zona dianggap WIB).
create or replace function public.orders_fill_created_at_ts()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.created_at_ts is null then
    begin
      if new.created_at ~ '(Z|[+-]\d\d(:?\d\d)?)$' then
        new.created_at_ts := new.created_at::timestamptz;
      else
        new.created_at_ts := new.created_at::timestamp at time zone 'Asia/Jakarta';
      end if;
    exception when others then
      new.created_at_ts := now();
    end;
  end if;
  return new;
end;
$$;

-- DELETE dari APK lama -> soft delete. Hanya untuk request dari user (role
-- authenticated); cascade dari hapus akun (admin) tetap menghapus sungguhan.
create or replace function public.sync_soft_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- current_user di fungsi SECURITY DEFINER = pemilik fungsi, jadi yang dicek
  -- adalah role sesi dari PostgREST.
  if coalesce(current_setting('role', true), '') = 'authenticated' then
    execute format('update %I.%I set deleted_at = now() where id = $1 and user_id = $2 and deleted_at is null',
                   tg_table_schema, tg_table_name)
      using old.id, old.user_id;
    return null; -- batalkan DELETE fisik
  end if;
  return old;
end;
$$;
revoke execute on function public.sync_soft_delete() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['categories','products','product_variant_groups',
                           'product_variant_options','orders','order_items','settings']
  loop
    execute format('drop trigger if exists sync_touch on public.%I', t);
    execute format('create trigger sync_touch before insert or update on public.%I
                    for each row execute function public.sync_touch()', t);
  end loop;

  foreach t in array array['categories','products','product_variant_groups',
                           'product_variant_options','orders','order_items']
  loop
    execute format('drop trigger if exists sync_soft_delete on public.%I', t);
    execute format('create trigger sync_soft_delete before delete on public.%I
                    for each row execute function public.sync_soft_delete()', t);
  end loop;
end $$;

drop trigger if exists orders_fill_created_at_ts on public.orders;
create trigger orders_fill_created_at_ts before insert or update on public.orders
  for each row execute function public.orders_fill_created_at_ts();

update public.orders set created_at_ts = null where created_at_ts is null; -- isi data lama via trigger

-- ── 4. RLS: APK lama tidak melihat baris terhapus / order void ──────────────
-- (App baru membaca lewat pull_changes yang juga mengirim tombstone.)
drop policy if exists "User can manage own categories"      on public.categories;
drop policy if exists "User can manage own products"        on public.products;
drop policy if exists "User can manage own variant groups"  on public.product_variant_groups;
drop policy if exists "User can manage own variant options" on public.product_variant_options;
drop policy if exists "User can manage own orders"          on public.orders;
drop policy if exists "User can manage own order items"     on public.order_items;
drop policy if exists "User can manage own settings"        on public.settings;

do $$
declare
  t text;
  extra text;
begin
  foreach t in array array['categories','products','product_variant_groups',
                           'product_variant_options','orders','order_items','settings']
  loop
    execute format('drop policy if exists sync_select on public.%I', t);
    execute format('drop policy if exists sync_insert on public.%I', t);
    execute format('drop policy if exists sync_update on public.%I', t);
    execute format('drop policy if exists sync_delete on public.%I', t);

    extra := case when t = 'orders' then ' and status = ''paid''' else '' end;
    execute format('create policy sync_select on public.%I for select to authenticated
                    using (user_id = (select auth.uid()) and deleted_at is null%s)', t, extra);
    execute format('create policy sync_insert on public.%I for insert to authenticated
                    with check (user_id = (select auth.uid()))', t);
    execute format('create policy sync_update on public.%I for update to authenticated
                    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
    execute format('create policy sync_delete on public.%I for delete to authenticated
                    using (user_id = (select auth.uid()))', t);
  end loop;
end $$;

-- ── 5. Index ────────────────────────────────────────────────────────────────
create index if not exists categories_sync_idx              on public.categories (user_id, updated_at, id);
create index if not exists products_sync_idx                on public.products (user_id, updated_at, id);
create index if not exists product_variant_groups_sync_idx  on public.product_variant_groups (user_id, updated_at, id);
create index if not exists product_variant_options_sync_idx on public.product_variant_options (user_id, updated_at, id);
create index if not exists orders_sync_idx                  on public.orders (user_id, updated_at, id);
create index if not exists order_items_sync_idx             on public.order_items (user_id, updated_at, id);
create index if not exists settings_sync_idx                on public.settings (user_id, updated_at, key);
create index if not exists order_items_order_id_idx         on public.order_items (order_id);
create index if not exists product_variant_groups_product_idx on public.product_variant_groups (product_id);
create index if not exists product_variant_options_group_idx  on public.product_variant_options (group_id);
create index if not exists orders_user_created_idx          on public.orders (user_id, created_at_ts);

-- ── 6. Perangkat (kode HP untuk nomor antrean) ──────────────────────────────
create table if not exists public.devices (
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id           text not null,
  code         text not null,
  name         text,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (user_id, id),
  unique (user_id, code)
);
alter table public.devices enable row level security;
drop policy if exists devices_select on public.devices;
create policy devices_select on public.devices for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete, truncate on public.devices from anon, authenticated;

create or replace function public.register_device(p_device_id text, p_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_code  text;
  v_n     int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if coalesce(length(p_device_id), 0) not between 8 and 64 then raise exception 'invalid device id'; end if;

  select code into v_code from public.devices where user_id = v_uid and id = p_device_id;

  if v_code is null then
    -- Kode berikutnya yang belum dipakai: A..Z, lalu A1, B1, ...
    for v_n in 0..999 loop
      v_code := chr(65 + (v_n % 26)) || case when v_n >= 26 then (v_n / 26)::text else '' end;
      begin
        insert into public.devices (user_id, id, code, name) values (v_uid, p_device_id, v_code, p_name);
        exit;
      exception when unique_violation then
        -- kode sudah dipakai HP lain (atau device ini baru saja didaftarkan paralel)
        select code into v_code from public.devices where user_id = v_uid and id = p_device_id;
        if v_code is not null then exit; end if;
        v_code := null;
      end;
    end loop;
  else
    update public.devices set last_seen_at = now(), name = coalesce(p_name, name)
     where user_id = v_uid and id = p_device_id;
  end if;

  return jsonb_build_object(
    'code', v_code,
    'device_count', (select count(*) from public.devices where user_id = v_uid)
  );
end;
$$;
revoke execute on function public.register_device(text, text) from public, anon;
grant execute on function public.register_device(text, text) to authenticated;

-- ── 7. push_changes: terapkan antrean perubahan dari HP dalam 1 transaksi ───
-- p_ops = [{"t": tabel, "k": "upsert"|"insert"|"delete", "r": {baris}}, ...]
--   upsert : buat / perbarui (last write wins). Baris yang sudah dihapus tidak
--            dihidupkan lagi.
--   insert : buat kalau belum ada (aman diulang).
--   delete : soft delete (deleted_at).
-- Aturan khusus: order & item order tidak bisa diubah setelah dibuat, kecuali
-- order di-void (satu arah, tidak bisa di-un-void).
create or replace function public.push_changes(p_ops jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_op      jsonb;
  v_t       text;
  v_k       text;
  v_r       jsonb;
  v_pk      text;
  v_cols    text;
  v_set     text;
  v_count   int := 0;
  allowed   constant text[] := array['categories','products','product_variant_groups',
                                     'product_variant_options','orders','order_items','settings'];
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if jsonb_typeof(p_ops) <> 'array' then raise exception 'ops must be an array'; end if;
  if jsonb_array_length(p_ops) > 500 then raise exception 'too many ops'; end if;

  for v_op in select * from jsonb_array_elements(p_ops) loop
    v_t := v_op->>'t';
    v_k := v_op->>'k';
    v_r := coalesce(v_op->'r', '{}'::jsonb) - 'updated_at' - 'deleted_at';

    if not (v_t = any (allowed)) then raise exception 'table % not allowed', v_t; end if;
    v_pk := case when v_t = 'settings' then 'user_id, key' else 'id' end;
    v_r  := v_r || jsonb_build_object('user_id', v_uid);  -- selalu milik pemanggil

    if v_k = 'delete' then
      if v_t = 'settings' then raise exception 'settings cannot be deleted'; end if;
      execute format('update public.%I set deleted_at = now()
                       where id = $1 and user_id = $2 and deleted_at is null', v_t)
        using v_r->>'id', v_uid;

    elsif v_k in ('upsert', 'insert') then
      -- Hanya kolom yang dikirim & memang ada di tabel (sisanya pakai default).
      select string_agg(quote_ident(a.attname), ', ' order by a.attnum)
        into v_cols
        from pg_attribute a
       where a.attrelid = format('public.%I', v_t)::regclass
         and a.attnum > 0 and not a.attisdropped
         and v_r ? a.attname
         and a.attname not in ('updated_at', 'deleted_at');

      if v_k = 'insert' or v_t = 'order_items' then
        v_set := null;
      elsif v_t = 'orders' then
        -- Order hanya boleh berubah menjadi void.
        v_set := 'status = excluded.status, voided_at = excluded.voided_at, void_reason = excluded.void_reason';
      else
        select string_agg(format('%1$I = excluded.%1$I', a.attname), ', ')
          into v_set
          from pg_attribute a
         where a.attrelid = format('public.%I', v_t)::regclass
           and a.attnum > 0 and not a.attisdropped
           and v_r ? a.attname
           and a.attname not in ('id', 'user_id', 'key', 'updated_at', 'deleted_at', 'created_at');
      end if;

      if v_set is null then
        execute format('insert into public.%1$I (%2$s)
                        select %2$s from jsonb_populate_record(null::public.%1$I, $1)
                        on conflict (%3$s) do nothing', v_t, v_cols, v_pk)
          using v_r;
      elsif v_t = 'orders' then
        execute format('insert into public.orders (%1$s)
                        select %1$s from jsonb_populate_record(null::public.orders, $1)
                        on conflict (id) do update set %2$s
                        where public.orders.user_id = $2 and excluded.status = ''void''
                          and public.orders.status <> ''void''', v_cols, v_set)
          using v_r, v_uid;
      else
        execute format('insert into public.%1$I (%2$s)
                        select %2$s from jsonb_populate_record(null::public.%1$I, $1)
                        on conflict (%3$s) do update set %4$s
                        where public.%1$I.user_id = $2 and public.%1$I.deleted_at is null',
                       v_t, v_cols, v_pk, v_set)
          using v_r, v_uid;
      end if;
    else
      raise exception 'unknown op kind %', v_k;
    end if;

    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('applied', v_count, 'server_time', now());
end;
$$;
revoke execute on function public.push_changes(jsonb) from public, anon;
grant execute on function public.push_changes(jsonb) to authenticated;

-- ── 8. pull_changes: ambil perubahan sejak kursor (keyset pagination) ───────
-- Mengembalikan juga baris yang sudah dihapus (deleted_at terisi) supaya HP lain
-- ikut menghapus. Kursor = (updated_at, id) baris terakhir yang diterima.
create or replace function public.pull_changes(
  p_table    text,
  p_since    timestamptz default null,
  p_after_id text default null,
  p_limit    int default 500
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_key  text;
  v_rows jsonb;
  allowed constant text[] := array['categories','products','product_variant_groups',
                                   'product_variant_options','orders','order_items','settings'];
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not (p_table = any (allowed)) then raise exception 'table % not allowed', p_table; end if;
  v_key := case when p_table = 'settings' then 'key' else 'id' end;

  execute format(
    'select coalesce(jsonb_agg(to_jsonb(x) - ''user_id'' order by x.updated_at, x.%2$I), ''[]''::jsonb)
       from (select * from public.%1$I
              where user_id = $1
                and (updated_at, %2$I) > ($2, $3)
              order by updated_at, %2$I
              limit $4) x',
    p_table, v_key)
    into v_rows
    using v_uid,
          coalesce(p_since, '-infinity'::timestamptz),
          coalesce(p_after_id, ''),
          greatest(1, least(coalesce(p_limit, 500), 1000));

  return jsonb_build_object('rows', v_rows, 'server_time', now());
end;
$$;
revoke execute on function public.pull_changes(text, timestamptz, text, int) from public, anon;
grant execute on function public.pull_changes(text, timestamptz, text, int) to authenticated;

-- ── 9. Realtime ─────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array['categories','products','product_variant_groups',
                           'product_variant_options','orders','order_items','settings']
  loop
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ── 10. Bersih-bersih: setting printer adalah milik masing-masing HP ─────────
update public.settings set deleted_at = now()
 where key in ('printer_address', 'printer_name') and deleted_at is null;
