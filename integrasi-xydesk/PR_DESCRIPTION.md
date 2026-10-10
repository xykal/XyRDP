# PR: Jam Digital Gede + Gate Iklan 1x + Integrasi XyDesk Remote APK

## Ringkas
- **Jam digital** keren gede `HH:MM:SS` ganti progres bar di kartu Sesi — font mono 42px, blink colon, glow, live dot, sub “Sisa X jam Y menit”.
- **Gate iklan 1x seumur hidup**: modal 15s + progress, unlock `localStorage rdp_ad_unlocked` + cookie `ad_verified=1` (30d) + `POST /api/ad/verify`. Tombol **Mulai Sesi** di-intercept, cuma unlock sekali, selamanya gratis.
- **Integrasi APK** `github.com/xykal/Xydesk-Remote`: WebView `?apk=1` + `CookieManager ad_verified` + bridge `window.Android.onRdpCreated` / `window.XyDesk.onRdpCreated` → auto buat `ConnectionProfile` dan connect.
- **API**: `POST /api/ad/verify`, `GET /api/ad/status`, `GET /api/apk`, `POST /api/start` wajib ad (402 need_ad) untuk user (admin bypass).

## Perubahan
- `deploy/vercel/assets/index.html` — digital-clock CSS, `adGate` modal, JS `isAdUnlocked`/`setAdUnlocked`/`showAdGate`, poll update ke `dcH/dcM/dcS` + `dcSub`/`dcHint`, hook `bStart` click, APK `?apk=1` detect, bridge payload.
- `deploy/vercel/api/index.js` — CORS, `/ad/verify|/ad/status|/apk`, gate di `/start` (check `ad_verified` cookie atau `X-Ad-Verified`/`X-Xy-Ad` header).
- `integrasi-xydesk/` — `XyFreeRdpScreen.kt` (full Compose + WebView + mock rewarded), `README_INTEGRASI.md`, `patch_*.diff` siap tempel.

## Test
- `node --check` 0, `grep -c digital-clock` 3, `grep -c adGate` 2, `grep -c dcH` true, `api ad_verified` true.
- Web: clear storage → klik Mulai Sesi → gate → 15s → start 200 (bukan 402) → jam digital `06:00:00` → countdown `05:42:11`.
- API: `curl POST /api/ad/verify -c c.txt` → `curl -b c.txt POST /api/start` → 200; tanpa cookie → 402.
- APK: fresh install → tap Create → rewarded → WebView dash → login GitHub → Create → jam digital → `onRdpCreated` → connect.

## Cara pakai APK
1. Tambah `play-services-ads` di `app/build.gradle`, `APPLICATION_ID` di `AndroidManifest.xml`.
2. Copy `XyFreeRdpScreen.kt` ke `ui/`, apply `patch_AppPrefs.kt.diff` + `patch_XyDeskHome.kt.diff`.
3. Build APK, test flow di atas.

Credit: KallAncrit (template XyRDP)

Branch: `feat/digital-clock-ad-gate-apk` → `main`
