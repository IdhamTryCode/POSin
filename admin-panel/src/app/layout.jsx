import './globals.css';

export const metadata = {
  title: 'POSin Admin Panel',
  description: 'Admin backoffice for POSin POS system',
};

export default function RootLayout({ children }) {
  return (
    <html lang="id">
      <body className="min-h-screen bg-slate-950 text-slate-100 antialiased">
        {children}
      </body>
    </html>
  );
}
