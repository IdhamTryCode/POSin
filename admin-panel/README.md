# POSin Admin Panel (Backoffice)

Web Admin Panel modern berbasis Next.js 14 untuk mengelola data user, langganan Premium, perpanjangan masa trial, dan konfigurasi database Supabase POSin.

---

## Fitur Utama

- 🔐 **Admin Authentication:** Proteksi login berbasis password/PIN admin.
- 📊 **Statistik Real-time:** Menampilkan total user, user premium aktif, trial aktif, user kedaluwarsa, dan user diblokir.
- 👥 **User Management:**
  - Cari user berdasarkan email atau User ID.
  - Lihat jumlah kategori, produk, dan transaksi tiap user.
  - Ganti tipe plan (**FREE TRIAL** ↔ **PREMIUM**).
  - Tambah masa aktif cepat (+1 Bulan, +3 Bulan, +6 Bulan, +1 Tahun).
  - Pilih tanggal kedaluwarsa kustom.
  - **Set Expired Sekarang** (langsung kunci akses aplikasi user).
  - **Ban / Unban User** (menonaktifkan akun dari login).
- ⚡ **Aman:** Kunci rahasia `SUPABASE_SERVICE_ROLE_KEY` hanya berjalan di server (Next.js API route), tidak pernah terekspos ke browser.

---

## Cara Deploy ke Vercel (Gratis & Mudah)

1. **Buka [Vercel](https://vercel.com) & Login dengan akun GitHub.**
2. Klik **Add New...** > **Project**.
3. Pilih repositori **`POSin`** dari GitHub kamu.
4. Pada bagian **Root Directory**, klik **Edit** dan pilih folder:
   👉 **`admin-panel`**
5. Buka bagian **Environment Variables** dan tambahkan 3 variabel berikut:

| Name | Value |
|---|---|
| `SUPABASE_URL` | `https://zjsuaniatdjroklgxyuy.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | `sb_secret_...` *(Secret key Supabase kamu)* |
| `ADMIN_PASSWORD` | *(Password bebas pilihanmu untuk login ke admin web)* |

6. Klik tombol **Deploy**! 🚀
7. Dalam ~1 menit web admin panel kamu sudah live di URL Vercel (misal: `posin-admin.vercel.app`).

---

## Cara Menjalankan Lokal

```bash
cd admin-panel
npm install
npm run dev
```
Buka [http://localhost:3000](http://localhost:3000) di browser.
