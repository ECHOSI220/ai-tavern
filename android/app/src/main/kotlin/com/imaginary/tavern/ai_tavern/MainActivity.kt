package com.imaginary.tavern.ai_tavern

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.ProxySelector
import java.net.Proxy
import java.net.URI
import java.net.InetSocketAddress

class MainActivity : FlutterActivity() {
    private lateinit var nearbyBridge: NearbyConnectionsBridge
    private lateinit var wifiDirectBridge: WifiDirectConnectionsBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai_tavern/network")
            .setMethodCallHandler { call, result ->
                if (call.method != "proxyForUrl") {
                    result.notImplemented()
                } else {
                    val url = call.argument<String>("url") ?: ""
                    Thread {
                        try {
                            val routes = ProxySelector.getDefault()?.select(URI(url)) ?: listOf(Proxy.NO_PROXY)
                            val route = routes.mapNotNull { proxy ->
                                if (proxy.type() == Proxy.Type.DIRECT) "DIRECT"
                                else if (proxy.type() == Proxy.Type.HTTP) {
                                    val address = proxy.address() as InetSocketAddress
                                    "PROXY ${address.hostString}:${address.port}"
                                } else null
                            }.joinToString("; ")
                            runOnUiThread {
                                if (route.isEmpty()) result.error("PROXY_UNSUPPORTED", "Unsupported system proxy", null)
                                else result.success(route)
                            }
                        } catch (_: Exception) {
                            runOnUiThread { result.error("PROXY_LOOKUP_FAILED", "Cannot read system proxy", null) }
                        }
                    }.start()
                }
            }
        nearbyBridge = NearbyConnectionsBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        wifiDirectBridge = WifiDirectConnectionsBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (::nearbyBridge.isInitialized &&
            nearbyBridge.onRequestPermissionsResult(requestCode, permissions, grantResults)) {
            return
        }
        if (::wifiDirectBridge.isInitialized &&
            wifiDirectBridge.onRequestPermissionsResult(requestCode, permissions, grantResults)) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        if (::nearbyBridge.isInitialized) nearbyBridge.detach()
        if (::wifiDirectBridge.isInitialized) wifiDirectBridge.detach()
        super.onDestroy()
    }
}
