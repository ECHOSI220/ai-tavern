package com.imaginary.tavern.ai_tavern

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.NetworkInfo
import android.net.Uri
import android.net.wifi.WpsInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Build
import android.provider.Settings
import android.util.Base64
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Google-free proximity backend based only on Android's WifiP2pManager.
 * It mirrors the event/method contract of NearbyConnectionsBridge so the
 * existing authoritative multiplayer core remains unchanged.
 */
class WifiDirectConnectionsBridge(
    private val activity: Activity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "ai_tavern/wifi_direct"
        private const val EVENT_CHANNEL = "ai_tavern/wifi_direct_events"
        private const val PERMISSION_REQUEST = 7320
        private const val SERVICE_INSTANCE = "AITavernTRPG"
        private const val SERVICE_TYPE = "_aitavern._tcp"
        private const val SOCKET_PORT = 43821
        private const val MAX_FRAME_BYTES = 2 * 1024 * 1024
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val wifiManager = activity.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
    private val channel = wifiManager?.initialize(activity, activity.mainLooper) {
        emit("error", mapOf("code" to "channel_disconnected", "message" to "Wi-Fi Direct 通道已断开"))
    }
    private val executor = Executors.newCachedThreadPool()
    private val discoveredDevices = ConcurrentHashMap<String, WifiP2pDevice>()
    private val links = ConcurrentHashMap<String, PeerLink>()
    private var eventSink: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null
    private var receiverRegistered = false
    private var serverSocket: ServerSocket? = null
    private var advertising = false
    private var discovering = false
    private var localEndpointName = "AI Tavern"
    private var targetEndpointId: String? = null
    private val localEndpointId: String by lazy {
        val raw = Settings.Secure.getString(activity.contentResolver, Settings.Secure.ANDROID_ID)
            ?: UUID.randomUUID().toString()
        "wd-${raw.takeLast(16)}"
    }

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
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${activity.packageName}")
                })
                result.success(null)
            }
            "startAdvertising" -> startAdvertising(call, result)
            "stopAdvertising" -> {
                stopAdvertisingInternal()
                result.success(null)
            }
            "startDiscovery" -> startDiscovery(result)
            "stopDiscovery" -> {
                stopDiscoveryInternal()
                result.success(null)
            }
            "requestConnection" -> requestConnection(call, result)
            "acceptConnection" -> acceptConnection(call, result)
            "rejectConnection" -> rejectConnection(call, result)
            "sendBytes" -> sendBytes(call, result)
            "sendFile" -> result.error(
                "file_not_supported",
                "无 GMS 模式暂不直接发送文件；剧情状态和文本可正常同步",
                null
            )
            "disconnectEndpoint" -> {
                val endpointId = call.argument<String>("endpointId") ?: ""
                closeLink(endpointId, true)
                result.success(null)
            }
            "disconnectAll" -> {
                disconnectAllInternal()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun supportState(): Map<String, Any?> {
        val supported = wifiManager != null && channel != null &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)
        return mapOf(
            "platformSupported" to supported,
            "playServicesAvailable" to supported,
            "playServicesCode" to 0,
            "sdkInt" to Build.VERSION.SDK_INT,
            "backend" to "wifiDirect"
        )
    }

    private fun requiredPermissions(): List<String> = when {
        Build.VERSION.SDK_INT >= 33 -> listOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        Build.VERSION.SDK_INT >= 23 -> listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        else -> emptyList()
    }

    private fun permissionState(): Map<String, Any?> {
        val missing = requiredPermissions().filter {
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }
        return mapOf(
            "granted" to missing.isEmpty(),
            "missing" to missing,
            "showRationale" to missing.any {
                ActivityCompat.shouldShowRequestPermissionRationale(activity, it)
            },
            "mayNeedSettings" to missing.any {
                !ActivityCompat.shouldShowRequestPermissionRationale(activity, it)
            }
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

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                    if (state != WifiP2pManager.WIFI_P2P_STATE_ENABLED) {
                        emit("error", mapOf(
                            "code" to "wifi_direct_disabled",
                            "message" to "请先打开 Wi-Fi，Wi-Fi Direct 不要求连接路由器"
                        ))
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    @Suppress("DEPRECATION")
                    val network = intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
                    if (network?.isConnected == true) requestConnectionInfo()
                    else if (links.isNotEmpty()) closeAllLinks(true)
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> requestPeers()
            }
        }
    }

    private fun registerReceiverIfNeeded() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            activity.registerReceiver(receiver, filter)
        }
        receiverRegistered = true
    }

    private fun startAdvertising(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureReady(result)) return
        val manager = wifiManager ?: return result.error("unsupported", "设备不支持 Wi-Fi Direct", null)
        val p2pChannel = channel ?: return result.error("unsupported", "Wi-Fi Direct 初始化失败", null)
        registerReceiverIfNeeded()
        localEndpointName = call.argument<String>("endpointName") ?: "AI Tavern"
        val txt = mapOf(
            "protocol" to "AIT1",
            "endpointName" to localEndpointName,
            "port" to SOCKET_PORT.toString()
        )
        val service = WifiP2pDnsSdServiceInfo.newInstance(
            SERVICE_INSTANCE,
            SERVICE_TYPE,
            txt
        )
        manager.clearLocalServices(p2pChannel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = addServiceAndGroup(manager, p2pChannel, service, call, result)
            override fun onFailure(reason: Int) =
                addServiceAndGroup(manager, p2pChannel, service, call, result)
        })
    }

    private fun addServiceAndGroup(
        manager: WifiP2pManager,
        p2pChannel: WifiP2pManager.Channel,
        service: WifiP2pDnsSdServiceInfo,
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        manager.addLocalService(p2pChannel, service, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                manager.removeGroup(p2pChannel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() = createHostGroup(manager, p2pChannel, call, result)
                    override fun onFailure(reason: Int) = createHostGroup(manager, p2pChannel, call, result)
                })
            }
            override fun onFailure(reason: Int) = result.error(
                "advertising_failed",
                "Wi-Fi Direct 服务广播失败（$reason）",
                null
            )
        })
    }

    private fun createHostGroup(
        manager: WifiP2pManager,
        p2pChannel: WifiP2pManager.Channel,
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        manager.createGroup(p2pChannel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = advertisingStarted(call, result)
            override fun onFailure(reason: Int) {
                if (reason == WifiP2pManager.BUSY) advertisingStarted(call, result)
                else result.error(
                    "advertising_failed",
                    "无法创建 Wi-Fi Direct 房主组（$reason）",
                    null
                )
            }
        })
    }

    private fun advertisingStarted(call: MethodCall, result: MethodChannel.Result) {
        advertising = true
        requestConnectionInfo()
        startHostService(call.argument<String>("roomName") ?: "附近跑团")
        emit("status", mapOf(
            "status" to "advertising",
            "role" to "host",
            "backend" to "wifiDirect"
        ))
        result.success(null)
    }

    private fun startDiscovery(result: MethodChannel.Result) {
        if (!ensureReady(result)) return
        val manager = wifiManager ?: return result.error("unsupported", "设备不支持 Wi-Fi Direct", null)
        val p2pChannel = channel ?: return result.error("unsupported", "Wi-Fi Direct 初始化失败", null)
        registerReceiverIfNeeded()
        discoveredDevices.clear()
        manager.setDnsSdResponseListeners(
            p2pChannel,
            WifiP2pManager.DnsSdServiceResponseListener { _, _, device ->
                discoveredDevices[device.deviceAddress] = device
            },
            WifiP2pManager.DnsSdTxtRecordListener { _, record, device ->
                if (record["protocol"] != "AIT1") return@DnsSdTxtRecordListener
                discoveredDevices[device.deviceAddress] = device
                emit("endpointFound", mapOf(
                    "endpointId" to device.deviceAddress,
                    "endpointName" to (record["endpointName"] ?: device.deviceName),
                    "backend" to "wifiDirect"
                ))
            }
        )
        val request = WifiP2pDnsSdServiceRequest.newInstance()
        manager.clearServiceRequests(p2pChannel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = addServiceRequest(manager, p2pChannel, request, result)
            override fun onFailure(reason: Int) = addServiceRequest(manager, p2pChannel, request, result)
        })
    }

    private fun addServiceRequest(
        manager: WifiP2pManager,
        p2pChannel: WifiP2pManager.Channel,
        request: WifiP2pDnsSdServiceRequest,
        result: MethodChannel.Result
    ) {
        manager.addServiceRequest(p2pChannel, request, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                manager.discoverServices(p2pChannel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        discovering = true
                        emit("status", mapOf(
                            "status" to "discovering",
                            "role" to "client",
                            "backend" to "wifiDirect"
                        ))
                        result.success(null)
                    }
                    override fun onFailure(reason: Int) = result.error(
                        "discovery_failed",
                        "Wi-Fi Direct 搜索失败（$reason），请确认 Wi-Fi 和位置信息开关已开启",
                        null
                    )
                })
            }
            override fun onFailure(reason: Int) = result.error(
                "discovery_failed",
                "无法注册 Wi-Fi Direct 搜索（$reason）",
                null
            )
        })
    }

    private fun requestConnection(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureReady(result)) return
        val endpointId = call.argument<String>("endpointId") ?: return result.error(
            "invalid_endpoint", "缺少 endpointId", null
        )
        localEndpointName = call.argument<String>("playerName") ?: "玩家"
        targetEndpointId = endpointId
        val config = WifiP2pConfig().apply {
            deviceAddress = endpointId
            wps.setup = WpsInfo.PBC
            groupOwnerIntent = 0
        }
        wifiManager?.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                emit("status", mapOf(
                    "status" to "connecting",
                    "role" to "client",
                    "backend" to "wifiDirect"
                ))
                result.success(null)
            }
            override fun onFailure(reason: Int) = result.error(
                "connection_request_failed",
                "Wi-Fi Direct 连接请求失败（$reason）",
                null
            )
        })
    }

    private fun requestConnectionInfo() {
        val manager = wifiManager ?: return
        val p2pChannel = channel ?: return
        try {
            manager.requestConnectionInfo(p2pChannel) { info ->
                if (!info.groupFormed) return@requestConnectionInfo
                if (info.isGroupOwner) startSocketServer()
                else info.groupOwnerAddress?.let { connectToHost(it.hostAddress) }
            }
        } catch (error: SecurityException) {
            emit("error", mapOf("code" to "missing_permission", "message" to error.message))
        }
    }

    private fun requestPeers() {
        val manager = wifiManager ?: return
        val p2pChannel = channel ?: return
        try {
            manager.requestPeers(p2pChannel) { peers ->
                peers.deviceList.forEach { discoveredDevices[it.deviceAddress] = it }
            }
        } catch (_: SecurityException) {
        }
    }

    private fun startSocketServer() {
        if (serverSocket?.isClosed == false) return
        executor.execute {
            try {
                val server = ServerSocket(SOCKET_PORT)
                server.reuseAddress = true
                serverSocket = server
                while (!server.isClosed) {
                    val socket = server.accept()
                    socket.tcpNoDelay = true
                    val provisional = "pending-${UUID.randomUUID()}"
                    val link = PeerLink(provisional, socket, true)
                    links[provisional] = link
                    startReader(link)
                    sendHello(link)
                }
            } catch (error: Throwable) {
                if (advertising) emit("error", mapOf(
                    "code" to "socket_server_failed",
                    "message" to "Wi-Fi Direct 数据通道启动失败：${error.message}"
                ))
            }
        }
    }

    private fun connectToHost(hostAddress: String) {
        val endpointId = targetEndpointId ?: return
        if (links.containsKey(endpointId)) return
        executor.execute {
            var lastError: Throwable? = null
            repeat(20) {
                try {
                    val socket = Socket()
                    socket.connect(InetSocketAddress(hostAddress, SOCKET_PORT), 1500)
                    socket.tcpNoDelay = true
                    val link = PeerLink(endpointId, socket, false)
                    links[endpointId] = link
                    startReader(link)
                    sendHello(link)
                    return@execute
                } catch (error: Throwable) {
                    lastError = error
                    Thread.sleep(500)
                }
            }
            emit("connectionFailed", mapOf(
                "endpointId" to endpointId,
                "message" to "无法连接房主数据通道：${lastError?.message}"
            ))
        }
    }

    private fun startReader(link: PeerLink) {
        executor.execute {
            try {
                while (!link.closed.get()) {
                    val size = link.input.readInt()
                    if (size <= 0 || size > MAX_FRAME_BYTES) throw IllegalArgumentException("invalid frame size")
                    val bytes = ByteArray(size)
                    link.input.readFully(bytes)
                    handleFrame(link, JSONObject(String(bytes, Charsets.UTF_8)))
                }
            } catch (_: Throwable) {
                closeLink(link.endpointId, true)
            }
        }
    }

    private fun sendHello(link: PeerLink) {
        sendControl(link, JSONObject().apply {
            put("kind", "hello")
            put("endpointId", localEndpointId)
            put("endpointName", localEndpointName)
            put("nonce", link.localNonce)
        })
    }

    private fun handleFrame(link: PeerLink, frame: JSONObject) {
        when (frame.optString("kind")) {
            "hello" -> {
                val reportedId = frame.optString("endpointId")
                link.remoteName = frame.optString("endpointName", "附近设备")
                link.remoteNonce = frame.optString("nonce")
                val oldId = link.endpointId
                val stableId = if (link.hostSide) reportedId else (targetEndpointId ?: reportedId)
                if (stableId.isNotBlank() && stableId != oldId) {
                    links.remove(oldId)
                    link.endpointId = stableId
                    links[stableId] = link
                }
                maybeRequestVerification(link)
            }
            "accept" -> {
                link.remoteAccepted = true
                maybeEmitConnected(link)
            }
            "reject" -> {
                emit("connectionFailed", mapOf(
                    "endpointId" to link.endpointId,
                    "message" to "对方拒绝了连接"
                ))
                closeLink(link.endpointId, false)
            }
            "data" -> {
                if (!link.connectedEmitted.get()) return
                val payload = Base64.decode(frame.optString("data"), Base64.NO_WRAP)
                emit("bytesReceived", mapOf(
                    "endpointId" to link.endpointId,
                    "payloadId" to frame.optLong("payloadId"),
                    "bytes" to payload
                ))
            }
        }
    }

    private fun maybeRequestVerification(link: PeerLink) {
        val remoteNonce = link.remoteNonce ?: return
        if (!link.verificationEmitted.compareAndSet(false, true)) return
        val joined = listOf(link.localNonce, remoteNonce).sorted().joinToString(":")
        val digest = MessageDigest.getInstance("SHA-256").digest(joined.toByteArray())
        val number = ((digest[0].toInt() and 0xff) shl 16) or
            ((digest[1].toInt() and 0xff) shl 8) or
            (digest[2].toInt() and 0xff)
        val digits = (number % 1_000_000).toString().padStart(6, '0')
        emit("verificationRequired", mapOf(
            "endpointId" to link.endpointId,
            "endpointName" to link.remoteName,
            "authenticationDigits" to digits,
            "incoming" to link.hostSide,
            "backend" to "wifiDirect"
        ))
    }

    private fun acceptConnection(call: MethodCall, result: MethodChannel.Result) {
        val endpointId = call.argument<String>("endpointId") ?: return result.error(
            "invalid_endpoint", "缺少 endpointId", null
        )
        val link = links[endpointId] ?: return result.error(
            "endpoint_unknown", "连接已失效，请重新搜索", null
        )
        link.localAccepted = true
        sendControl(link, JSONObject().put("kind", "accept"))
        maybeEmitConnected(link)
        result.success(null)
    }

    private fun rejectConnection(call: MethodCall, result: MethodChannel.Result) {
        val endpointId = call.argument<String>("endpointId") ?: return result.error(
            "invalid_endpoint", "缺少 endpointId", null
        )
        links[endpointId]?.let { sendControl(it, JSONObject().put("kind", "reject")) }
        closeLink(endpointId, false)
        result.success(null)
    }

    private fun maybeEmitConnected(link: PeerLink) {
        if (!link.localAccepted || !link.remoteAccepted) return
        if (!link.connectedEmitted.compareAndSet(false, true)) return
        emit("connected", mapOf(
            "endpointId" to link.endpointId,
            "endpointName" to link.remoteName,
            "backend" to "wifiDirect"
        ))
    }

    private fun sendBytes(call: MethodCall, result: MethodChannel.Result) {
        val endpointId = call.argument<String>("endpointId") ?: return result.error(
            "invalid_endpoint", "缺少 endpointId", null
        )
        val bytes = call.argument<ByteArray>("bytes") ?: return result.error(
            "invalid_payload", "缺少 bytes", null
        )
        val link = links[endpointId]
        if (link == null || !link.connectedEmitted.get()) {
            result.error("endpoint_unknown", "Wi-Fi Direct 连接已断开", null)
            return
        }
        try {
            sendControl(link, JSONObject().apply {
                put("kind", "data")
                put("payloadId", System.nanoTime())
                put("data", Base64.encodeToString(bytes, Base64.NO_WRAP))
            })
            result.success(null)
        } catch (error: Throwable) {
            result.error("send_failed", error.message, null)
        }
    }

    private fun sendControl(link: PeerLink, json: JSONObject) {
        val bytes = json.toString().toByteArray(Charsets.UTF_8)
        synchronized(link.output) {
            link.output.writeInt(bytes.size)
            link.output.write(bytes)
            link.output.flush()
        }
    }

    private fun closeLink(endpointId: String, notify: Boolean) {
        val link = links.remove(endpointId) ?: return
        if (!link.closed.compareAndSet(false, true)) return
        links.entries.removeIf { it.value === link }
        try { link.socket.close() } catch (_: Throwable) {}
        if (notify && link.connectedEmitted.get()) {
            emit("disconnected", mapOf("endpointId" to endpointId, "backend" to "wifiDirect"))
        }
    }

    private fun closeAllLinks(notify: Boolean) {
        links.keys.toList().forEach { closeLink(it, notify) }
    }

    private fun stopAdvertisingInternal() {
        advertising = false
        try { serverSocket?.close() } catch (_: Throwable) {}
        serverSocket = null
        closeAllLinks(true)
        wifiManager?.clearLocalServices(channel, null)
        wifiManager?.removeGroup(channel, null)
        stopHostService()
        emit("status", mapOf("status" to "idle", "role" to "host", "backend" to "wifiDirect"))
    }

    private fun stopDiscoveryInternal() {
        discovering = false
        wifiManager?.stopPeerDiscovery(channel, null)
        wifiManager?.clearServiceRequests(channel, null)
        emit("status", mapOf("status" to "idle", "role" to "client", "backend" to "wifiDirect"))
    }

    private fun disconnectAllInternal() {
        advertising = false
        discovering = false
        try { serverSocket?.close() } catch (_: Throwable) {}
        serverSocket = null
        closeAllLinks(false)
        wifiManager?.stopPeerDiscovery(channel, null)
        wifiManager?.clearServiceRequests(channel, null)
        wifiManager?.clearLocalServices(channel, null)
        wifiManager?.removeGroup(channel, null)
        stopHostService()
    }

    private fun ensureReady(result: MethodChannel.Result): Boolean {
        if (supportState()["playServicesAvailable"] != true) {
            result.error("unsupported", "此手机硬件或系统不支持 Wi-Fi Direct", supportState())
            return false
        }
        if (permissionState()["granted"] != true) {
            result.error("missing_permissions", "Wi-Fi Direct 权限尚未授权", permissionState())
            return false
        }
        return true
    }

    private fun emit(type: String, data: Map<String, Any?> = emptyMap()) {
        activity.runOnUiThread { eventSink?.success(mapOf("type" to type, "data" to data)) }
    }

    private fun startHostService(roomName: String) {
        ContextCompat.startForegroundService(
            activity,
            Intent(activity, NearbyHostForegroundService::class.java)
                .putExtra("roomName", "$roomName · 无 GMS Wi-Fi Direct")
        )
    }

    private fun stopHostService() {
        activity.stopService(Intent(activity, NearbyHostForegroundService::class.java))
    }

    fun detach() {
        disconnectAllInternal()
        if (receiverRegistered) {
            try { activity.unregisterReceiver(receiver) } catch (_: Throwable) {}
            receiverRegistered = false
        }
        executor.shutdownNow()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        permissionResult = null
    }

    private class PeerLink(
        @Volatile var endpointId: String,
        val socket: Socket,
        val hostSide: Boolean
    ) {
        val input = DataInputStream(BufferedInputStream(socket.getInputStream()))
        val output = DataOutputStream(BufferedOutputStream(socket.getOutputStream()))
        val localNonce: String = UUID.randomUUID().toString()
        @Volatile var remoteNonce: String? = null
        @Volatile var remoteName: String = "附近设备"
        @Volatile var localAccepted: Boolean = false
        @Volatile var remoteAccepted: Boolean = false
        val verificationEmitted = AtomicBoolean(false)
        val connectedEmitted = AtomicBoolean(false)
        val closed = AtomicBoolean(false)
    }
}
