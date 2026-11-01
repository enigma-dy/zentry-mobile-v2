package com.zentry.predict

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.ConsoleMessage
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** One off-screen browser per resolution. No browser view is attached to the UI. */
class StreamBrowser(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private var browser: WebView? = null
    private var pending: MethodChannel.Result? = null
    private var generation = 0
    private var pageUrl = ""
    private var userAgent = ""
    private data class Candidate(val url: String, val headers: Map<String, String>, val score: Int)
    private var candidate: Candidate? = null
    private var selectionScheduled = false
    private val mediaPath = Regex("\\.(m3u8|mpd|mp4|webm)(?:[?#]|$)", RegexOption.IGNORE_CASE)
    private val mediaQuery = Regex("[?&](?:format|type|output)=(?:hls|dash|m3u8|mpd)(?:&|$)", RegexOption.IGNORE_CASE)

    @SuppressLint("SetJavaScriptEnabled")
    fun resolve(url: String?, result: MethodChannel.Result, referer: String? = null) {
        val uri = url?.let { Uri.parse(it) }
        if (uri == null || uri.host.isNullOrEmpty() || uri.scheme !in listOf("http", "https")) {
            result.error("invalid_url", "Enter a valid HTTP or HTTPS webpage URL.", null)
            return
        }
        cancel()
        pending = result
        val session = generation
        pageUrl = uri.toString()
        try {
            val view = WebView(activity)
            browser = view
            view.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                mediaPlaybackRequiresUserGesture = false
                allowFileAccess = false
                allowContentAccess = false
                setSupportMultipleWindows(true)
                javaScriptCanOpenWindowsAutomatically = false
                mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            }
            userAgent = view.settings.userAgentString
            CookieManager.getInstance().setAcceptThirdPartyCookies(view, true)
            // Size permits responsive embedded players without displaying a WebView.
            view.layout(0, 0, 1280, 720)
            view.webChromeClient = object : WebChromeClient() {
                override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                    val text = message.message()
                    if (text.startsWith(MARKER)) {
                        try {
                            val data = JSONObject(text.removePrefix(MARKER))
                            // Prefer actual network headers over an early JavaScript observation.
                            handler.postDelayed({
                                capture(session, data.getString("url"), mapOf("Referer" to data.optString("referer", pageUrl)), false)
                            }, 200)
                        } catch (_: Exception) { /* Ignore malformed page messages. */ }
                        return true
                    }
                    return false
                }
                // Popups are never opened in an external browser.
                override fun onCreateWindow(view: WebView?, dialog: Boolean, gesture: Boolean, transport: android.os.Message?) = false
            }
            view.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    if (request.method == "GET") capture(session, request.url.toString(), request.requestHeaders)
                    return null // Observe only; keep the page's original requests intact.
                }
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                    request.url.scheme !in listOf("http", "https")

                override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                    view.evaluateJavascript(script, null)
                }
                override fun onPageFinished(view: WebView, url: String) {
                    view.evaluateJavascript(script, null)
                }
            }
            // Inject in cross-origin frames too, before their players initialize.
            if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                WebViewCompat.addDocumentStartJavaScript(view, script, setOf("*"))
            }
            handler.postDelayed({
                if (session == generation && pending != null) {
                    finishError("stream_timeout", "No playable stream appeared within 45 seconds. The event may be offline or unavailable.")
                }
            }, 45_000)
            val headers = mutableMapOf<String, String>()
            if (referer != null && Uri.parse(referer).scheme in listOf("http", "https")) {
                headers["Referer"] = referer
            }
            view.loadUrl(pageUrl, headers)
        } catch (error: Exception) {
            finishError("browser_error", error.message ?: "Could not start the stream browser.")
        }
    }

    private fun capture(session: Int, url: String, requestHeaders: Map<String, String>, fromNetwork: Boolean = true) {
        val uri = Uri.parse(url)
        if (uri.scheme !in listOf("http", "https") || uri.host.isNullOrEmpty()) return
        if (!mediaPath.containsMatchIn(url) && !mediaQuery.containsMatchIn(url)) return
        // Interception is on a worker thread; cookies, results and WebView cleanup run on the UI thread.
        handler.post {
            if (session != generation || pending == null) return@post
            // Prefer playlists and actual browser headers over early JS observations.
            val score = (if (uri.path.orEmpty().endsWith(".m3u8", true) || uri.path.orEmpty().endsWith(".mpd", true) || mediaQuery.containsMatchIn(url)) 20 else 10) +
                (if (fromNetwork) 3 else 0)
            if (candidate == null || score > candidate!!.score || candidate!!.url == url && score >= candidate!!.score) {
                candidate = Candidate(url, requestHeaders.toMap(), score)
            }
            if (!selectionScheduled) {
                selectionScheduled = true
                // Let the first playlist request finish and session cookies settle.
                handler.postDelayed({ completeSelection(session) }, 1500)
            }
        }
    }

    private fun completeSelection(session: Int) {
        if (session != generation || pending == null) return
        val selected = candidate ?: return
        val url = selected.url
        val headers = mutableMapOf<String, String>()
        for ((name, value) in selected.headers) {
            if (name.lowercase() in setOf("referer", "origin", "user-agent", "cookie", "authorization")) {
                headers[name] = value
            }
        }
        if (headers.keys.none { it.equals("Referer", true) }) headers["Referer"] = pageUrl
        if (headers.keys.none { it.equals("User-Agent", true) }) headers["User-Agent"] = userAgent
        CookieManager.getInstance().getCookie(url)?.takeIf { it.isNotBlank() }?.let {
            headers.keys.filter { key -> key.equals("Cookie", true) }.toList().forEach { key -> headers.remove(key) }
            headers["Cookie"] = it
        }
        val result = pending
        pending = null
        val title = browser?.title?.takeIf { it.isNotBlank() } ?: "Video"
        // Keep page timers/session alive during native playback. Closing the page
        // immediately can interrupt provider initialization and session heartbeats.
        result?.success(mapOf("url" to url, "headers" to headers, "title" to title))
    }

    fun handoff() {
        // Pause hidden media after the native player is ready, without stopping the
        // page's JavaScript/session or downloading two copies of the live stream.
        browser?.evaluateJavascript("window.postMessage({streamBrowserHandoff:true}, '*');", null)
    }

    fun cancel() {
        if (pending != null) finishError("cancelled", "Stream detection was cancelled.") else cleanup()
    }

    private fun finishError(code: String, message: String) {
        val result = pending
        pending = null
        cleanup()
        result?.error(code, message, null)
    }

    private fun cleanup() {
        generation++
        candidate = null
        selectionScheduled = false
        handler.removeCallbacksAndMessages(null)
        browser?.apply {
            stopLoading()
            webChromeClient = null
            destroy()
        }
        browser = null
    }

    companion object {
        private const val MARKER = "__STREAM_BROWSER__:"
        // This script observes public media URLs; it never exposes a native JS bridge.
        private val script = """
            (() => {
              if (window.__streamBrowser) return;
              window.__streamBrowser = true;
              const handoff = () => {
                window.__streamBrowserHandoff = true;
                document.querySelectorAll('video,audio').forEach(m => m.pause());
                for (let i = 0; i < frames.length; i++) {
                  try { frames[i].postMessage({streamBrowserHandoff:true}, '*'); } catch (_) {}
                }
              };
              window.addEventListener('message', event => {
                if (event.data && event.data.streamBrowserHandoff === true) handoff();
              });
              const report = raw => {
                try {
                  const url = new URL(raw, location.href).href;
                  if (/^https?:/.test(url) && /\.(m3u8|mpd|mp4|webm)([?#]|$)|[?&](format|type|output)=(hls|dash|m3u8|mpd)(&|$)/i.test(url))
                    console.debug('__STREAM_BROWSER__:' + JSON.stringify({url, referer: location.href}));
                } catch (_) {}
              };
              const originalFetch = window.fetch;
              window.fetch = function(input, init) {
                report(typeof input === 'string' ? input : input && input.url);
                return originalFetch.apply(this, arguments);
              };
              const originalOpen = XMLHttpRequest.prototype.open;
              XMLHttpRequest.prototype.open = function(method, url) {
                report(url); return originalOpen.apply(this, arguments);
              };
              try {
                new PerformanceObserver(list => list.getEntries().forEach(e => report(e.name)))
                  .observe({type: 'resource', buffered: true});
              } catch (_) {}
              const scan = () => {
                if (window.__streamBrowserHandoff) { handoff(); return; }
                document.querySelectorAll('video, audio').forEach(media => {
                  media.muted = true;
                  report(media.currentSrc || media.src);
                  media.querySelectorAll('source').forEach(s => report(s.src));
                  if (media.paused) { const p = media.play(); if (p) p.catch(() => {}); }
                });
                // Only activate known video-player controls, never arbitrary page links.
                document.querySelectorAll('.vjs-big-play-button,.jw-icon-display,.plyr__control--overlaid,[data-plyr="play"]').forEach(b => {
                  if (!b.dataset.streamClicked) { b.dataset.streamClicked = '1'; b.click(); }
                });
              };
              document.addEventListener('DOMContentLoaded', scan);
              setInterval(scan, 1000);
            })();
        """.trimIndent()
    }
}
