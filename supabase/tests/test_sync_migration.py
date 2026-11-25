"""
Tes lokal untuk migration sinkronisasi (Tahap 1) — tanpa menyentuh Supabase produksi.

Jalankan:
    python -m venv .venv && .venv/bin/pip install pgserver psycopg2-binary
    .venv/bin/python supabase/tests/test_sync_migration.py

Mensimulasikan:
  * APK LAMA (insert/upsert/delete langsung ke tabel, seperti versi yang ada di HP user)
  * APP BARU (push_changes / pull_changes / register_device)
  * isolasi antar user, hapus akun (cascade), presisi uang.
"""
import json
import pathlib
import shutil
import sys
import tempfile
import uuid

import pgserver
import psycopg2

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "migrations" / "20261125000002_sync_foundation.sql"
MIGRATION3 = ROOT / "migrations" / "20261125000003_plan_tax_appversion.sql"
STUB = ROOT / "tests" / "stub_prod_schema.sql"

A = str(uuid.uuid4())
B = str(uuid.uuid4())
failures = []


def check(name, cond, detail=""):
    print(("  PASS " if cond else "  FAIL ") + name + ("" if cond else f"  -> {detail}"))
    if not cond:
        failures.append(name)


class Db:
    def __init__(self, uri):
        self.conn = psycopg2.connect(uri)
        self.conn.autocommit = True

    def as_user(self, uid):
        """Seperti request PostgREST: role authenticated + JWT sub."""
        cur = self.conn.cursor()
        cur.execute("reset role")
        cur.execute("select set_config('request.jwt.claim.sub', %s, false)", (uid,))
        cur.execute("set role authenticated")
        return cur

    def as_admin(self):
        cur = self.conn.cursor()
        cur.execute("reset role")
        cur.execute("select set_config('request.jwt.claim.sub', '', false)")
        return cur

    def q(self, cur, sql, args=None):
        cur.execute(sql, args)
        return cur.fetchall() if cur.description else None


def push(db, uid, ops):
    cur = db.as_user(uid)
    return db.q(cur, "select public.push_changes(%s::jsonb)", (json.dumps(ops),))[0][0]


def pull(db, uid, table, since=None, after=None, limit=500):
    cur = db.as_user(uid)
    return db.q(cur, "select public.pull_changes(%s, %s, %s, %s)", (table, since, after, limit))[0][0]


def main():
    tmp = tempfile.mkdtemp(prefix="posin-pg-")
    srv = pgserver.get_server(tmp, cleanup_mode="stop")
    try:
        db = Db(srv.get_uri())
        cur = db.as_admin()
        cur.execute(STUB.read_text())
        db.q(cur, "insert into auth.users values (%s,'a@x'),(%s,'b@x')", (A, B))

        # ── Data lama, dibuat APK lama SEBELUM migration ──────────────────────
        old = db.as_user(A)
        old.execute("""insert into public.orders (id, order_number, total, payment_method, created_at, user_id, daily_number)
                       values ('o-old-1','20261124-100000',23500,'Tunai','2026-11-24T10:00:00.000',%s,'001'),
                              ('o-old-2','20261124-110000',1020000,'QRIS','2026-11-24T04:00:00.000Z',%s,'002')""", (A, A))
        old.execute("""insert into public.order_items (id, order_id, product_id, product_name, price, qty, subtotal, user_id)
                       values ('i-old-1','o-old-1','p1','Kopi',23500,1,23500,%s)""", (A,))
        old.execute("""insert into public.products (id, name, price, created_at, user_id)
                       values ('p1','Kopi',23500,'2026-01-01T00:00:00.000',%s)""", (A,))
        old.execute("""insert into public.products (id, name, price, created_at, user_id)
                       values ('p-garbage','Salah input',5.46667e+27,'2026-04-06T23:16:45.044191',%s)""", (A,))
        old.execute("""insert into public.settings (user_id, key, value) values (%s,'store_name','Toko A'),
                       (%s,'printer_address','AA:BB')""", (A, A))

        # ── Migration ────────────────────────────────────────────────────────
        cur = db.as_admin()
        cur.execute(MIGRATION.read_text())
        print("Migration OK")
        cur.execute(MIGRATION.read_text())
        print("Migration idempotent (2x) OK")

        print("\n[Data lama setelah migration]")
        r = db.q(db.as_admin(), "select id, created_at_ts at time zone 'UTC', total from public.orders order by id")
        check("created_at tanpa zona dianggap WIB", str(r[0][1]) == "2026-11-24 03:00:00", r[0])
        check("created_at dengan Z tetap UTC", str(r[1][1]) == "2026-11-24 04:00:00", r[1])
        check("uang numeric presisi", str(r[1][2]) == "1020000.00", r[1])
        r = db.q(db.as_admin(), "select price, is_active from public.products where id='p-garbage'")
        check("harga mustahil (5e27) dinolkan & produk dinonaktifkan", r == [(0, 0)], r)
        try:
            db.as_user(A).execute("""insert into public.products (id, name, price, created_at, user_id)
                                     values ('p-bad2','x',99999999999,'x',%s)""", (A,))
            check("harga mustahil baru ditolak database", False)
        except psycopg2.Error:
            check("harga mustahil baru ditolak database", True)
        r = db.q(db.as_user(A), "select key from public.settings order by key")
        check("setting printer disembunyikan dari APK lama", r == [("store_name",)], r)

        print("\n[APK lama tetap berfungsi]")
        old = db.as_user(A)
        old.execute("""insert into public.orders (id, order_number, total, payment_method, created_at, user_id, daily_number)
                       values ('o-old-3','x',10000,'Tunai','2026-11-25T09:00:00.000',%s,'003')
                       on conflict (id) do update set total = excluded.total""", (A,))
        old.execute("""insert into public.settings (user_id, key, value) values (%s,'store_name','Toko A2')
                       on conflict (user_id, key) do update set value = excluded.value""", (A,))
        r = db.q(old, "select count(*) from public.orders")
        check("APK lama: upsert order + select", r[0][0] == 3, r)
        # APK lama menghapus order: hapus item dulu, lalu order
        old.execute("delete from public.order_items where order_id = 'o-old-1'")
        old.execute("delete from public.orders where id = 'o-old-1'")
        r = db.q(old, "select id from public.orders order by id")
        check("APK lama: order terhapus tidak terlihat lagi", ("o-old-1",) not in r, r)
        r = db.q(db.as_admin(), "select deleted_at is not null from public.orders where id='o-old-1'")
        check("hapus dari APK lama jadi soft delete (jejak audit)", r == [(True,)], r)

        print("\n[App baru: push_changes]")
        oid = "o-new-1"
        order = {"id": oid, "order_number": "20261125-120000", "daily_number": "A-001", "total": 33500,
                 "payment_method": "Tunai", "amount_paid": 50000, "change_amount": 16500,
                 "created_at": "2026-11-25T12:00:00.000", "created_at_ts": "2026-11-25T05:00:00Z",
                 "device_id": "dev-aaaaaaaa", "cashier_name": "Sari", "customer_name": "Meja 4",
                 "updated_at": "1999-01-01T00:00:00Z", "user_id": B}  # user_id palsu harus diabaikan
        items = [{"id": "i-new-1", "order_id": oid, "product_id": "p1", "product_name": "Kopi",
                  "price": 23500, "qty": 1, "subtotal": 23500},
                 {"id": "i-new-2", "order_id": oid, "product_id": "p2", "product_name": "Roti",
                  "price": 10000, "qty": 1, "subtotal": 10000}]
        ops = [{"t": "orders", "k": "insert", "r": order}] + [{"t": "order_items", "k": "insert", "r": i} for i in items]
        res = push(db, A, ops)
        check("push order + item dalam 1 panggilan", res["applied"] == 3, res)
        res = push(db, A, ops)
        r = db.q(db.as_admin(), "select count(*) from public.order_items where order_id=%s", (oid,))
        check("push ulang (retry) tidak membuat duplikat", r[0][0] == 2, r)
        r = db.q(db.as_admin(), "select user_id, updated_at > now() - interval '1 minute', customer_name from public.orders where id=%s", (oid,))
        check("user_id dipaksa milik pemanggil", str(r[0][0]) == A, r)
        check("updated_at dari jam server, bukan dari client", r[0][1] is True, r)
        check("kolom baru tersimpan", r[0][2] == "Meja 4", r)

        # Push yang gagal di tengah harus membatalkan semuanya (atomik)
        bad = [{"t": "orders", "k": "insert", "r": {**order, "id": "o-atomic"}},
               {"t": "order_items", "k": "insert", "r": {"id": "i-bad"}}]  # kolom wajib hilang
        try:
            push(db, A, bad)
            check("push gagal harus error", False)
        except psycopg2.Error:
            pass
        r = db.q(db.as_admin(), "select count(*) from public.orders where id='o-atomic'")
        check("push gagal = tidak ada yang tersimpan (atomik)", r[0][0] == 0, r)

        # Order tidak bisa diubah, kecuali di-void (satu arah)
        push(db, A, [{"t": "orders", "k": "upsert", "r": {**order, "total": 1}}])
        r = db.q(db.as_admin(), "select total from public.orders where id=%s", (oid,))
        check("total order tidak bisa diubah setelah dibuat", float(r[0][0]) == 33500, r)
        push(db, A, [{"t": "orders", "k": "upsert", "r": {**order, "status": "void", "void_reason": "salah input",
                                                           "voided_at": "2026-11-25T05:10:00Z"}}])
        r = db.q(db.as_admin(), "select status, void_reason from public.orders where id=%s", (oid,))
        check("order bisa di-void dengan alasan", r == [("void", "salah input")], r)
        push(db, A, [{"t": "orders", "k": "upsert", "r": {**order, "status": "paid"}}])
        r = db.q(db.as_admin(), "select status from public.orders where id=%s", (oid,))
        check("void tidak bisa dibatalkan", r == [("void",)], r)
        r = db.q(db.as_user(A), "select count(*) from public.orders where id=%s", (oid,))
        check("order void disembunyikan dari APK lama (laporan lama tidak menggelembung)", r[0][0] == 0, r)

        # Katalog: last write wins, delete menang atas edit basi
        push(db, A, [{"t": "products", "k": "upsert", "r": {"id": "p1", "name": "Kopi Susu", "price": 25000,
                                                            "created_at": "x", "is_active": 1}}])
        r = db.q(db.as_admin(), "select name, price, created_at from public.products where id='p1'")
        check("edit produk tersimpan (created_at tidak berubah)", r == [("Kopi Susu", 25000, "2026-01-01T00:00:00.000")], r)
        push(db, A, [{"t": "products", "k": "delete", "r": {"id": "p1"}}])
        push(db, A, [{"t": "products", "k": "upsert", "r": {"id": "p1", "name": "Edit basi", "price": 1, "created_at": "x"}}])
        r = db.q(db.as_admin(), "select name, deleted_at is not null from public.products where id='p1'")
        check("produk terhapus tidak hidup lagi oleh edit basi", r == [("Kopi Susu", True)], r)

        push(db, A, [{"t": "settings", "k": "upsert", "r": {"key": "receipt_footer", "value": "Makasih"}}])
        r = db.q(db.as_user(A), "select value from public.settings where key='receipt_footer'")
        check("setting di-upsert", r == [("Makasih",)], r)

        print("\n[Isolasi antar user]")
        push(db, B, [{"t": "orders", "k": "upsert", "r": {**order, "status": "void"}}])
        push(db, B, [{"t": "products", "k": "upsert", "r": {"id": "o-old-2", "name": "hack", "price": 1, "created_at": "x"}}])
        r = db.q(db.as_admin(), "select user_id from public.orders where id=%s", (oid,))
        check("user B tidak bisa menimpa order user A", str(r[0][0]) == A, r)
        rows = pull(db, B, "orders")["rows"]
        check("pull user B tidak berisi data user A", all(x["id"] != oid for x in rows), rows)
        try:
            push(db, A, [{"t": "profiles", "k": "upsert", "r": {"id": A}}])
            check("tabel di luar whitelist ditolak", False)
        except psycopg2.Error:
            check("tabel di luar whitelist ditolak", True)

        print("\n[App baru: pull_changes]")
        res = pull(db, A, "orders")
        ids = [x["id"] for x in res["rows"]]
        check("pull menyertakan tombstone & order void", "o-old-1" in ids and oid in ids, ids)
        check("pull tidak mengirim user_id", all("user_id" not in x for x in res["rows"]), res["rows"][0])
        check("angka uang dikirim sebagai number JSON", isinstance(res["rows"][0]["total"], (int, float)), res["rows"][0])
        last = res["rows"][-1]
        res2 = pull(db, A, "orders", last["updated_at"], last["id"])
        check("pull dari kursor terakhir = kosong", res2["rows"] == [], res2)
        # paginasi
        p1 = pull(db, A, "orders", limit=2)["rows"]
        p2 = pull(db, A, "orders", p1[-1]["updated_at"], p1[-1]["id"], limit=2)["rows"]
        check("paginasi tidak tumpang tindih", not ({x["id"] for x in p1} & {x["id"] for x in p2}) and len(p1) == 2, (p1, p2))
        s = pull(db, A, "settings")["rows"]
        check("pull settings memakai kunci 'key'", any(x["key"] == "printer_address" and x["deleted_at"] for x in s), s)

        print("\n[register_device]")
        cur = db.as_user(A)
        d1 = db.q(cur, "select public.register_device('dev-aaaaaaaa','HP Kasir 1')")[0][0]
        d2 = db.q(cur, "select public.register_device('dev-bbbbbbbb','HP Kasir 2')")[0][0]
        d1b = db.q(cur, "select public.register_device('dev-aaaaaaaa')")[0][0]
        check("HP pertama = A, kedua = B", (d1["code"], d2["code"]) == ("A", "B"), (d1, d2))
        check("HP yang sama dapat kode yang sama", d1b["code"] == "A" and d1b["device_count"] == 2, d1b)
        db.q(db.as_user(B), "select public.register_device('dev-aaaaaaaa')")
        r = db.q(db.as_admin(), "select count(*) from public.devices where id='dev-aaaaaaaa'")
        check("HP yang sama dipakai 2 akun tidak bentrok", r[0][0] == 2, r)

        print("\n[Migration 3: langganan, diskon/pajak, versi app]")
        cur = db.as_admin()
        cur.execute(MIGRATION3.read_text())
        cur.execute(MIGRATION3.read_text())
        print("  Migration 3 OK (2x)")
        db.q(cur, "insert into public.profiles (id, plan_type, trial_expires_at) values (%s,'premium','2030-01-01')", (A,))
        plan = db.q(db.as_user(A), "select public.get_my_plan()")[0][0]
        check("get_my_plan mengembalikan plan + jam server", plan["plan_type"] == "premium" and "server_now" in plan, plan)
        plan_b = db.q(db.as_user(B), "select public.get_my_plan()")[0][0]
        check("get_my_plan user lain tidak bocor", plan_b is None, plan_b)
        try:
            db.as_user(A).execute("update public.profiles set plan_type='premium' where id=%s", (A,))
            check("user tetap tidak bisa mengubah plan sendiri", False)
        except psycopg2.Error:
            check("user tetap tidak bisa mengubah plan sendiri", True)

        push(db, A, [{"t": "orders", "k": "insert", "r": {**order, "id": "o-tax", "subtotal": 30000,
            "discount_amount": 3000, "tax_name": "PB1", "tax_percent": 10, "tax_amount": 2700, "total": 29700}}])
        r = db.q(db.as_admin(), "select subtotal, discount_amount, tax_name, tax_amount, total from public.orders where id='o-tax'")
        check("order dengan diskon & pajak tersimpan", [tuple(str(x) for x in r[0])] == [("30000.00", "3000.00", "PB1", "2700.00", "29700.00")], r)
        r = db.q(db.as_admin(), "select discount_amount, tax_amount from public.orders where id=%s", (oid,))
        check("order lama: diskon & pajak default 0", [tuple(float(x) for x in r[0])] == [(0.0, 0.0)], r)

        anon = db.conn.cursor(); anon.execute("reset role"); anon.execute("set role anon")
        r = db.q(anon, "select latest_version_code, min_version_code from public.app_config")
        check("app_config bisa dibaca tanpa login", r == [(5, 1)], r)
        try:
            db.as_user(A).execute("update public.app_config set min_version_code = 99")
            check("user tidak bisa mengubah app_config", False)
        except psycopg2.Error:
            check("user tidak bisa mengubah app_config", True)

        print("\n[Realtime & hapus akun]")
        r = db.q(db.as_admin(), "select count(*) from pg_publication_tables where pubname='supabase_realtime'")
        check("7 tabel masuk publication realtime", r[0][0] == 7, r)
        cur = db.as_admin()
        cur.execute("delete from auth.users where id=%s", (A,))
        r = db.q(cur, "select (select count(*) from public.orders where user_id=%s) + (select count(*) from public.products where user_id=%s)", (A, A))
        check("hapus akun (admin) benar-benar menghapus data (cascade)", r[0][0] == 0, r)
    finally:
        srv.cleanup()
        shutil.rmtree(tmp, ignore_errors=True)

    print("\n" + ("SEMUA TES LULUS" if not failures else f"{len(failures)} TES GAGAL: {failures}"))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
