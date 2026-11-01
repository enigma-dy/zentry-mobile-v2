package com.zentry.predict

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var streamBrowser: StreamBrowser? = null
    private var providerPlayers: ProviderPlayerFactory? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        streamBrowser = StreamBrowser(this)
        providerPlayers = ProviderPlayerFactory(this, flutterEngine.dartExecutor.binaryMessenger).also {
            flutterEngine.platformViewsController.registry.registerViewFactory("provider_player", it)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stream_browser")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "resolve" -> streamBrowser!!.resolve(call.argument<String>("url"), result, call.argument<String>("referer"))
                    "handoff" -> {
                        streamBrowser?.handoff()
                        result.success(null)
                    }
                    "cancel" -> {
                        streamBrowser?.cancel()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onStop() {
        streamBrowser?.cancel()
        providerPlayers?.pauseAll()
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        providerPlayers?.resumeAll()
    }

    override fun onDestroy() {
        streamBrowser?.cancel()
        providerPlayers?.disposeAll()
        providerPlayers = null
        streamBrowser = null
        super.onDestroy()
    }
}
