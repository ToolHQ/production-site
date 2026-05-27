import { readFileSync } from 'fs'
import { join } from 'path'
import { __dirname } from './dir.js'

const { commitTitle, sha } = JSON.parse(readFileSync(join(__dirname, '../version.json')).toString())

export const version = `${commitTitle} - ${sha}`

export const mimeTypes = {
  ico: 'image/vnd.microsoft.icon',
  txt: 'text/plain',
  webp: 'image/webp',
  csv: 'text/csv',
  html: 'text/html; charset=utf-8',
  json: 'application/json',
  js: 'text/javascript',
  css: 'text/css',
}

export const cacheConstants = {
  time: {
    twoMinutes: {
      ms: 120000,
      s: 120,
    },
    year: {
      ms: 31536000000,
      s: 31536000,
    },
    week: {
      ms: 604800000,
      s: 604800,
    },
  },
  policies: {
    noStore: 'no-store', // Never store it, never cache
    noCache: 'no-cache', // Always ask server if its ok to use client cache
    // Uses cache without asking server as long it isnt expired (Expired, max-age).
    // Uses shared caches between proxies along the way.
    public: 'public',
    private: 'private', // // Do not use shared caches.
  },
}

export const pkiCertFileName = 'B1428DBC78506B94D0DD0B9170890F76.txt'

/** OCI K8s public IPs — egress for in-cluster scrapers (see config/external-fleet/registry.yaml). */
export const INTERNAL_SCRAPE_IPS = new Set([
  '150.136.34.254',
  '150.136.67.52',
  '150.136.70.212',
  '150.136.88.87',
])
