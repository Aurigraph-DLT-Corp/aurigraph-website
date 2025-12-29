import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Aurigraph | Next-Generation Blockchain Platform',
  description: 'Aurigraph DLT: 2M+ TPS blockchain with quantum-resistant cryptography, real-world asset tokenization, and enterprise DAO governance.',
  keywords: ['blockchain', 'DLT', 'cryptocurrency', 'quantum-resistant', 'tokenization'],
  viewport: 'width=device-width, initial-scale=1',
  authors: [{ name: 'Aurigraph Team' }],
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="theme-color" content="#000000" />
      </head>
      <body>
        <div id="root">{children}</div>
      </body>
    </html>
  );
}
