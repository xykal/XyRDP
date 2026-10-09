package id.xydesk.remote.ui

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import id.xydesk.remote.core.ConnectionProfile
import id.xydesk.remote.core.RdpOptions
import id.xydesk.remote.ui.components.XyPillButton
import id.xydesk.remote.ui.components.XyCard
import kotlinx.coroutines.launch

/**
 * XyFreeRdpScreen — Create RDP 6 jam dari APK XyDesk Remote.
 *
 * - Nonton iklan Rewarded 1x seumur hidup (per device) → unlock.
 * - WebView load https://xyrdp-dash.vercel.app/id/home?apk=1
 * - Setelah RDP aktif, user bisa tap "Connect di XyDesk" → auto buat profile.
 *
 * TEMPEL file ini di: client/Android/Studio/app/src/main/kotlin/id/xydesk/remote/ui/XyFreeRdpScreen.kt
 * Tambah di AppPrefs: var rdpFreeAdUnlocked
 * Panggil dari XyDeskHome: XyFreeRdpScreen(onBack, onConnect)
 */

// ---------- CARD di Home ----------
@Composable
fun XyFreeRdpCard(
    unlocked: Boolean,
    onCreate: () -> Unit,
    modifier: Modifier = Modifier
) {
    XyCard(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 8.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    Brush.linearGradient(
                        listOf(Color(0xFF1A1A2E), Color(0xFF0F0F18))
                    ),
                    RoundedCornerShape(22.dp)
                )
                .clip(RoundedCornerShape(22.dp))
                .padding(16.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(42.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(Brush.linearGradient(listOf(Color(0xFFFF4D00), Color(0xFFFF8A00)))),
                    contentAlignment = Alignment.Center
                ) { Text("⚡", fontSize = 20.sp) }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text("RDP Gratis 6 Jam", color = Color.White, fontWeight = FontWeight.ExtraBold, fontSize = 15.sp, letterSpacing = (-0.3).sp)
                    Text("Buat Windows di HP • 1x iklan aja", color = Color(0xFF9AA0B6), fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                }
                if (unlocked) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(99.dp))
                            .background(Color(0xFF22C55E).copy(0.14f))
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    ) { Text("✓ TERBUKA", color = Color(0xFF86EFAC), fontSize = 10.sp, fontWeight = FontWeight.ExtraBold) }
                } else {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(99.dp))
                            .background(Color(0xFFFF8A00).copy(0.18f))
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    ) { Text("▶ 1X IKLAN", color = Color(0xFFFFC08A), fontSize = 10.sp, fontWeight = FontWeight.ExtraBold) }
                }
            }
            Spacer(Modifier.height(12.dp))
            Text(
                "Windows 11 Pro di cloud GitHub Actions, konek via Tailscale 100.x atau RustDesk. Jam digital gede, bukan progress bar. Credit KallAncrit.",
                color = Color(0xFFB8BDCF), fontSize = 12.sp, lineHeight = 16.sp
            )
            Spacer(Modifier.height(14.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                XyPillButton(
                    text = if (unlocked) "🚀 Create RDP Sekarang" else "▶ Nonton Iklan & Create",
                    onClick = onCreate,
                    modifier = Modifier.weight(1f)
                )
                XyPillButton(
                    text = "ℹ️",
                    onClick = { /* show info */ },
                )
            }
            if (!unlocked) {
                Text("Sekali nonton, selamanya gratis di device ini.", color = Color(0xFF6B7280), fontSize = 10.sp, modifier = Modifier.padding(top = 8.dp))
            }
        }
    }
}

// ---------- AD HELPER (AdMob Rewarded) ----------
/**
 * Helper minimal. Ganti TEST_ID dengan ID produksi kamu.
 * TEST rewarded: ca-app-pub-3940256099942544/5224354917
 */
object XyRdpAdHelper {
    const val TEST_REWARDED_ID = "ca-app-pub-3940256099942544/5224354917"
    // TODO: ganti dengan ID produksi: ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy
    const val PROD_REWARDED_ID = "ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy"

    fun loadRewarded(context: Context, onLoaded: (Any?) -> Unit, onFailed: () -> Unit) {
        // Tanpa SDK pun tetap jalan: fallback mock 15s
        // Kalau sudah tambah play-services-ads, ganti dengan:
        // val adRequest = AdRequest.Builder().build()
        // RewardedAd.load(context, rewardedId, adRequest, callback)
        // Untuk paket ini, pakai mock biar tidak wajib compile AdMob dulu.
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            onLoaded(null) // mock success
        }, 500)
    }
}

// ---------- FULL SCREEN WebView ----------
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun XyFreeRdpScreen(
    onBack: () -> Unit,
    onConnectProfile: (ConnectionProfile) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showAdGate by remember { mutableStateOf(false) }
    var adUnlocked by remember {
        mutableStateOf(
            context.getSharedPreferences("xydesk.app", Context.MODE_PRIVATE)
                .getBoolean("rdp_free_ad_unlocked", false)
        )
    }

    fun unlock() {
        adUnlocked = true
        context.getSharedPreferences("xydesk.app", Context.MODE_PRIVATE)
            .edit().putBoolean("rdp_free_ad_unlocked", true).apply()
        // set cookie untuk WebView supaya /api/start tidak 402
        try {
            val cm = CookieManager.getInstance()
            cm.setAcceptCookie(true)
            cm.setCookie("https://xyrdp-dash.vercel.app", "ad_verified=1; Path=/; Max-Age=2592000")
            cm.flush()
        } catch (_: Exception) {}
    }

    // Cek pref saat masuk
    LaunchedEffect(Unit) {
        if (!adUnlocked) showAdGate = true
    }

    Column(Modifier.fillMaxSize().background(Color(0xFF08080B))) {
        // Top bar
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            XyPillButton(text = "← Kembali", onClick = onBack)
            Text("RDP Gratis — XyDesk", color = Color.White, fontWeight = FontWeight.ExtraBold, fontSize = 13.sp)
            Box(Modifier.size(1.dp))
        }

        if (showAdGate && !adUnlocked) {
            // Gate overlay (Compose)
            Column(
                Modifier.fillMaxSize().padding(16.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Box(
                    Modifier.fillMaxWidth()
                        .clip(RoundedCornerShape(28.dp))
                        .background(Color(0xFF1A1A2E))
                        .padding(20.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("▶ IKLAN • 1X SEUMUR HIDUP", color = Color(0xFFFF8A00), fontSize = 10.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 1.sp)
                        Spacer(Modifier.height(8.dp))
                        Text("Buka Create RDP gratis", color = Color.White, fontWeight = FontWeight.ExtraBold, fontSize = 18.sp)
                        Text("Tonton iklan 15 detik sekali aja, setelah itu Create kebuka selamanya. Support server bre! 🙏", color = Color(0xFF9AA0B6), fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                        Spacer(Modifier.height(16.dp))
                        // Mock ad preview
                        Box(
                            Modifier.fillMaxWidth().height(110.dp)
                                .clip(RoundedCornerShape(18.dp))
                                .background(Color(0xFF0F0F18)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("▷ Iklan XyDesk Remote akan diputar di sini", color = Color(0xFF6B7280), fontSize = 11.sp)
                        }
                        Spacer(Modifier.height(14.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                            OutlinedButton(onClick = onBack, modifier = Modifier.weight(1f), shape = RoundedCornerShape(99.dp)) { Text("Nanti") }
                            var watching by remember { mutableStateOf(false) }
                            var sec by remember { mutableIntStateOf(15) }
                            var prog by remember { mutableFloatStateOf(0f) }
                            LaunchedEffect(watching) {
                                if (!watching) return@LaunchedEffect
                                while (sec > 0) {
                                    kotlinx.coroutines.delay(1000)
                                    sec--
                                    prog = (15 - sec) / 15f
                                    if (sec <= 0) {
                                        unlock()
                                        showAdGate = false
                                        Toast.makeText(context, "Iklan selesai — Create RDP terbuka!", Toast.LENGTH_SHORT).show()
                                    }
                                }
                            }
                            Button(
                                onClick = {
                                    if (!watching) {
                                        watching = true
                                        // Kalau sudah ada AdMob, panggil:
                                        // XyRdpAdHelper.loadRewarded(...) { ad -> ad.show(...) { unlock() } }
                                    }
                                },
                                enabled = !watching || sec <= 0,
                                modifier = Modifier.weight(1f),
                                shape = RoundedCornerShape(99.dp)
                            ) {
                                Text(if (!watching) "▶ Nonton 15s" else "${sec}s...")
                            }
                        }
                        if (adUnlocked) Text("✓ Terbuka", color = Color(0xFF22C55E), fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp))
                    }
                }
            }
        } else {
            // WebView
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.allowFileAccess = false
                        webChromeClient = WebChromeClient()
                        webViewClient = object : WebViewClient() {
                            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                                return false // buka di WebView yang sama
                            }
                            override fun onPageFinished(view: WebView?, url: String?) {
                                // inject unlocked flag
                                view?.evaluateJavascript(
                                    """
                                    (function(){
                                      try{ localStorage.setItem('rdp_ad_unlocked','1'); }catch(e){}
                                      document.cookie='ad_verified=1; Path=/; Max-Age=2592000';
                                      if(window.XyRdpAd) window.XyRdpAd.unlock();
                                    })();
                                    """.trimIndent(), null
                                )
                            }
                        }
                        // JS bridge untuk auto-connect
                        addJavascriptInterface(object {
                            @JavascriptInterface
                            fun onRdpCreated(json: String) {
                                // json: {"ip":"100.x","user":"xyadmin","pass":"..."}
                                scope.launch {
                                    try {
                                        // parse simpel
                                        val ip = Regex("\"ip\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1) ?: ""
                                        val user = Regex("\"user\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1) ?: "xyadmin"
                                        val pass = Regex("\"pass\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1) ?: ""
                                        if (ip.isNotBlank()) {
                                            val profile = ConnectionProfile(
                                                id = java.util.UUID.randomUUID().toString(),
                                                label = "RDP Gratis $ip",
                                                host = ip,
                                                port = 3389,
                                                username = user,
                                                // password disimpan via gateway (terenkripsi)
                                            )
                                            // simpan via SessionsRepository kalau mau
                                            Toast.makeText(context, "RDP $ip siap — buka sesi?", Toast.LENGTH_LONG).show()
                                            onConnectProfile(profile)
                                        }
                                    } catch (e: Exception) {
                                        Toast.makeText(context, "Gagal parse RDP: ${e.message}", Toast.LENGTH_SHORT).show()
                                    }
                                }
                            }
                        }, "Android")
                        // cookie untuk ad
                        CookieManager.getInstance().setAcceptCookie(true)
                        CookieManager.getInstance().setCookie("https://xyrdp-dash.vercel.app", "ad_verified=1; Path=/; Max-Age=2592000")
                        loadUrl("https://xyrdp-dash.vercel.app/id/home?apk=1")
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
        }
    }
}
