'use client';

import { useState } from 'react';

interface FormData {
  name: string;
  email: string;
  company: string;
  useCase: string;
  message: string;
}

export default function ContactForm() {
  const [formData, setFormData] = useState<FormData>({
    name: '',
    email: '',
    company: '',
    useCase: '',
    message: '',
  });

  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>
  ) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value,
    }));
  };

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      // Send to database API
      const response = await fetch('/api/contact', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: formData.name,
          email: formData.email,
          company: formData.company,
          useCase: formData.useCase,
          message: formData.message,
        }),
      });

      if (!response.ok) {
        const data = await response.json();
        throw new Error(data.error || 'Failed to submit form');
      }

      const data = await response.json();

      if (data.success) {
        setSubmitted(true);
        setFormData({
          name: '',
          email: '',
          company: '',
          useCase: '',
          message: '',
        });

        // Reset success message after 5 seconds
        setTimeout(() => {
          setSubmitted(false);
        }, 5000);
      }
    } catch (err) {
      setError(
        err instanceof Error ? err.message : 'Failed to send message. Please try again.'
      );
      console.error('Form submission error:', err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="max-w-2xl mx-auto space-y-6">
      {/* Success Message */}
      {submitted && (
        <div className="p-4 bg-green-50 border border-green-200 rounded-lg">
          <p className="text-green-800 font-medium">
            ✅ Message sent successfully! We'll get back to you soon.
          </p>
        </div>
      )}

      {/* Error Message */}
      {error && (
        <div className="p-4 bg-red-50 border border-red-200 rounded-lg">
          <p className="text-red-800 font-medium">❌ {error}</p>
        </div>
      )}

      {/* Name Field */}
      <div>
        <label htmlFor="name" className="block text-sm font-medium text-gray-700 mb-2">
          Full Name *
        </label>
        <input
          type="text"
          id="name"
          name="name"
          value={formData.name}
          onChange={handleChange}
          required
          placeholder="John Doe"
          className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition"
        />
      </div>

      {/* Email Field */}
      <div>
        <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-2">
          Email Address *
        </label>
        <input
          type="email"
          id="email"
          name="email"
          value={formData.email}
          onChange={handleChange}
          required
          placeholder="john@example.com"
          className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition"
        />
      </div>

      {/* Company Field */}
      <div>
        <label htmlFor="company" className="block text-sm font-medium text-gray-700 mb-2">
          Company
        </label>
        <input
          type="text"
          id="company"
          name="company"
          value={formData.company}
          onChange={handleChange}
          placeholder="Your Company"
          className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition"
        />
      </div>

      {/* Use Case Field */}
      <div>
        <label htmlFor="useCase" className="block text-sm font-medium text-gray-700 mb-2">
          Use Case
        </label>
        <select
          id="useCase"
          name="useCase"
          value={formData.useCase}
          onChange={handleChange}
          className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition"
        >
          <option value="">Select a use case...</option>
          <option value="enterprise">Enterprise Integration</option>
          <option value="rwat">Real-World Asset Tokenization</option>
          <option value="governance">DAO Governance</option>
          <option value="blockchain">Blockchain Development</option>
          <option value="partnership">Partnership Inquiry</option>
          <option value="other">Other</option>
        </select>
      </div>

      {/* Message Field */}
      <div>
        <label htmlFor="message" className="block text-sm font-medium text-gray-700 mb-2">
          Message *
        </label>
        <textarea
          id="message"
          name="message"
          value={formData.message}
          onChange={handleChange}
          required
          placeholder="Tell us more about your inquiry..."
          rows={6}
          className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition resize-none"
        />
      </div>

      {/* Submit Button */}
      <div className="flex gap-4">
        <button
          type="submit"
          disabled={loading}
          className={`flex-1 px-6 py-3 bg-blue-600 text-white font-semibold rounded-lg transition ${
            loading
              ? 'opacity-50 cursor-not-allowed'
              : 'hover:bg-blue-700 active:bg-blue-800'
          }`}
        >
          {loading ? 'Sending...' : 'Send Message'}
        </button>
        <button
          type="reset"
          onClick={() => {
            setFormData({
              name: '',
              email: '',
              company: '',
              useCase: '',
              message: '',
            });
            setError('');
          }}
          className="px-6 py-3 bg-gray-200 text-gray-800 font-semibold rounded-lg hover:bg-gray-300 transition"
        >
          Clear
        </button>
      </div>

      {/* Privacy Notice */}
      <p className="text-xs text-gray-500 text-center">
        Your information will be kept confidential and used only to respond to your inquiry.
        See our <a href="/privacy" className="text-blue-600 hover:underline">Privacy Policy</a> for more details.
      </p>
    </form>
  );
}
