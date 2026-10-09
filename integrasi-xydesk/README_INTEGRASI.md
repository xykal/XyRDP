# Integrasi XyRDP-SAMP ↔ XyDesk Remote (APK) — Create RDP 1x Iklan

> **Tujuan:** User buka APK XyDesk Remote → tap **“RDP Gratis 6 Jam”** → nonton iklan **1x seumur hidup** → langsung bisa **Create RDP** via WebView tanpa keluar APK. Sisa waktu di dash tampil sebagai **jam digital besar** (bukan progress bar).

Ini paket siap-tempel untuk repo **github.com/xykal/Xydesk-Remote**.

---

## 1) Apa yang sudah jadi di XyRDP (web)

**Web `deploy/vercel/assets/index.html`**
- Sisa waktu diganti **digital-clock** gede: `HH:MM:SS` font mono `JetBrains Mono`-style, blink colon, glow `drop-shadow`, live dot pulsing, sub-text “Sisa X jam Y menit”.
- Progress bar dihapus (tetap ada `<span id="stLeft" class="hidden">` biar JS lama tidak pecah).
- Gate iklan: modal `id="adGate"` → 15s countdown + progress, setelah selesai `localStorage rdp_ad_unlocked=1` + cookie `ad_verified=1` (30 hari) + `POST /api/ad/verify`.

**API `deploy/vercel/api/index.js`**
- `POST /api/ad/verify` → `Set-Cookie: ad_verified=1; Max-Age=2592000`
- `GET /api/ad/status` → `{unlocked:true|false}`
- `GET /api/apk` → info APK
- `POST /api/start` sekarang **wajib iklan** untuk `kind=user` (admin bypass):
  ```js
  if (ctx.kind==='user' && !hasAd && AD_GATE_DISABLED!=='1') return 402 {need_ad:true}
  ```
  Header yang diterima: `ad_verified` cookie **atau** `X-Ad-Verified:1` / `X-Xy-Ad:1` (untuk APK WebView).
- CORS `*` untuk `/ad/*` & `/apk`.

**Cara test web:**
- Buka `/id/home`, tombol **Mulai Sesi** akan buka gate kalau belum unlock.
- Setelah “Nonton 15s”, localStorage + cookie set, tombol langsung aktif selamanya.
- Sisa waktu sekarang tampil di kartu **Sesi** → jam digital `06:00:00` gede.

---

## 2) Integrasi APK — 3 langkah

### Langkah A — Tambah AdMob (Rewarded)

`client/Android/Studio/app/build.gradle` → dependencies:
```gradle
implementation 'com.google.android.gms:play-services-ads:23.0.0'
```

`AndroidManifest.xml` → dalam `<application>`:
```xml
<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyy"/>
<!-- pakai TEST ID dulu: ca-app-pub-3940256099942544~3347511713 -->
```

### Langkah B — Copy 2 file baru

Copy ke `client/Android/Studio/app/src/main/kotlin/id/xydesk/remote/ui/`:

- **`XyFreeRdpScreen.kt`** (sudah disertakan di folder ini) — WebView + Ad gate + bridge.
- **`XyRdpAdHelper.kt`** (opsional, bisa gabung) — helper AdMob.

### Langkah C — Tambah entry di Home

Buka `XyDeskHome.kt`, tambahkan card di atas daftar perangkat (lihat diff `patch_XyDeskHome.kt.diff`).

**Snippet minimal:**
```kotlin
// di Devices route, paling atas Column
XyFreeRdpCard(
  unlocked = appPrefs.rdpFreeAdUnlocked,
  onCreate = {
    if (appPrefs.rdpFreeAdUnlocked) navToRdpFree()
    else showRdpAd { appPrefs.rdpFreeAdUnlocked = true; navToRdpFree() }
  }
)
```

Tambahkan di `AppPrefs.kt`:
```kotlin
var rdpFreeAdUnlocked: Boolean
  get() = sp.getBoolean("rdp_free_ad_unlocked", false)
  set(v) = sp.edit().putBoolean("rdp_free_ad_unlocked", v).apply()
```

---

## 3) Alur APK (user perspective)

1. Buka XyDesk Remote → **Beranda** → card **“RDP Gratis 6 Jam — Buat Windows di HP”**
2. Tap **Create RDP** → kalau belum pernah nonton, muncul **Rewarded Ad** (15-30s)
3. Selesai nonton → `rdpFreeAdUnlocked=true` + `CookieManager.setCookie("https://xyrdp-dash.vercel.app","ad_verified=1")`
4. WebView load `https://xyrdp-dash.vercel.app/id/home?apk=1` → user login GitHub (OAuth) di WebView → tap **Mulai Sesi** (sudah unlocked, tidak minta iklan lagi)
5. Polling ` /api/status` → jam digital gede `05:42:11` muncul.
6. Kartu koneksi → **“Connect di XyDesk”** (bridge) otomatis buat `ConnectionProfile(host=100.x, user, pass)` → `XyDeskSessionActivity`.

Sekali unlock, selamanya tidak minta iklan lagi (per device). Kalau reinstall, nonton lagi 1x.

---

## 4) Bridge Web ↔ APK (opsional canggih)

Web (`index.html`) sudah expose:
```js
window.XyDesk = window.XyDesk || {}
// APK inject via addJavascriptInterface
// Web kalau detect `Android` atau `?apk=1` tampilkan tombol “Buka di XyDesk”
if (navigator.userAgent.includes("XyDesk")) {
  // tampilkan extra button
}
```

Di `XyFreeRdpScreen.kt`, WebView sudah inject:
```kotlin
webView.addJavascriptInterface(object{
  @JavascriptInterface fun onRdpCreated(json: String){ /* parse ip/user/pass, buat profile */ }
}, "Android")
```
Web bisa panggil `Android.onRdpCreated(...)` saat `poll()` detect `session.active`.

---

## 5) Test checklist

- [ ] Web: clear `localStorage` → click **Mulai Sesi** → gate muncul → 15s → unlock → start berhasil (200) tanpa 402.
- [ ] API: `curl -X POST https://xyrdp-dash.vercel.app/api/ad/verify -c cookies.txt` → cookie set → `curl -b cookies.txt POST /api/start` → 200 (bukan 402).
- [ ] APK: fresh install → tap Create → ad muncul → setelah reward, WebView load dash → login GitHub → Create → jam digital muncul `HH:MM:SS`.
- [ ] Reopen APK → tap Create → langsung WebView (tidak minta ad lagi).

---

## 6) File di paket ini

- `XyFreeRdpScreen.kt` — full Compose screen
- `patch_XyDeskHome.kt.diff` — diff 12 baris untuk tambah card
- `patch_AppPrefs.kt.diff` — tambah pref
- `README_INTEGRASI.md` — ini

Credit tetap **KallAncrit** untuk XyRDP template.

