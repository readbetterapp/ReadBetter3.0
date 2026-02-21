/**
 * In-memory caching utilities for API responses
 */

class Cache {
  constructor() {
    this.cache = new Map();
  }

  /**
   * Get value from cache if not expired
   * @param {string} key - Cache key
   * @returns {any|null} - Cached value or null if expired/missing
   */
  get(key) {
    const entry = this.cache.get(key);
    if (!entry) return null;

    // Check if expired
    if (Date.now() > entry.expiresAt) {
      this.cache.delete(key);
      return null;
    }

    return entry.value;
  }

  /**
   * Set value in cache with TTL
   * @param {string} key - Cache key
   * @param {any} value - Value to cache
   * @param {number} ttlMs - Time to live in milliseconds
   */
  set(key, value, ttlMs) {
    this.cache.set(key, {
      value,
      expiresAt: Date.now() + ttlMs
    });
  }

  /**
   * Delete value from cache
   * @param {string} key - Cache key
   */
  delete(key) {
    this.cache.delete(key);
  }

  /**
   * Clear all cache entries
   */
  clear() {
    this.cache.clear();
  }

  /**
   * Clean up expired entries
   */
  cleanup() {
    const now = Date.now();
    for (const [key, entry] of this.cache.entries()) {
      if (now > entry.expiresAt) {
        this.cache.delete(key);
      }
    }
  }
}

// Create singleton instances for different cache types
const libraryCache = new Cache();
const chapterIndexCache = new Cache();

// Cleanup expired entries every 5 minutes
setInterval(() => {
  libraryCache.cleanup();
  chapterIndexCache.cleanup();
}, 5 * 60 * 1000);

module.exports = {
  libraryCache,
  chapterIndexCache
};

















