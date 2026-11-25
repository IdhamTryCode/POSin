# POSin — Point of Sale App

POSin adalah aplikasi kasir (POS) Android berbasis Flutter untuk usaha kuliner dan ritel kecil. Data tersimpan lokal (SQLite per akun) dan disinkronkan ke cloud (Supabase), sehingga bisa diakses dari perangkat lain.

---

## Fitur Utama

### Kasir (Cashier)
- Grid menu produk dengan foto, nama, dan harga
- Filter menu berdasarkan kategori (chip horizontal)
- Keranjang belanja real-time di bagian bawah layar
- Dukungan varian produk (ukuran, topping, dll.) dengan modifier harga
- Proses pembayaran: **Tunai** (tombol **Uang Pas** + nominal cepat, pemisah ribuan, kembalian otomatis) dan **QRIS**
- **Diskon** (Rp / %) dan **pajak/service** opsional — aktifkan di Pengaturan; kalau mati, struk tetap bersih
- Nomor antrean harian per HP (`#001`, atau `#A-001`/`#B-001` kalau toko memakai beberapa HP)
- Kosongkan keranjang bisa di-**urungkan**
- Tampilkan quantity badge di kartu produk jika sudah ditambahkan ke keranjang

### Checkout & Struk
- Modal bottom sheet pembayaran dengan pilihan metode
- Input jumlah uang tunai dengan tombol nominal cepat (otomatis dibulatkan)
- Hitung kembalian otomatis
- Layar struk digital setelah pembayaran berhasil
- Cetak struk ke **printer Bluetooth ESC/POS** (general — semua merek)
- Struk berisi: logo toko, nama, alamat, telepon, deskripsi, nomor order, tanggal, item+varian+catatan, (subtotal/diskon/pajak bila ada), total, bayar, kembalian, dan footer pesan
- **Cetak otomatis** setelah bayar (opsional, per HP)

### Manajemen Menu (Products)
- Daftar menu dikelompokkan per kategori, bisa di-collapse
- Tambah/edit produk: nama, harga, kategori, foto (upload ke Supabase Storage)
- Aktifkan/nonaktifkan menu tanpa menghapus
- Manajemen **varian produk**: grup varian (wajib/opsional) dengan opsi dan modifier harga
- Hapus produk dengan konfirmasi

### Kategori
- Buat, edit, dan hapus kategori
- Setiap kategori punya warna custom (color picker)
- Kategori muncul sebagai chip filter di halaman Kasir

### Laporan (Reports)
- Filter transaksi: **Hari Ini**, **7 Hari**, **30 Hari**, **Custom**, export PDF
- Kartu ringkasan, grafik tren, produk terlaris, rincian Tunai/QRIS
- Pesanan **tidak bisa dihapus** — hanya **dibatalkan (void)** dengan alasan wajib; tetap tercatat di riwayat (dicoret) dan tidak dihitung di omzet

### Pengaturan (Settings)
- Informasi toko: nama, alamat, telepon, deskripsi, footer struk
- Upload logo toko (tampil di struk)
- Diskon & pajak opsional (sinkron ke semua HP)
- Per HP (tidak ikut sinkron): printer Bluetooth, cetak otomatis, nama kasir
- Info langganan & perpanjangan via WhatsApp
- Keluar akun (dengan peringatan kalau masih ada data yang belum terkirim)

### Autentikasi
- Login dan registrasi akun via Supabase Auth (email + password)
- Konfirmasi email saat registrasi
- Reset password via email

### Sinkronisasi Cloud
- **Offline-first**: semua operasi berjalan lewat SQLite lokal; jualan tetap jalan tanpa internet
- Setiap perubahan masuk **antrean (outbox)** dalam transaksi yang sama → tidak ada pesanan hilang; dikirim ulang otomatis saat online
- **Realtime**: pesanan dari HP lain masuk dalam hitungan detik (Supabase Realtime + tarikan inkremental per halaman)
- Ikon awan di Kasir: status sinkron (tersinkron / menunggu / offline) + sinkron manual
- Popup **update ke Play Store** & mode **wajib update** (diatur dari admin-panel)
- Data ter-isolasi per user (SQLite per `userId`, RLS di Supabase)
- Provider di-invalidate otomatis saat user berganti (tidak ada data bocor antar akun)

---

## Langganan

| Paket | Harga | Keterangan |
|---|---|---|
| Free Trial | Gratis | 3 bulan sejak daftar (dibuat otomatis oleh trigger DB) |
| Premium | **Rp10.000/bulan** | Perpanjangan: kalau masih aktif ditambah dari tanggal habis, kalau sudah expired dihitung dari tanggal bayar |

Harga diatur di satu tempat per aplikasi: `lib/features/plan/plan_config.dart` (app) dan `admin-panel/src/lib/pricing.js` (admin).

---

## Tech Stack

| Layer | Library |
|---|---|
| UI Framework | Flutter (Dart `^3.7.0`) |
| State Management | `flutter_riverpod` (AsyncNotifier, NotifierProvider) |
| Local DB | `sqflite` + `sqflite_common_ffi` |
| Cloud / Auth | `supabase_flutter` |
| Bluetooth Print | `blue_thermal_printer` |
| Image Picker | `image_picker` |
| Charts | `fl_chart` |
| Localization | `intl` |
| Unique IDs | `uuid` |
| URL Launcher | `url_launcher` |
| App Icon | `flutter_launcher_icons` |
| Splash Screen | `flutter_native_splash` |

---

## Struktur Folder

```text
lib/
├── app.dart                    # Root widget, nav shell, auth gate
├── main.dart                   # Entry point, Supabase init
├── core/
│   ├── constants/app_colors.dart
│   ├── database/database_helper.dart   # SQLite setup, per-user DB
│   ├── screens/splash_screen.dart      # Animated splash
│   ├── supabase/
│   │   ├── supabase_config.dart        # URL & anon key
│   │   └── supabase_service.dart       # All Supabase calls
│   ├── sync/app_sync_service.dart      # Sync all providers at once
│   └── theme/app_theme.dart
├── features/
│   ├── auth/
│   │   ├── providers/          # supabase_auth_provider
│   │   └── screens/            # auth_screen (login/register)
│   ├── categories/
│   │   ├── models/category_model.dart
│   │   ├── providers/category_provider.dart
│   │   └── screens/categories_screen.dart
│   ├── orders/
│   │   ├── models/             # order_model, order_item_model
│   │   ├── providers/          # order_provider, cart_provider
│   │   └── screens/            # cashier_screen, checkout_sheet, receipt_screen
│   ├── printer/
│   │   ├── screens/printer_settings_screen.dart
│   │   └── services/printer_service.dart
│   ├── products/
│   │   ├── models/             # product_model, variant_group_model, variant_option_model
│   │   ├── providers/          # product_provider, variant_provider
│   │   └── screens/            # products_screen, product_form_screen
│   ├── reports/
│   │   └── screens/report_screen.dart
│   └── settings/
│       ├── providers/settings_provider.dart
│       └── screens/settings_screen.dart
assets/
└── images/
    └── logo.png                # App logo (1024x1024)
```

---

## Setup

### Prasyarat
- Flutter SDK **3.44.x** (3.50+ butuh migrasi ke AGP 9 — belum dilakukan)
- JDK 17
- Android SDK (target Android 5.0+ / API 21+)
- Akun [Supabase](https://supabase.com) (free tier cukup)

### Konfigurasi Supabase

1. Buat project baru di Supabase
2. Jalankan SQL schema berikut di Supabase SQL Editor:

```sql
-- Tabel categories
create table categories (
  id uuid primary key,
  user_id uuid references auth.users,
  name text not null,
  color bigint not null,
  created_at text
);

-- Tabel products
create table products (
  id uuid primary key,
  user_id uuid references auth.users,
  name text not null,
  price float8 not null,
  category_id uuid,
  image_path text,
  is_active boolean default true,
  created_at text
);

-- Tabel product_variant_groups
create table product_variant_groups (
  id uuid primary key,
  user_id uuid references auth.users,
  product_id uuid,
  name text not null,
  is_required boolean default false,
  created_at text
);

-- Tabel product_variant_options
create table product_variant_options (
  id uuid primary key,
  user_id uuid references auth.users,
  group_id uuid,
  name text not null,
  price_modifier float8 default 0,
  created_at text
);

-- Tabel orders
create table orders (
  id uuid primary key,
  user_id uuid references auth.users,
  order_number text,
  total float8,
  payment_method text,
  amount_paid float8,
  change_amount float8,
  note text,
  created_at text
);

-- Tabel order_items
create table order_items (
  id uuid primary key,
  user_id uuid references auth.users,
  order_id uuid,
  product_id uuid,
  product_name text,
  price float8,
  qty integer,
  subtotal float8,
  variant_label text
);

-- Tabel settings
create table settings (
  user_id uuid references auth.users,
  key text,
  value text,
  primary key (user_id, key)
);

-- Enable RLS pada semua tabel
alter table categories enable row level security;
alter table products enable row level security;
alter table product_variant_groups enable row level security;
alter table product_variant_options enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table settings enable row level security;

-- Policy: user hanya akses data miliknya sendiri
create policy "user_own" on categories for all using (auth.uid() = user_id);
create policy "user_own" on products for all using (auth.uid() = user_id);
create policy "user_own" on product_variant_groups for all using (auth.uid() = user_id);
create policy "user_own" on product_variant_options for all using (auth.uid() = user_id);
create policy "user_own" on orders for all using (auth.uid() = user_id);
create policy "user_own" on order_items for all using (auth.uid() = user_id);
create policy "user_own" on settings for all using (auth.uid() = user_id);

-- Storage bucket untuk logo toko
insert into storage.buckets (id, name, public) values ('store-assets', 'store-assets', true);
create policy "user_upload" on storage.objects for insert with check (bucket_id = 'store-assets' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "public_read" on storage.objects for select using (bucket_id = 'store-assets');
```

3. Salin URL dan anon key dari Project Settings → API, lalu isi di:
   `lib/core/supabase/supabase_config.dart`

```dart
class SupabaseConfig {
  static const String url = 'https://YOUR_PROJECT.supabase.co';
  static const String anonKey = 'YOUR_ANON_KEY';
}
```

### Install & Jalankan

```bash
flutter pub get
flutter run
```

---

## Build & Rilis

```bash
export JAVA_HOME=~/Android/jdk-17 ANDROID_HOME=~/Android/Sdk PATH=~/flutter-3.44/bin:~/Android/jdk-17/bin:$PATH
flutter test
flutter build apk --release        # APK untuk dibagikan langsung
flutter build appbundle --release  # AAB untuk Play Store
```

Signing release memakai `android/key.properties` + keystore (`*.jks`) — keduanya **di-ignore git, jangan pernah di-commit**. Simpan cadangan keystore + password di tempat aman: tanpa itu kamu tidak bisa merilis update.

### Urutan rilis versi baru
1. Jalankan migration baru di `supabase/migrations/` (SQL Editor) — semua migration dibuat kompatibel dengan APK lama.
2. Naikkan `version:` di `pubspec.yaml` (angka setelah `+` = build number, wajib selalu naik).
3. `flutter test`, build AAB, upload ke Play Console.
4. Setelah versi **live** di Play Store: admin-panel → *Versi Aplikasi* → isi build terbaru (popup update muncul di HP lama). Naikkan *build minimum* hanya kalau versi lama benar-benar harus berhenti dipakai.

### ⚠️ Pertama kali upload ke Play Store
Saat mendaftar **Play App Signing**, pilih **pakai kunci signing sendiri** (upload keystore `posin-release.jks` lewat PEPK), **bukan** kunci buatan Google. Kalau memakai kunci Google, pengguna lama yang memasang APK langsung **tidak bisa update dari Play Store** (tanda tangan beda) dan harus uninstall — data lokal yang belum tersinkron bisa hilang.

---

## Arsitektur

### Offline-First
Setiap operasi langsung disimpan ke SQLite lokal **bersama** entri antrean `sync_queue` dalam satu transaksi. `SyncController` (`lib/core/sync/`) mengirim antrean lewat RPC `push_changes` (atomik, idempoten) lalu menarik perubahan lewat `pull_changes` (kursor `updated_at,id`, paginasi, termasuk tombstone hapus). Pemicu: perubahan lokal, Supabase Realtime, app dibuka lagi, dan cadangan tiap 5 menit; retry dengan backoff saat offline. Detail desain & aturan server ada di `supabase/migrations/20261125000002_sync_foundation.sql`, tesnya di `supabase/tests/` dan `test/`.

### Isolasi Data Per User
- SQLite menggunakan file database terpisah per user: `posin_<userId>.db`
- Supabase menggunakan Row Level Security (RLS): setiap query otomatis difilter oleh `auth.uid() = user_id`
- Saat user berganti (login/logout), semua providers di-`invalidate` via `ref.listen(supabaseAuthProvider, ...)` di `_AppShell`

### State Management
- `AsyncNotifierProvider` untuk data async (orders, products, categories, settings)
- `NotifierProvider` untuk cart (sinkron)
- `StateProvider` untuk UI state (tab index, filter kategori, range laporan)
- Provider family untuk data per-produk (variant groups)

---

## Catatan Keamanan

- Jangan commit `supabase_config.dart` dengan kredensial production ke repositori publik
- Gunakan environment variable atau secret management untuk production
- Anon key Supabase aman untuk di-bundle di mobile app (diproteksi RLS)

---

## Kontribusi

1. Fork repository
2. Buat branch: `git checkout -b feat/nama-fitur`
3. Commit dengan pesan yang jelas
4. Buat Pull Request
