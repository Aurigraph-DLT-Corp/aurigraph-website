'use client';

import { ContactForm } from './components/ContactForm';

export default function Home() {
  return (
    <main className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
      {/* Header */}
      <header className="border-b border-slate-700 bg-slate-900/50 backdrop-blur">
        <div className="max-w-6xl mx-auto px-4 py-6 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-2">
              <div className="text-2xl font-bold text-white">◆</div>
              <h1 className="text-2xl font-bold text-white">Aurigraph</h1>
            </div>
            <nav className="hidden sm:flex space-x-8">
              <a href="#features" className="text-slate-300 hover:text-white transition">Features</a>
              <a href="#contact" className="text-slate-300 hover:text-white transition">Contact</a>
            </nav>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="max-w-6xl mx-auto px-4 py-20 sm:px-6 lg:px-8">
        <div className="text-center space-y-8">
          <h2 className="text-5xl sm:text-6xl font-bold text-white leading-tight">
            Next-Generation <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-cyan-400">Blockchain Platform</span>
          </h2>
          <p className="text-xl text-slate-300 max-w-2xl mx-auto">
            Aurigraph DLT: 2M+ TPS with quantum-resistant cryptography, real-world asset tokenization, and enterprise DAO governance.
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 max-w-3xl mx-auto mt-12">
            <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-6">
              <div className="text-3xl font-bold text-cyan-400">2M+</div>
              <p className="text-slate-400 mt-2">Transactions Per Second</p>
            </div>
            <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-6">
              <div className="text-3xl font-bold text-cyan-400">&lt;500ms</div>
              <p className="text-slate-400 mt-2">Block Finality</p>
            </div>
            <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-6">
              <div className="text-3xl font-bold text-cyan-400">NIST L5</div>
              <p className="text-slate-400 mt-2">Quantum Resistant</p>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section id="features" className="max-w-6xl mx-auto px-4 py-20 sm:px-6 lg:px-8">
        <h3 className="text-3xl font-bold text-white mb-12 text-center">Key Features</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          {[
            { title: 'Quantum-Resistant Cryptography', desc: 'NIST Level 5 security with CRYSTALS-Dilithium and Kyber' },
            { title: 'Real-World Asset Tokenization', desc: 'Tokenize and trade physical assets on-chain with Merkle trees' },
            { title: 'Enterprise DAO Governance', desc: 'Token-based voting with transparent governance contracts' },
            { title: 'Multi-Chain Bridges', desc: 'Cross-chain asset transfers with validator consensus' },
            { title: 'AI-Driven Optimization', desc: 'Machine learning for intelligent transaction ordering' },
            { title: 'High Throughput', desc: '2M+ TPS with &lt;500ms finality and 0.022 gCO₂/tx' },
          ].map((feature, idx) => (
            <div key={idx} className="bg-slate-800/50 border border-slate-700 rounded-lg p-6 hover:border-slate-600 transition">
              <h4 className="text-xl font-bold text-white mb-3">{feature.title}</h4>
              <p className="text-slate-400">{feature.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Contact Section */}
      <section id="contact" className="max-w-6xl mx-auto px-4 py-20 sm:px-6 lg:px-8">
        <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-8 sm:p-12">
          <h3 className="text-3xl font-bold text-white mb-8 text-center">Get In Touch</h3>
          <ContactForm />
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-slate-700 bg-slate-900/50 mt-20">
        <div className="max-w-6xl mx-auto px-4 py-12 sm:px-6 lg:px-8">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8 mb-8">
            <div>
              <h4 className="text-white font-bold mb-4">Aurigraph</h4>
              <p className="text-slate-400">Next-generation blockchain platform with quantum-resistant cryptography.</p>
            </div>
            <div>
              <h4 className="text-white font-bold mb-4">Links</h4>
              <ul className="space-y-2 text-slate-400">
                <li><a href="#" className="hover:text-white transition">Platform</a></li>
                <li><a href="#" className="hover:text-white transition">Documentation</a></li>
                <li><a href="#" className="hover:text-white transition">GitHub</a></li>
              </ul>
            </div>
            <div>
              <h4 className="text-white font-bold mb-4">Legal</h4>
              <ul className="space-y-2 text-slate-400">
                <li><a href="#" className="hover:text-white transition">Privacy Policy</a></li>
                <li><a href="#" className="hover:text-white transition">Terms of Service</a></li>
              </ul>
            </div>
          </div>
          <div className="border-t border-slate-700 pt-8">
            <p className="text-center text-slate-400">© 2025 Aurigraph. All rights reserved.</p>
          </div>
        </div>
      </footer>
    </main>
  );
}
