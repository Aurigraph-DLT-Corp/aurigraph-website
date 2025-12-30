/**
 * HubSpot API Retry & Timeout Helper
 * Wraps all HubSpot API calls with:
 * - 10-second timeout protection
 * - Exponential backoff retry (2s, 4s, 8s)
 * - Detailed error logging
 */

export interface RetryOptions {
  maxAttempts?: number;
  timeoutMs?: number;
  initialDelayMs?: number;
}

const DEFAULT_OPTIONS: RetryOptions = {
  maxAttempts: 3,
  timeoutMs: 10000, // 10 seconds
  initialDelayMs: 2000, // Start with 2 seconds
};

/**
 * Wraps a fetch request with timeout and exponential backoff retry
 *
 * @param fn - Async function that returns a Promise (typically a fetch call)
 * @param options - Retry configuration
 * @returns Promise with the response
 *
 * @example
 * const response = await retryWithBackoff(
 *   () => fetch('https://api.hubapi.com/...'),
 *   { maxAttempts: 3, timeoutMs: 10000 }
 * );
 */
export async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  options: RetryOptions = {}
): Promise<T> {
  const config = { ...DEFAULT_OPTIONS, ...options };
  const { maxAttempts = 3, timeoutMs = 10000, initialDelayMs = 2000 } = config;

  let lastError: Error | null = null;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      // Wrap the function in a timeout promise
      const result = await Promise.race([
        fn(),
        new Promise<never>((_, reject) =>
          setTimeout(
            () => reject(new Error(`Request timeout after ${timeoutMs}ms`)),
            timeoutMs
          )
        ),
      ]);

      // Success - return immediately
      if (attempt > 1) {
        console.log(`HubSpot API call succeeded on attempt ${attempt}`);
      }
      return result;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));

      // Check if this is a retryable error
      const isRetryable = isRetryableError(lastError);
      const isLastAttempt = attempt === maxAttempts;

      // Log the error with context
      console.warn(
        `HubSpot API error on attempt ${attempt}/${maxAttempts}: ${lastError.message} (retryable: ${isRetryable})`
      );

      // If this was the last attempt or error is not retryable, throw
      if (isLastAttempt || !isRetryable) {
        throw lastError;
      }

      // Calculate exponential backoff delay
      const delayMs = initialDelayMs * Math.pow(2, attempt - 1);
      console.log(`Retrying HubSpot API call in ${delayMs}ms...`);

      // Wait before retrying
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }

  // Should never reach here, but just in case
  throw lastError || new Error('Unknown error in retryWithBackoff');
}

/**
 * Determines if an error is retryable
 * Retryable: Network errors, timeouts, 429 (rate limit), 5xx (server errors)
 * Non-retryable: 400 (bad request), 401 (auth), 403 (forbidden), 404 (not found)
 */
function isRetryableError(error: Error): boolean {
  const message = error.message.toLowerCase();

  // Retryable error patterns
  const retryablePatterns = [
    'econnrefused', // Connection refused
    'enotfound', // DNS lookup failed
    'etimedout', // Network timeout
    'timeout after', // Our timeout error
    '429', // Rate limit
    '500', // Internal server error
    '502', // Bad gateway
    '503', // Service unavailable
    '504', // Gateway timeout
  ];

  return retryablePatterns.some(pattern => message.includes(pattern));
}

/**
 * Wraps a fetch call with automatic retry and timeout
 *
 * @param url - URL to fetch
 * @param options - Fetch options (headers, body, etc.)
 * @param retryOptions - Retry configuration
 * @returns Promise with the Response
 */
export async function fetchWithRetry(
  url: string,
  options?: RequestInit,
  retryOptions?: RetryOptions
): Promise<Response> {
  return retryWithBackoff(() => fetch(url, options), retryOptions);
}
