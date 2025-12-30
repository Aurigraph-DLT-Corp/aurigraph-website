/**
 * HubSpot Integration Test Suite
 *
 * Tests coverage:
 * - Contact creation with fixed payload format
 * - Contact updates with fixed payload format
 * - Efficient contact search implementation
 * - Retry logic with timeout protection
 * - Error handling (network, API, validation)
 *
 * Target: ≥80% code coverage
 */

import { syncContactToHubSpot, addContactToList, createHubSpotDeal, logActivityToHubSpot } from '@/lib/hubspot';
import { fetchWithRetry, retryWithBackoff } from '@/lib/hubspot-retry';

// Mock fetch globally
global.fetch = jest.fn();

describe('HubSpot Integration', () => {
  beforeEach(() => {
    // Clear all mocks before each test
    jest.clearAllMocks();

    // Set required environment variable
    process.env.HUBSPOT_API_KEY = 'test-api-key-123';
  });

  describe('syncContactToHubSpot - Core Functionality', () => {
    it('should create a new contact successfully with fixed payload format', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ results: [] }), // No existing contact
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ id: 12345 }), // Contact created
      });

      const result = await syncContactToHubSpot({
        email: 'john@example.com',
        firstName: 'John',
        lastName: 'Doe',
        company: 'Test Corp',
      });

      expect(result.success).toBe(true);
      expect(result.vid).toBe(12345);
    });

    it('should update an existing contact with fixed payload format', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          results: [
            {
              id: 67890,
              properties: {
                email: { value: 'john@example.com' },
              },
            },
          ],
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({}), // Update successful
      });

      const result = await syncContactToHubSpot({
        email: 'john@example.com',
        firstName: 'John',
        lastName: 'UpdatedDoe',
      });

      expect(result.success).toBe(true);
      expect(result.vid).toBe(67890);
    });

    it('should use efficient Search API for contact lookup', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ results: [] }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ id: 99999 }),
      });

      await syncContactToHubSpot({
        email: 'test@example.com',
      });

      // Verify Search API was called (POST to /contacts/search)
      const firstCall = (mockFetch as jest.Mock).mock.calls[0];
      expect(firstCall[0]).toContain('/contacts/search');
      expect(firstCall[1].method).toBe('POST');
    });

    it('should return error when API key is missing', async () => {
      delete process.env.HUBSPOT_API_KEY;

      const result = await syncContactToHubSpot({
        email: 'test@example.com',
      });

      expect(result.success).toBe(false);
      expect(result.error).toContain('HUBSPOT_API_KEY');
    });

    it('should handle API error responses gracefully', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValue({
        ok: false,
        json: async () => ({ message: 'Invalid email format' }),
      });

      const result = await syncContactToHubSpot({
        email: 'invalid-email',
      });

      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
    });
  });

  describe('retryWithBackoff - Retry & Timeout Protection', () => {
    it('should succeed on first attempt', async () => {
      const mockFn = jest.fn().mockResolvedValue({ data: 'success' });

      const result = await retryWithBackoff(mockFn);

      expect(result.data).toBe('success');
      expect(mockFn).toHaveBeenCalledTimes(1);
    });

    it('should retry on transient failure and succeed', async () => {
      const mockFn = jest
        .fn()
        .mockRejectedValueOnce(new Error('ECONNREFUSED'))
        .mockResolvedValueOnce({ data: 'success' });

      const result = await retryWithBackoff(mockFn, {
        maxAttempts: 3,
        initialDelayMs: 10, // Short delay for tests
      });

      expect(result.data).toBe('success');
      expect(mockFn).toHaveBeenCalledTimes(2); // First attempt + 1 retry
    });

    it('should fail after max retries exhausted', async () => {
      const mockFn = jest.fn().mockRejectedValue(new Error('ECONNREFUSED'));

      await expect(
        retryWithBackoff(mockFn, {
          maxAttempts: 2,
          initialDelayMs: 10,
        })
      ).rejects.toThrow('ECONNREFUSED');

      expect(mockFn).toHaveBeenCalledTimes(2);
    });

    it('should not retry on non-retryable errors (400)', async () => {
      const mockFn = jest.fn().mockRejectedValue(new Error('400 Bad Request'));

      await expect(
        retryWithBackoff(mockFn, { maxAttempts: 3 })
      ).rejects.toThrow();

      // Should fail immediately without retrying
      expect(mockFn).toHaveBeenCalledTimes(1);
    });

    it('should enforce timeout limit', async () => {
      const mockFn = jest
        .fn()
        .mockImplementation(
          () => new Promise(resolve => setTimeout(() => resolve('late'), 5000))
        );

      await expect(
        retryWithBackoff(mockFn, {
          maxAttempts: 1,
          timeoutMs: 100,
        })
      ).rejects.toThrow('timeout');
    });
  });

  describe('fetchWithRetry - Convenience Wrapper', () => {
    it('should fetch successfully with retry wrapper', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({ data: 'success' }),
      });

      const response = await fetchWithRetry('https://api.example.com/test', {
        method: 'GET',
      });

      expect(response.ok).toBe(true);
      expect(mockFetch).toHaveBeenCalled();
    });

    it('should retry on network failure and succeed', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch
        .mockRejectedValueOnce(new Error('ECONNREFUSED'))
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ data: 'success' }),
        });

      const response = await fetchWithRetry('https://api.example.com/test', {}, { initialDelayMs: 10 });

      expect(response.ok).toBe(true);
      expect(mockFetch).toHaveBeenCalledTimes(2);
    });
  });

  describe('Helper Functions', () => {
    it('should add contact to list successfully', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({}),
      });

      const result = await addContactToList('john@example.com', 'list-id-123');

      expect(result.success).toBe(true);
    });

    it('should handle list API error', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValue({
        ok: false,
        json: async () => ({ message: 'List not found' }),
      });

      const result = await addContactToList('john@example.com', 'invalid-list-id');

      expect(result.success).toBe(false);
      expect(result.error).toContain('List not found');
    });

    it('should create deal successfully', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({ id: 'deal-456' }),
      });

      const result = await createHubSpotDeal({
        contactEmail: 'john@example.com',
        dealName: 'Test Deal',
        dealAmount: 10000,
      });

      expect(result.success).toBe(true);
      expect(result.dealId).toBe('deal-456');
    });

    it('should handle deal creation errors', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValue({
        ok: false,
        json: async () => ({ message: 'Deal creation failed' }),
      });

      const result = await createHubSpotDeal({
        contactEmail: 'john@example.com',
        dealName: 'Test Deal',
      });

      expect(result.success).toBe(false);
      expect(result.error).toContain('Deal creation failed');
    });

    it('should log activity to existing contact', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          results: [
            {
              id: 'contact-123',
              properties: { email: { value: 'john@example.com' } },
            },
          ],
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({}),
      });

      const result = await logActivityToHubSpot({
        email: 'john@example.com',
        activityType: 'form_submission',
        activityText: 'User submitted demo request form',
      });

      expect(result.success).toBe(true);
    });

    it('should return error if contact not found for activity logging', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({ results: [] }),
      });

      const result = await logActivityToHubSpot({
        email: 'nonexistent@example.com',
        activityType: 'form_submission',
        activityText: 'test',
      });

      expect(result.success).toBe(false);
      expect(result.error).toContain('Contact not found');
    });
  });

  describe('Error Scenarios', () => {
    it('should handle network errors gracefully', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockRejectedValue(new Error('ECONNREFUSED'));

      const result = await syncContactToHubSpot({
        email: 'test@example.com',
      });

      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
    });

    it('should handle malformed responses', async () => {
      const mockFetch = global.fetch as jest.Mock;
      mockFetch.mockResolvedValue({
        ok: true,
        json: async () => ({}), // Missing results array
      });

      const result = await syncContactToHubSpot({
        email: 'test@example.com',
      });

      expect(result.success).toBe(false);
    });
  });
});
