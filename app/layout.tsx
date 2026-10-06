import type { Metadata } from "next";
import "./globals.css";
import "./final.css";

export const metadata: Metadata = {
  title: "IPL Mega Auction | Auction Room",
  description: "Build your dream IPL squad. Compete with your friends.",
  other: {
    "codex-preview": "development",
  },
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}<footer className="site-footer">Made with <span aria-label="love">❤️</span> by Rishi Varma</footer></body>
    </html>
  );
}
