import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono, Lora } from "next/font/google";
import { headers } from "next/headers";
import "./globals.css";

const geist = Geist({
  variable: "--font-ui",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-mono",
  subsets: ["latin"],
});

const lora = Lora({
  variable: "--font-reading",
  subsets: ["latin"],
});

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host =
    requestHeaders.get("x-forwarded-host") ||
    requestHeaders.get("host") ||
    "localhost:3000";
  const protocol =
    requestHeaders.get("x-forwarded-proto") ||
    (host.includes("localhost") ? "http" : "https");
  const base = new URL(`${protocol}://${host}`);
  const socialImage = new URL("/og.png", base).toString();

  return {
    title: "Lume — leitor Markdown",
    description:
      "Um leitor Markdown local, rápido e bonito, com links wiki e zero distrações.",
    manifest: "/manifest.webmanifest",
    appleWebApp: {
      capable: true,
      title: "Lume",
    },
    icons: {
      apple: "/apple-touch-icon.png",
      icon: "/favicon.png",
      shortcut: "/favicon.png",
    },
    openGraph: {
      description:
        "Um leitor Markdown local, rápido e bonito, com links wiki e zero distrações.",
      images: [{ alt: "Lume — Markdown, só para ler.", url: socialImage }],
      title: "Lume — leitor Markdown",
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      description: "Leitor Markdown local, leve e com links wiki.",
      images: [socialImage],
      title: "Lume — Markdown, só para ler.",
    },
  };
}

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f4f1ea" },
    { media: "(prefers-color-scheme: dark)", color: "#171817" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="pt-BR" suppressHydrationWarning>
      <body className={`${geist.variable} ${geistMono.variable} ${lora.variable}`}>
        {children}
      </body>
    </html>
  );
}
