import { defineConfig } from 'vitest/config'

// Kept apart from vite.config.ts: the Cloudflare plugin targets the Workers
// runtime, while these tests run plain TypeScript in Node.
export default defineConfig({
  test: {
    include: ['src/**/*.test.{ts,tsx}', 'scripts/**/*.test.ts'],
  },
})
