'use client';

import { useState, useEffect } from 'react';
import {
  Users,
  Shield,
  Clock,
  CheckCircle,
  AlertTriangle,
  Ban,
  Search,
  RefreshCw,
  LogOut,
  Calendar,
  Sparkles,
  ShoppingBag,
  Layers,
  Receipt,
  UserX,
  X,
  Lock,
} from 'lucide-react';

export default function AdminPage() {
  const [token, setToken] = useState('');
  const [passwordInput, setPasswordInput] = useState('');
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [loading, setLoading] = useState(false);
  const [users, setUsers] = useState([]);
  const [summary, setSummary] = useState(null);
  const [search, setSearch] = useState('');
  const [filterPlan, setFilterPlan] = useState('all');
  const [selectedUser, setSelectedUser] = useState(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);
  const [message, setMessage] = useState(null);

  // Form edit user
  const [editPlan, setEditPlan] = useState('premium');
  const [editDate, setEditDate] = useState('');

  useEffect(() => {
    const savedToken = localStorage.getItem('posin_admin_token');
    if (savedToken) {
      setToken(savedToken);
      setIsLoggedIn(true);
      fetchUsers(savedToken);
    }
  }, []);

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    setMessage(null);
    try {
      const res = await fetch('/api/auth', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: passwordInput }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Password salah');

      localStorage.setItem('posin_admin_token', data.token);
      setToken(data.token);
      setIsLoggedIn(true);
      fetchUsers(data.token);
    } catch (err) {
      setMessage({ type: 'error', text: err.message });
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = () => {
    localStorage.removeItem('posin_admin_token');
    setToken('');
    setIsLoggedIn(false);
    setUsers([]);
  };

  const fetchUsers = async (authToken = token) => {
    setLoading(true);
    try {
      const res = await fetch('/api/users', {
        headers: { 'x-admin-token': authToken },
      });
      const data = await res.json();
      if (!res.ok) {
        if (res.status === 401) handleLogout();
        throw new Error(data.error || 'Gagal memuat user');
      }
      setUsers(data.users || []);
      setSummary(data.summary);
    } catch (err) {
      setMessage({ type: 'error', text: err.message });
    } finally {
      setLoading(false);
    }
  };

  const openEditModal = (u) => {
    setSelectedUser(u);
    setEditPlan(u.planType || 'premium');
    if (u.trialExpiresAt) {
      const d = new Date(u.trialExpiresAt);
      setEditDate(d.toISOString().slice(0, 16));
    } else {
      const d = new Date();
      d.setFullYear(d.getFullYear() + 1);
      setEditDate(d.toISOString().slice(0, 16));
    }
    setModalOpen(true);
  };

  const handleQuickAdd = (months) => {
    const base = new Date();
    base.setMonth(base.getMonth() + months);
    setEditDate(base.toISOString().slice(0, 16));
  };

  const handleSavePlan = async () => {
    if (!selectedUser || !editDate) return;
    setActionLoading(true);
    try {
      const expiresIso = new Date(editDate).toISOString();
      const res = await fetch('/api/users/update', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-admin-token': token,
        },
        body: JSON.stringify({
          action: 'update_plan',
          userId: selectedUser.id,
          planType: editPlan,
          expiresAt: expiresIso,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);

      setMessage({ type: 'success', text: `Status ${selectedUser.email} berhasil diupdate ke ${editPlan.toUpperCase()}!` });
      setModalOpen(false);
      fetchUsers();
    } catch (err) {
      setMessage({ type: 'error', text: err.message });
    } finally {
      setActionLoading(false);
    }
  };

  const handleToggleBan = async (banStatus) => {
    if (!selectedUser) return;
    const actionText = banStatus ? 'menonaktifkan (ban)' : 'mengaktifkan kembali';
    if (!confirm(`Yakin ingin ${actionText} user ${selectedUser.email}?`)) return;

    setActionLoading(true);
    try {
      const res = await fetch('/api/users/update', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-admin-token': token,
        },
        body: JSON.stringify({
          action: 'toggle_ban',
          userId: selectedUser.id,
          ban: banStatus,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);

      setMessage({
        type: 'success',
        text: `User ${selectedUser.email} berhasil ${banStatus ? 'dinonaktifkan' : 'diaktifkan kembali'}!`,
      });
      setModalOpen(false);
      fetchUsers();
    } catch (err) {
      setMessage({ type: 'error', text: err.message });
    } finally {
      setActionLoading(false);
    }
  };

  const handleExpireNow = () => {
    const past = new Date();
    past.setDate(past.getDate() - 1);
    setEditDate(past.toISOString().slice(0, 16));
    setEditPlan('free');
  };

  // Filter users
  const filteredUsers = users.filter((u) => {
    const matchSearch = u.email?.toLowerCase().includes(search.toLowerCase()) || u.id.includes(search);
    if (!matchSearch) return false;
    if (filterPlan === 'premium') return u.planType === 'premium' && !u.isExpired;
    if (filterPlan === 'free') return u.planType === 'free' && !u.isExpired;
    if (filterPlan === 'expired') return u.isExpired;
    if (filterPlan === 'banned') return u.banned;
    return true;
  });

  const formatDate = (dateStr) => {
    if (!dateStr) return '-';
    const d = new Date(dateStr);
    return d.toLocaleDateString('id-ID', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  if (!isLoggedIn) {
    return (
      <div className="min-h-screen flex items-center justify-center p-4 bg-slate-950">
        <div className="max-w-md w-full bg-slate-900 border border-slate-800 rounded-2xl p-8 shadow-2xl">
          <div className="flex justify-center mb-6">
            <div className="w-16 h-16 bg-blue-600/20 text-blue-500 rounded-2xl flex items-center justify-center border border-blue-500/30">
              <Shield className="w-8 h-8" />
            </div>
          </div>
          <h1 className="text-2xl font-bold text-center text-white mb-2">POSin Admin Panel</h1>
          <p className="text-slate-400 text-sm text-center mb-6">
            Masukkan password administrator untuk mengelola database Supabase.
          </p>

          {message && (
            <div className="mb-4 p-3 bg-red-500/10 border border-red-500/30 text-red-400 text-sm rounded-xl">
              {message.text}
            </div>
          )}

          <form onSubmit={handleLogin} className="space-y-4">
            <div>
              <label className="block text-xs font-semibold text-slate-300 uppercase tracking-wider mb-2">
                Password Admin
              </label>
              <div className="relative">
                <Lock className="w-5 h-5 text-slate-500 absolute left-3 top-3.5" />
                <input
                  type="password"
                  value={passwordInput}
                  onChange={(e) => setPasswordInput(e.target.value)}
                  placeholder="Masukkan password..."
                  required
                  className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl pl-10 pr-4 py-3 focus:outline-none focus:border-blue-500 transition"
                />
              </div>
            </div>
            <button
              type="submit"
              disabled={loading}
              className="w-full bg-blue-600 hover:bg-blue-500 text-white font-semibold py-3 rounded-xl transition duration-200 shadow-lg shadow-blue-600/20 disabled:opacity-50"
            >
              {loading ? 'Memeriksa...' : 'Masuk ke Admin Panel'}
            </button>
          </form>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      {/* Header */}
      <header className="border-b border-slate-800/80 bg-slate-900/60 backdrop-blur sticky top-0 z-20">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 bg-blue-600/20 text-blue-500 rounded-xl flex items-center justify-center border border-blue-500/30">
              <Shield className="w-5 h-5" />
            </div>
            <div>
              <h1 className="font-bold text-lg text-white">POSin Admin</h1>
              <p className="text-xs text-slate-400">Database & Subscription Manager</p>
            </div>
          </div>
          <div className="flex items-center space-x-3">
            <button
              onClick={() => fetchUsers()}
              disabled={loading}
              className="p-2 text-slate-400 hover:text-white bg-slate-800/60 hover:bg-slate-800 rounded-xl transition border border-slate-700/50"
              title="Refresh Data"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-blue-400' : ''}`} />
            </button>
            <button
              onClick={handleLogout}
              className="flex items-center space-x-2 px-3 py-2 text-sm text-red-400 hover:bg-red-500/10 rounded-xl transition border border-red-500/20"
            >
              <LogOut className="w-4 h-4" />
              <span>Keluar</span>
            </button>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Toast Alert */}
        {message && (
          <div
            className={`mb-6 p-4 rounded-xl border flex items-center justify-between ${
              message.type === 'success'
                ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-300'
                : 'bg-red-500/10 border-red-500/30 text-red-300'
            }`}
          >
            <div className="flex items-center space-x-2">
              {message.type === 'success' ? <CheckCircle className="w-5 h-5" /> : <AlertTriangle className="w-5 h-5" />}
              <span>{message.text}</span>
            </div>
            <button onClick={() => setMessage(null)} className="text-slate-400 hover:text-white">
              <X className="w-4 h-4" />
            </button>
          </div>
        )}

        {/* Stats Grid */}
        {summary && (
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-8">
            <div className="bg-slate-900/80 border border-slate-800/80 p-4 rounded-2xl">
              <div className="flex items-center justify-between text-slate-400 text-xs font-medium mb-1">
                <span>Total Pengguna</span>
                <Users className="w-4 h-4 text-blue-400" />
              </div>
              <p className="text-2xl font-bold text-white">{summary.total}</p>
            </div>

            <div className="bg-slate-900/80 border border-slate-800/80 p-4 rounded-2xl">
              <div className="flex items-center justify-between text-amber-400 text-xs font-medium mb-1">
                <span>Premium Aktif</span>
                <Sparkles className="w-4 h-4 text-amber-400" />
              </div>
              <p className="text-2xl font-bold text-amber-300">{summary.premium}</p>
            </div>

            <div className="bg-slate-900/80 border border-slate-800/80 p-4 rounded-2xl">
              <div className="flex items-center justify-between text-blue-400 text-xs font-medium mb-1">
                <span>Free Trial Aktif</span>
                <Clock className="w-4 h-4 text-blue-400" />
              </div>
              <p className="text-2xl font-bold text-blue-300">{summary.freeActive}</p>
            </div>

            <div className="bg-slate-900/80 border border-slate-800/80 p-4 rounded-2xl">
              <div className="flex items-center justify-between text-rose-400 text-xs font-medium mb-1">
                <span>Trial Habis (Expired)</span>
                <AlertTriangle className="w-4 h-4 text-rose-400" />
              </div>
              <p className="text-2xl font-bold text-rose-300">{summary.expired}</p>
            </div>

            <div className="bg-slate-900/80 border border-slate-800/80 p-4 rounded-2xl">
              <div className="flex items-center justify-between text-red-400 text-xs font-medium mb-1">
                <span>Diblokir (Banned)</span>
                <Ban className="w-4 h-4 text-red-400" />
              </div>
              <p className="text-2xl font-bold text-red-400">{summary.banned}</p>
            </div>
          </div>
        )}

        {/* Filters & Search */}
        <div className="bg-slate-900/60 border border-slate-800/80 p-4 rounded-2xl mb-6 flex flex-col md:flex-row items-center justify-between gap-4">
          <div className="relative w-full md:w-80">
            <Search className="w-4 h-4 text-slate-500 absolute left-3 top-3" />
            <input
              type="text"
              placeholder="Cari email atau User ID..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl pl-9 pr-4 py-2 text-sm focus:outline-none focus:border-blue-500 transition"
            />
          </div>

          <div className="flex items-center space-x-2 w-full md:w-auto overflow-x-auto">
            {[
              { id: 'all', label: 'Semua User' },
              { id: 'premium', label: '⭐ Premium' },
              { id: 'free', label: '⏳ Free Trial' },
              { id: 'expired', label: '❌ Expired' },
              { id: 'banned', label: '🚫 Banned' },
            ].map((f) => (
              <button
                key={f.id}
                onClick={() => setFilterPlan(f.id)}
                className={`px-3 py-1.5 text-xs font-medium rounded-xl whitespace-nowrap transition border ${
                  filterPlan === f.id
                    ? 'bg-blue-600 text-white border-blue-500 shadow-sm'
                    : 'bg-slate-950 text-slate-400 border-slate-800 hover:text-white'
                }`}
              >
                {f.label}
              </button>
            ))}
          </div>
        </div>

        {/* User Table */}
        <div className="bg-slate-900/80 border border-slate-800/80 rounded-2xl overflow-hidden shadow-xl">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="bg-slate-950 text-slate-400 text-xs uppercase tracking-wider border-b border-slate-800">
                <tr>
                  <th className="px-6 py-4">User</th>
                  <th className="px-6 py-4">Status Plan</th>
                  <th className="px-6 py-4">Masa Berlaku</th>
                  <th className="px-6 py-4">Data Toko</th>
                  <th className="px-6 py-4 text-right">Aksi</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60">
                {filteredUsers.length === 0 ? (
                  <tr>
                    <td colSpan="5" className="px-6 py-12 text-center text-slate-500">
                      {loading ? 'Memuat data pengguna...' : 'Tidak ada user yang cocok dengan filter.'}
                    </td>
                  </tr>
                ) : (
                  filteredUsers.map((u) => {
                    const isPrem = u.planType === 'premium';
                    const isExp = u.isExpired;

                    return (
                      <tr key={u.id} className="hover:bg-slate-800/30 transition">
                        <td className="px-6 py-4">
                          <div className="font-semibold text-white flex items-center space-x-2">
                            <span>{u.email}</span>
                            {u.banned && (
                              <span className="bg-red-500/20 text-red-400 border border-red-500/30 text-[10px] px-2 py-0.5 rounded-full font-bold">
                                BANNED
                              </span>
                            )}
                          </div>
                          <div className="text-xs text-slate-500 font-mono mt-0.5 truncate max-w-xs">{u.id}</div>
                        </td>

                        <td className="px-6 py-4">
                          {isPrem ? (
                            <span
                              className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-semibold ${
                                isExp
                                  ? 'bg-rose-500/10 text-rose-400 border border-rose-500/20'
                                  : 'bg-amber-500/10 text-amber-300 border border-amber-500/30'
                              }`}
                            >
                              ⭐ PREMIUM {isExp ? '(EXPIRED)' : ''}
                            </span>
                          ) : (
                            <span
                              className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-semibold ${
                                isExp
                                  ? 'bg-rose-500/10 text-rose-400 border border-rose-500/20'
                                  : 'bg-blue-500/10 text-blue-400 border border-blue-500/30'
                              }`}
                            >
                              ⏳ FREE TRIAL {isExp ? '(EXPIRED)' : ''}
                            </span>
                          )}
                        </td>

                        <td className="px-6 py-4">
                          <div className="text-slate-300 text-xs">{formatDate(u.trialExpiresAt)}</div>
                          <div className="text-[11px] text-slate-500 mt-0.5">
                            {isExp ? (
                              <span className="text-rose-400 font-medium">Masa aktif sudah habis</span>
                            ) : (
                              <span className="text-emerald-400">Aktif</span>
                            )}
                          </div>
                        </td>

                        <td className="px-6 py-4">
                          <div className="flex items-center space-x-3 text-xs text-slate-400">
                            <span className="flex items-center space-x-1" title="Kategori">
                              <Layers className="w-3.5 h-3.5 text-blue-400" />
                              <span>{u.counts?.categories || 0}</span>
                            </span>
                            <span className="flex items-center space-x-1" title="Produk">
                              <ShoppingBag className="w-3.5 h-3.5 text-emerald-400" />
                              <span>{u.counts?.products || 0}</span>
                            </span>
                            <span className="flex items-center space-x-1" title="Order">
                              <Receipt className="w-3.5 h-3.5 text-amber-400" />
                              <span>{u.counts?.orders || 0}</span>
                            </span>
                          </div>
                        </td>

                        <td className="px-6 py-4 text-right">
                          <button
                            onClick={() => openEditModal(u)}
                            className="bg-blue-600/20 hover:bg-blue-600 text-blue-400 hover:text-white border border-blue-500/30 px-3 py-1.5 rounded-xl text-xs font-medium transition shadow-sm"
                          >
                            Kelola Plan
                          </button>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      </main>

      {/* Modal Kelola User */}
      {modalOpen && selectedUser && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-lg w-full p-6 shadow-2xl relative">
            <button
              onClick={() => setModalOpen(false)}
              className="absolute right-4 top-4 text-slate-400 hover:text-white"
            >
              <X className="w-5 h-5" />
            </button>

            <h2 className="text-xl font-bold text-white mb-1">Kelola Langganan User</h2>
            <p className="text-sm text-slate-400 mb-6 font-mono text-xs truncate">{selectedUser.email}</p>

            <div className="space-y-5">
              {/* Pilihan Plan */}
              <div>
                <label className="block text-xs font-semibold text-slate-400 uppercase tracking-wider mb-2">
                  Tipe Plan
                </label>
                <div className="grid grid-cols-2 gap-3">
                  <button
                    type="button"
                    onClick={() => setEditPlan('premium')}
                    className={`py-3 px-4 rounded-xl border text-sm font-semibold flex items-center justify-center space-x-2 transition ${
                      editPlan === 'premium'
                        ? 'bg-amber-500/20 border-amber-500 text-amber-300'
                        : 'bg-slate-950 border-slate-800 text-slate-400 hover:text-white'
                    }`}
                  >
                    <Sparkles className="w-4 h-4 text-amber-400" />
                    <span>PREMIUM</span>
                  </button>

                  <button
                    type="button"
                    onClick={() => setEditPlan('free')}
                    className={`py-3 px-4 rounded-xl border text-sm font-semibold flex items-center justify-center space-x-2 transition ${
                      editPlan === 'free'
                        ? 'bg-blue-500/20 border-blue-500 text-blue-300'
                        : 'bg-slate-950 border-slate-800 text-slate-400 hover:text-white'
                    }`}
                  >
                    <Clock className="w-4 h-4 text-blue-400" />
                    <span>FREE TRIAL</span>
                  </button>
                </div>
              </div>

              {/* Tambah Durasi Cepat */}
              <div>
                <label className="block text-xs font-semibold text-slate-400 uppercase tracking-wider mb-2">
                  Tambah Masa Aktif Cepat
                </label>
                <div className="grid grid-cols-4 gap-2">
                  {[
                    { label: '+1 Bulan', months: 1 },
                    { label: '+3 Bulan', months: 3 },
                    { label: '+6 Bulan', months: 6 },
                    { label: '+1 Tahun', months: 12 },
                  ].map((item) => (
                    <button
                      key={item.label}
                      type="button"
                      onClick={() => handleQuickAdd(item.months)}
                      className="bg-slate-950 hover:bg-slate-800 border border-slate-800 text-slate-300 text-xs py-2 rounded-xl font-medium transition"
                    >
                      {item.label}
                    </button>
                  ))}
                </div>
              </div>

              {/* Input Tanggal Expire */}
              <div>
                <label className="block text-xs font-semibold text-slate-400 uppercase tracking-wider mb-2">
                  Berlaku Sampai Tanggal
                </label>
                <div className="relative">
                  <Calendar className="w-4 h-4 text-slate-500 absolute left-3 top-3.5" />
                  <input
                    type="datetime-local"
                    value={editDate}
                    onChange={(e) => setEditDate(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl pl-10 pr-4 py-2.5 text-sm focus:outline-none focus:border-blue-500 transition"
                  />
                </div>
              </div>

              {/* Tombol Simpan */}
              <div className="pt-2">
                <button
                  type="button"
                  onClick={handleSavePlan}
                  disabled={actionLoading}
                  className="w-full bg-blue-600 hover:bg-blue-500 text-white font-semibold py-3 rounded-xl transition duration-200 shadow-lg shadow-blue-600/20 disabled:opacity-50"
                >
                  {actionLoading ? 'Menyimpan...' : 'Simpan Perubahan Plan'}
                </button>
              </div>

              {/* Quick Actions (Nonaktifkan & Ban) */}
              <div className="pt-4 border-t border-slate-800/80 flex items-center justify-between gap-3">
                <button
                  type="button"
                  onClick={handleExpireNow}
                  className="flex-1 py-2 px-3 text-xs font-medium text-rose-400 hover:bg-rose-500/10 border border-rose-500/20 rounded-xl transition text-center"
                >
                  Set Expired Sekarang
                </button>

                <button
                  type="button"
                  onClick={() => handleToggleBan(!selectedUser.banned)}
                  className={`flex-1 py-2 px-3 text-xs font-medium rounded-xl transition text-center border ${
                    selectedUser.banned
                      ? 'text-emerald-400 hover:bg-emerald-500/10 border-emerald-500/30'
                      : 'text-red-400 hover:bg-red-500/10 border-red-500/30'
                  }`}
                >
                  {selectedUser.banned ? 'Buka Blokir (Unban)' : 'Nonaktifkan Akun (Ban)'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
