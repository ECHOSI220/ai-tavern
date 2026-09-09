package com.imaginary.tavern.ai_tavern

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var nearbyBridge: NearbyConnectionsBridge
    private lateinit var wifiDirectBridge: WifiDirectConnectionsBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
