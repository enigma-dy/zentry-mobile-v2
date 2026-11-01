package com.zentry.predict

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream

class ProviderPlayerFactory(private val activity: Activity, private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private val players = mutableSetOf<ProviderPlayerView>()

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val values = args as? Map<*, *> ?: emptyMap<Any, Any>()
        val player = ProviderPlayerView(activity, messenger, viewId, values) { players.remove(it) }
        players.add(player)
        return player
    }

    fun pauseAll() = players.toList().forEach { it.pause() }
    fun resumeAll() = players.toList().forEach { it.resume() }
    fun disposeAll() = players.toList().forEach { it.dispose() }
}

/** Runs the provider's media loader unchanged, including its segment transforms. */
@SuppressLint("SetJavaScriptEnabled")
private class ProviderPlayerView(
    private val activity: Activity,
    messenger: BinaryMessenger,
    id: Int,
    args: Map<*, *>,
    private val onDispose: (ProviderPlayerView) -> Unit,
) : PlatformView {
    private val container = FrameLayout(activity)
    private val webView = WebView(activity)
    private val channel = MethodChannel(messenger, "provider_player/$id")
    private var disposed = false
    private var started = false
    private var documentFailed = false
    private val playbackScript = activity.assets.open("provider_player.js").bufferedReader().use { it.readText() }

    init {
        container.setBackgroundColor(Color.BLACK)
        container.addView(webView, FrameLayout.LayoutParams(-1, -1))
        webView.setBackgroundColor(Color.BLACK)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            allowFileAccess = false
            allowContentAccess = false
            setSupportMultipleWindows(true)
            javaScriptCanOpenWindowsAutomatically = false
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
        }
        android.webkit.CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        webView.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                if (message.message() == "__PROVIDER_PLAYER_PLAYING__") {
                    if (!disposed) channel.invokeMethod("playing", null)
                    return true
                }
                if (message.message() == "__PROVIDER_PLAYER_ERROR__") {
                    if (!disposed) channel.invokeMethod("error", null)
                    return true
                }
                return false
            }

            override fun onCreateWindow(view: WebView?, dialog: Boolean, gesture: Boolean, message: android.os.Message?) = false

            override fun onShowCustomView(view: View, callback: WebChromeClient.CustomViewCallback) {
                // Keep Flutter's server selector visible in fullscreen.
                callback.onCustomViewHidden()
                if (!disposed) channel.invokeMethod("fullscreen", null)
            }

        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                if (isAdRequest(request.url)) {
                    return WebResourceResponse("text/plain", "UTF-8", 204, "No Content",
                        emptyMap(), ByteArrayInputStream(ByteArray(0)))
                }
                return null
            }
            override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
                documentFailed = false
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (request.url.scheme !in listOf("http", "https")) return true
                return request.isForMainFrame && !isProviderEmbed(request.url)
            }

            override fun onPageFinished(view: WebView, url: String) {
                if (!disposed && !documentFailed) {
                    view.evaluateJavascript(playbackScript, null)
                    channel.invokeMethod("ready", null)
                }
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame && !disposed) {
                    documentFailed = true
                    channel.invokeMethod("error", null)
                }
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (request.isForMainFrame && response.statusCode >= 400 && !disposed) {
                    documentFailed = true
                    channel.invokeMethod("error", null)
                }
            }
        }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(webView, playbackScript, setOf("*"))
        }
        val url = Uri.parse(args["url"]?.toString() ?: "")
        // Flutter installs its event handler before asking the embed to start.
        channel.setMethodCallHandler { call, result ->
            if (call.method != "start") {
                result.notImplemented()
            } else {
                if (!started && !disposed) {
                    started = true
                    if (isProviderEmbed(url)) {
                        val headers = mutableMapOf<String, String>()
                        val referer = args["referer"]?.toString()
                        if (referer != null && Uri.parse(referer).scheme in listOf("http", "https")) headers["Referer"] = referer
                        webView.loadUrl(url.toString(), headers)
                    } else {
                        webView.post { if (!disposed) channel.invokeMethod("error", null) }
                    }
                }
                result.success(null)
            }
        }
    }

    fun pause() {
        if (disposed) return
        webView.evaluateJavascript("window.postMessage({providerPlayerPause:true}, '*');", null)
        webView.onPause()
    }

    fun resume() { if (!disposed) webView.onResume() }

    override fun getView(): View = container

    override fun dispose() {
        if (disposed) return
        pause()
        disposed = true
        channel.setMethodCallHandler(null)
        webView.stopLoading()
        container.removeAllViews()
        webView.webChromeClient = null
        webView.destroy()
        onDispose(this)
    }

    companion object {
        private fun isProviderEmbed(url: Uri): Boolean = url.scheme in listOf("http", "https") &&
            url.host?.lowercase() in listOf("90minutes.pro", "www.90minutes.pro") &&
            (url.path == "/embed" || url.path.orEmpty().startsWith("/embed/") ||
             url.path == "/player/hls" || url.path.orEmpty().startsWith("/player/hls/"))

        private fun isAdRequest(url: Uri): Boolean {
            val host = url.host?.lowercase() ?: return false
            // Hosts observed in the supplied provider HAR. Do not match arbitrary
            // "ad" substrings: that could block media CDNs or token requests.
            val adHosts = setOf("llvpn.com", "luugy.com", "92mim.com", "vr-gc.com")
            if (adHosts.any { host == it || host.endsWith(".$it") }) return true
            return host in setOf("90minutes.pro", "www.90minutes.pro") &&
                url.path in setOf("/papi/mtg.js", "/js/adgeo.js")
        }
    }
}
