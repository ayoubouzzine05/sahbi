import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';

/**
 * Anonymous per-install tokens: `v1.<installId>.<issuedAtSec>.<hmac>`.
 * Stateless (HMAC with AUTH_SECRET); no user data involved. Tokens expire after `ttlSec`.
 */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isValidInstallId(id: string): boolean {
  return UUID_RE.test(id);
}

function sign(secret: string, payload: string): string {
  return createHmac('sha256', secret).update(payload).digest('base64url');
}

export function issueToken(secret: string, installId: string, nowSec = Math.floor(Date.now() / 1000)): string {
  const payload = `v1.${installId.toLowerCase()}.${nowSec}`;
  return `${payload}.${sign(secret, payload)}`;
}

export function verifyToken(secret: string, token: string, ttlSec = 60 * 60 * 24 * 30, nowSec = Math.floor(Date.now() / 1000)): string | null {
  const parts = token.split('.');
  if (parts.length !== 4 || parts[0] !== 'v1') return null;
  const [, installId, issued, mac] = parts as [string, string, string, string];
  if (!isValidInstallId(installId)) return null;
  const issuedAt = Number(issued);
  if (!Number.isInteger(issuedAt) || issuedAt > nowSec + 60 || nowSec - issuedAt > ttlSec) return null;
  const expected = Buffer.from(sign(secret, `v1.${installId}.${issued}`));
  const given = Buffer.from(mac);
  if (expected.length !== given.length || !timingSafeEqual(expected, given)) return null;
  return installId;
}

export function ephemeralSecret(): string {
  return `${randomUUID()}${randomUUID()}`;
}
