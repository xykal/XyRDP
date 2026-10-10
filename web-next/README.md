# RdpFree — Next.js + Cloudflare

Migration staging: https://rdpfree-next.dikanjut.workers.dev

Stack: Next.js 15.5.27, NextAuth 4, OpenNext Cloudflare, Workers. Node 22+.
Next 16.4 built successfully but failed at Workers runtime (`preview-props.json`); pinned to the patched 15.5 release.

## Implemented
- Separate login and server-protected dashboard routes.
- Encrypted HttpOnly cookie session, 30-day maximum. No access token in client session or localStorage.
- Real GitHub repository summary, root folder listing, Actions run listing.
- Sign-out using NextAuth's CSRF-protected flow.
- Runtime secrets stored using Workers secrets.

## Remaining before cutover
- Update the GitHub OAuth App authorization callback to:
  `https://rdpfree-next.dikanjut.workers.dev/api/auth/callback/github`
  Prefer a separate OAuth app for staging to preserve old production login.
- Complete actual user OAuth and browser reload/navigation/logout tests. Manual session tests are not a substitute.
- Port RDP start/stop, workflow settings, secret management, admin dashboard and nested folder browsing from the existing app.
- Resolve dependency audit findings before production cutover.
- Existing Vercel site remains unchanged; this is not feature-complete production replacement.

## Checks performed
- Next production build and OpenNext bundle: passed.
- Workers deployment: succeeded.
- GET /login: 200.
- GET /dashboard without cookie: 307.
- GET /api/auth/session without cookie: 200 empty session.
- GET /api/github without cookie: 401.
- CSRF + POST GitHub sign-in: github.com authorization URL, correct callback, OAuth state cookie Secure/HttpOnly/SameSite=Lax.
- Lint: no errors (one config export style warning).

## Commands
```
npm ci
npm run dev
npm run build:worker
npm run deploy
```
Configure GITHUB_ID, GITHUB_SECRET, NEXTAUTH_SECRET and NEXTAUTH_URL as Worker secrets. Keep the session secret stable across deployments. Never commit env files. OAuth credentials are server-only.

Credit: KallAncrit
