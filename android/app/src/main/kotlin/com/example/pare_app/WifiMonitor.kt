package com.example.pare_app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class WifiMonitor(context: Context, engine: FlutterEngine) : EventChannel.StreamHandler {
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var registered = false
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = emit()
        override fun onLost(network: Network) = emit()
    }
    init { EventChannel(engine.dartExecutor.binaryMessenger, "pare_app/wifi").setStreamHandler(this) }
    private fun emit() {
        handler.post {
            val caps = manager.getNetworkCapabilities(manager.activeNetwork)
            sink?.success(caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true &&
                caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true)
        }
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (!registered) { manager.registerDefaultNetworkCallback(callback); registered = true }
        emit()
    }
    override fun onCancel(arguments: Any?) = close()
    fun close() {
        sink = null
        if (registered) { manager.unregisterNetworkCallback(callback); registered = false }
    }
}
