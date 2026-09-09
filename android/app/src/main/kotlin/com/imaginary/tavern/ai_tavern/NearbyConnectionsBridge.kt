package com.imaginary.tavern.ai_tavern

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap

/** Thin platform bridge. Room rules and authoritative state remain in Dart. */
class NearbyConnectionsBridge(
    private val activity: Activity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "ai_tavern/nearby_connections"
        private const val EVENT_CHANNEL = "ai_tavern/nearby_connections_events"
        private const val SERVICE_ID = "com.imaginary.tavern.ai_tavern.trpg.nearby.v1"
        private const val PERMISSION_REQUEST = 7319
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val client: ConnectionsClient = Nearby.getConnectionsClient(activity)
    private val pendingNames = ConcurrentHashMap<String, String>()
    private val connectedEndpoints = ConcurrentHashMap.newKeySet<String>()
    private var eventSink: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(supportState())
            "permissionState" -> result.success(permissionState())
            "requestPermissions" -> requestPermissions(result)
            "openSettings" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
                activity.startActivity(intent)
                result.success(null)
            }
            "startAdvertising" -> startAdvertising(call, result)
            "stopAdvertising" -> {
                client.stopAdvertising()
                stopHostService()
                emit("status", mapOf("status" to "idle", "role" to "host"))
                result.success(null)
            }
            "startDiscovery" -> startDiscovery(result)
            "stopDiscovery" -> {
                client.stopDiscovery()
                emit("status", mapOf("status" to "idle", "role" to "client"))
                result.success(null)
            }
            "requestConnection" -> requestConnection(call, result)
            "acceptConnection" -> acceptConnection(call, result)
            "rejectConnection" -> rejectConnection(call, result)
            "sendBytes" -> sendBytes(call, result)
            "sendFile" -> sendFile(call, result)
            "disconnectEndpoint" -> {
                val endpointId = call.argument<String>("endpointId") ?: ""
                client.disconnectFromEndpoint(endpointId)
                connectedEndpoints.remove(endpointId)
                result.success(null)
            }
            "disconnectAll" -> {
                client.stopAdvertising()
                client.stopDiscovery()
                client.stopAllEndpoints()
                connectedEndpoints.clear()
                stopHostService()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun supportState(): Map<String, Any?> {
        val code = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(activity)
        return mapOf(
            "platformSupported" to true,
            "playServicesAvailable" to (code == ConnectionResult.SUCCESS),
            "playServicesCode" to code,
            "sdkInt" to Build.VERSION.SDK_INT,
            "backend" to "googleNearby"
        )
    }

    private fun requiredPermissions(): List<String> = when {
        Build.VERSION.SDK_INT >= 33 -> listOf(
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.NEARBY_WIFI_DEVICES
        )
        Build.VERSION.SDK_INT >= 31 -> listOf(
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN
        )
        Build.VERSION.SDK_INT >= 29 -> listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        Build.VERSION.SDK_INT >= 23 -> listOf(Manifest.permission.ACCESS_COARSE_LOCATION)
        else -> emptyList()
    }

    private fun permissionState(): Map<String, Any?> {
        val missing = requiredPermissions().filter {
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }
        val permanentlyDenied = missing.any {
            !ActivityCompat.shouldShowRequestPermissionRationale(activity, it)
        }
        return mapOf(
            "granted" to missing.isEmpty(),
            "missing" to missing,
            "showRationale" to missing.any {
                ActivityCompat.shouldShowRequestPermissionRationale(activity, it)
            },
            "mayNeedSettings" to permanentlyDenied
        )
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val missing = requiredPermissions().filter {
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(permissionState())
            return
        }
        if (permissionResult != null) {
            result.error("permission_in_progress", "权限请求正在进行", null)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), PERMISSION_REQUEST)
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        permissionResult?.success(permissionState())
        permissionResult = null
        return true
    }

    private val lifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            pendingNames[endpointId] = info.endpointName
            emit("verificationRequired", mapOf(
                "endpointId" to endpointId,
                "endpointName" to info.endpointName,
                "authenticationDigits" to info.authenticationDigits,
                "incoming" to info.isIncomingConnection
            ))
        }

        override fun onConnectionResult(endpointId: String, resolution: ConnectionResolution) {
            if (resolution.status.statusCode == ConnectionsStatusCodes.STATUS_OK) {
                connectedEndpoints.add(endpointId)
                emit("connected", mapOf(
                    "endpointId" to endpointId,
                    "endpointName" to (pendingNames[endpointId] ?: endpointId)
                ))
            } else {
                emit("connectionFailed", mapOf(
                    "endpointId" to endpointId,
                    "statusCode" to resolution.status.statusCode,
                    "message" to (resolution.status.statusMessage ?: "连接被拒绝或失败")
                ))
            }
        }

        override fun onDisconnected(endpointId: String) {
            connectedEndpoints.remove(endpointId)
            emit("disconnected", mapOf("endpointId" to endpointId))
        }
    }

    private val discoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            if (info.serviceId != SERVICE_ID) return
            pendingNames[endpointId] = info.endpointName
            emit("endpointFound", mapOf(
                "endpointId" to endpointId,
                "endpointName" to info.endpointName
            ))
        }

        override fun onEndpointLost(endpointId: String) {
            pendingNames.remove(endpointId)
            emit("endpointLost", mapOf("endpointId" to endpointId))
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            when (payload.type) {
                Payload.Type.BYTES -> emit("bytesReceived", mapOf(
                    "endpointId" to endpointId,
                    "payloadId" to payload.id,
                    "bytes" to payload.asBytes()
                ))
                Payload.Type.FILE -> emit("fileReceived", mapOf(
                    "endpointId" to endpointId,
                    "payloadId" to payload.id,
                    "uri" to payload.asFile()?.asUri()?.toString()
                ))
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            emit("transferUpdate", mapOf(
                "endpointId" to endpointId,
                "payloadId" to update.payloadId,
                "status" to update.status,
                "bytesTransferred" to update.bytesTransferred,
                "totalBytes" to update.totalBytes
            ))
        }
    }

    private fun startAdvertising(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureReady(result)) return
        val endpointName = call.argument<String>("endpointName")?.take(120) ?: "AI Tavern"
        client.startAdvertising(
            endpointName,
            SERVICE_ID,
            lifecycleCallback,
            AdvertisingOptions.Builder().setStrategy(Strategy.P2P_STAR).build()
        ).addOnSuccessListener {
            startHostService(call.argument<String>("roomName") ?: endpointName)
            emit("status", mapOf("status" to "advertising", "role" to "host"))
            result.success(null)
        }.addOnFailureListener { fail(result, "advertising_failed", it) }
    }

    private fun startDiscovery(result: MethodChannel.Result) {
        if (!ensureReady(result)) return
        client.startDiscovery(
            SERVICE_ID,
            discoveryCallback,
            DiscoveryOptions.Builder().setStrategy(Strategy.P2P_STAR).build()
        ).addOnSuccessListener {
            emit("status", mapOf("status" to "discovering", "role" to "client"))
            result.success(null)
        }.addOnFailureListener { fail(result, "discovery_failed", it) }
    }

    private fun requestConnection(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureReady(result)) return
        val endpointId = call.argument<String>("endpointId") ?: return result.error(
            "invalid_endpoint", "缺少 endpointId", null
        )
        val playerName = call.argument<String>("playerName")?.take(120) ?: "玩家"
        client.requestConnection(playerName, endpointId, lifecycleCallback)
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { fail(result, "connection_request_failed", it) }
    }

    private fun acceptConnection(call: MethodCall, result: MethodChannel.Result) {
        val endpointId = call.argument<String>("endpointId") ?: return result.error(
            "invalid_endpoint", "缺少 endpointId", null
        )
        client.acceptConnection(endpointId, payloadCallback)
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { fail(result, "accept_failed", it) }
    }

    private fun rejectConnection(call: MethodCall, result: MethodChannel.Result) {
        val endpointId = call.argument<String>("endpointId") ?: return result.error(
            "invalid_endpoint", "缺少 endpointId", null
        )
        client.rejectConnection(endpointId)
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { fail(result, "reject_failed", it) }
    }

    private fun sendBytes(call: MethodCall, result: MethodChannel.Result) {
        val endpointId = call.argument<String>("endpointId") ?: return result.error(
            "invalid_endpoint", "缺少 endpointId", null
        )
        val bytes = call.argument<ByteArray>("bytes") ?: return result.error(
            "invalid_payload", "缺少 bytes", null
        )
        client.sendPayload(endpointId, Payload.fromBytes(bytes))
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { fail(result, "send_failed", it) }
    }

    private fun sendFile(call: MethodCall, result: MethodChannel.Result) {
        val endpointId = call.argument<String>("endpointId") ?: return result.error(
            "invalid_endpoint", "缺少 endpointId", null
        )
        val path = call.argument<String>("path") ?: return result.error(
            "invalid_file", "缺少文件路径", null
        )
        try {
            val payload = Payload.fromFile(File(path))
            client.sendPayload(endpointId, payload)
                .addOnSuccessListener { result.success(payload.id) }
                .addOnFailureListener { fail(result, "file_send_failed", it) }
        } catch (error: Throwable) {
            result.error("invalid_file", error.message, null)
        }
    }

    private fun ensureReady(result: MethodChannel.Result): Boolean {
        val support = supportState()
        if (support["playServicesAvailable"] != true) {
            result.error("play_services_unavailable", "Google Play 服务不可用或版本过低", support)
            return false
        }
        if (permissionState()["granted"] != true) {
            result.error("missing_permissions", "附近设备权限尚未授权", permissionState())
            return false
        }
        return true
    }

    private fun fail(result: MethodChannel.Result, code: String, error: Exception) {
        emit("error", mapOf("code" to code, "message" to (error.message ?: code)))
        result.error(code, error.message, null)
    }

    private fun emit(type: String, data: Map<String, Any?> = emptyMap()) {
        activity.runOnUiThread { eventSink?.success(mapOf("type" to type, "data" to data)) }
    }

    private fun startHostService(roomName: String) {
        val intent = Intent(activity, NearbyHostForegroundService::class.java)
            .putExtra("roomName", roomName)
        ContextCompat.startForegroundService(activity, intent)
    }

    private fun stopHostService() {
        activity.stopService(Intent(activity, NearbyHostForegroundService::class.java))
    }

    fun detach() {
        client.stopAdvertising()
        client.stopDiscovery()
        client.stopAllEndpoints()
        stopHostService()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        permissionResult = null
    }
}
