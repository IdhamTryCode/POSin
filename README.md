# POSin

POSin adalah aplikasi Point of Sale (POS) berbasis Flutter untuk membantu operasional kasir, manajemen menu/produk, laporan transaksi, dan pengaturan toko. Data utama tersimpan lokal (SQLite) dan bisa disinkronkan ke Supabase.

## Fitur Utama

- Kasir cepat dengan keranjang belanja, checkout, dan metode pembayaran.
- Manajemen kategori, produk, dan varian produk.
- Laporan transaksi harian, mingguan, dan bulanan.
- Pengaturan toko (nama toko, preferensi) dan proteksi PIN lokal.
- Integrasi Supabase untuk autentikasi, sinkronisasi data, dan storage gambar.
- Dukungan printer Bluetooth (ESC/POS) untuk struk.

## Tech Stack

- Flutter (Dart SDK `^3.7.0`)
- Riverpod (`flutter_riverpod`) untuk state management
- SQLite (`sqflite` + `sqflite_common_ffi`) untuk penyimpanan lokal
- Supabase (`supabase_flutter`) untuk auth + cloud sync
- `blue_thermal_printer` untuk printer Bluetooth
- `intl`, `shared_preferences`, `image_picker`, `fl_chart`, dan utilitas lain

## Struktur Folder (Ringkas)

```text
lib/
  core/
    constants/
    database/
    screens/
    supabase/
    theme/
  features/
    auth/
    categories/
    orders/
    printer/
    products/
    reports/
    settings/
  app.dart
  main.dart
assets/
  images/
```

## Prasyarat

- Flutter SDK terpasang dan bisa dijalankan dari terminal.
- Android SDK (jika build Android).
- Akun Supabase (untuk auth/sync/storage).

## Setup Project

1. Install dependency:

   ```bash
   flutter pub get
   ```

2. Pastikan konfigurasi Supabase sudah benar di file:
   - `lib/core/supabase/supabase_config.dart`

3. Jalankan aplikasi:

   ```bash
   flutter run
   ```

## Build

- APK release:

  ```bash
  flutter build apk --release
  ```

- Build platform lain sesuai target (`windows`, `linux`, `macos`, dll):

  ```bash
  flutter build windows
  ```

## Catatan Keamanan

- Jangan commit secret/key sensitif selain yang memang public.
- File runtime/build sudah diatur pada `.gitignore`.
- Jika ingin produksi, gunakan manajemen secret yang lebih aman (contoh: env/config terpisah per environment).

## Kontribusi

1. Buat branch baru.
2. Lakukan perubahan dan pengujian.
3. Commit dengan pesan yang jelas.
4. Ajukan pull request.
