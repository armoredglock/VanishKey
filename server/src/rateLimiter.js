import { logger } from './logger.js';

export class RateLimiter {
  constructor(maxRequests = 3, windowMs = 60 * 60 * 1000) {
    this.maxRequests = maxRequests;
    this.windowMs = windowMs;
    // Map of ownerId -> array of timestamps
    this.records = new Map();
  }

  /**
   * Check if the request is permitted for the given ownerId.
   * If permitted, records the timestamp and returns { allowed: true, remaining: number }.
   * If exceeded, returns { allowed: false, retryAfterSeconds: number }.
   */
  consume(ownerId) {
    const now = Date.now();
    const windowStart = now - this.windowMs;

    let timestamps = this.records.get(ownerId) || [];
    // Filter out timestamps older than the sliding window
    timestamps = timestamps.filter(ts => ts > windowStart);

    if (timestamps.length >= this.maxRequests) {
      const oldestInWindow = timestamps[0];
      const retryAfterSeconds = Math.ceil((oldestInWindow + this.windowMs - now) / 1000);
      logger.warn({ ownerId, remaining: 0, retryAfterSeconds }, 'Rate limit exceeded for owner');
      return {
        allowed: false,
        remaining: 0,
        retryAfterSeconds: Math.max(1, retryAfterSeconds)
      };
    }

    timestamps.push(now);
    this.records.set(ownerId, timestamps);
    const remaining = this.maxRequests - timestamps.length;
    logger.info({ ownerId, remaining }, 'Rate limit quota consumed');

    return {
      allowed: true,
      remaining
    };
  }

  /**
   * Refund one consumed slot (e.g. if the target device was offline or script failed)
   */
  refund(ownerId) {
    const timestamps = this.records.get(ownerId) || [];
    if (timestamps.length > 0) {
      timestamps.pop();
      this.records.set(ownerId, timestamps);
      logger.info({ ownerId, remaining: this.maxRequests - timestamps.length }, 'Rate limit slot refunded');
    }
  }

  /**
   * Reset rate limit records for an owner (useful for testing)
   */
  reset(ownerId) {
    this.records.delete(ownerId);
  }
}

export const globalRateLimiter = new RateLimiter(3, 60 * 60 * 1000);
