'use client';

import { useEffect, useState } from 'react';

/**
 * Atur popup update di app:
 * - Versi terbaru  : HP dengan build lebih lama melihat popup "Versi baru tersedia" (bisa ditunda).
 * - Versi minimum  : HP dengan build di bawah ini WAJIB update sebelum bisa memakai app.
 * Naikkan "versi terbaru" HANYA setelah versi itu sudah live di Play Store.
 */
export default function AppVersionCard({ token, onMessage }) {
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!token) return;
    fetch('/api/app-config', { headers: { 'x-admin-token': token } })
      .then((r) => r.json())
      .then((d) => {
        const c = d.config || {};
        setForm({
          latestVersionCode: c.latest_version_code ?? 1,
          latestVersionName: c.latest_version_name ?? '',
          minVersionCode: c.min_version_code ?? 1,
          releaseNotes: c.release_notes ?? '',
        });
      })
      .catch(() => setForm({ latestVersionCode: 1, latestVersionName: '', minVersionCode: 1, releaseNotes: '' }));
  }, [token]);

  const save = async () => {
    if (Number(form.minVersionCode) > 1 &&
        !confirm(`HP dengan build di bawah ${form.minVersionCode} TIDAK BISA memakai app sampai update. Lanjutkan?`)) {
      return;
    }
    setSaving(true);
    try {
      const res = await fetch('/api/app-config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-admin-token': token },
        body: JSON.stringify(form),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      onMessage?.({ type: 'success', text: 'Info versi aplikasi disimpan' });
    } catch (err) {
      onMessage?.({ type: 'error', text: err.message });
    } finally {
      setSaving(false);
    }
  };

  if (!form) return null;
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });
  const input = 'w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-sm text-white focus:outline-none focus:border-blue-500';
  const label = 'block text-xs font-semibold text-slate-400 uppercase tracking-wider mb-1';

  return (
    <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 mb-8">
      <div className="flex items-start justify-between gap-4 mb-4">
        <div>
          <h2 className="text-white font-bold">Versi Aplikasi (Popup Update)</h2>
          <p className="text-xs text-slate-400 mt-1">
            Naikkan &quot;versi terbaru&quot; hanya setelah versi tersebut sudah <b>live di Play Store</b>.
            Build number = angka setelah &quot;+&quot; di pubspec.yaml (mis. 1.2.0+6 → 6).
          </p>
        </div>
        <button
          onClick={save}
          disabled={saving}
          className="shrink-0 bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white text-sm font-semibold px-4 py-2 rounded-xl"
        >
          {saving ? 'Menyimpan...' : 'Simpan'}
        </button>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <label className={label}>Build terbaru</label>
          <input type="number" min="1" className={input} value={form.latestVersionCode} onChange={set('latestVersionCode')} />
        </div>
        <div>
          <label className={label}>Nama versi terbaru</label>
          <input className={input} placeholder="1.2.0" value={form.latestVersionName} onChange={set('latestVersionName')} />
        </div>
        <div>
          <label className={label}>Build minimum (wajib update)</label>
          <input type="number" min="1" className={input} value={form.minVersionCode} onChange={set('minVersionCode')} />
        </div>
        <div className="md:col-span-3">
          <label className={label}>Catatan rilis (tampil di popup)</label>
          <textarea rows={2} className={input} placeholder="Sinkron antar HP lebih cepat, diskon & pajak, ..." value={form.releaseNotes} onChange={set('releaseNotes')} />
        </div>
      </div>
    </div>
  );
}
