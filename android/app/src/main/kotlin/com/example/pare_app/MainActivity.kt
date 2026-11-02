package com.example.pare_app

import android.content.Intent
import android.net.Uri

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var wifiMonitor: WifiMonitor? = null
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        wifiMonitor?.close()
        wifiMonitor = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private val smsChannel = "pare_app/sms_receiver"
    private val blockChannel = "pare_app/block_sender"

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)
        MpinCrypto.install(flutterEngine)
        wifiMonitor = WifiMonitor(applicationContext, flutterEngine)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
        SmsAnalysisJob.schedule(applicationContext)

        // =========================================================
        // EXISTING SMS EVENT CHANNEL
        // =========================================================

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            smsChannel
        ).setStreamHandler(
            object : EventChannel.StreamHandler {

                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?
                ) {
                    SmsEventHandler.eventSink = events
                    try { SmsEventHandler.drain(applicationContext) } catch (e: Exception) { events?.error("SMS_QUEUE_ERROR", e.message, null) }
                }

                override fun onCancel(arguments: Any?) {
                    SmsEventHandler.eventSink = null
                }
            }
        )

        // =========================================================
        // BLOCK SENDER METHOD CHANNEL
        // =========================================================

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            blockChannel
        ).setMethodCallHandler { call, result ->

            // Integration fixtures are unavailable in non-debuggable builds.
            if (call.method.startsWith("debugSms")) {
                if ((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    when (call.method) {
                        "debugSmsEnqueue" -> {
                            SmsEventHandler.enqueue(applicationContext, "PARE TEST", "", call.argument<String>("body") ?: "", call.argument<Number>("timestamp")!!.toLong())
                            SmsAnalysisJob.schedule(applicationContext)
                            result.success(true)
                        }
                        "debugSmsStatus" -> result.success(mapOf("running" to SmsAnalysisJob.isRunning(), "pending" to SmsEventHandler.pending(applicationContext).size))
                        "debugSmsBackground" -> result.success(moveTaskToBack(true))
                        "debugSmsRemoveFixtures" -> {
                            val owner = call.argument<String>("owner")
                            SmsEventHandler.pending(applicationContext).filter {
                                it["owner"] == owner && it["senderNumber"] == "PARE TEST"
                            }.forEach { SmsEventHandler.acknowledge(applicationContext, it["id"] as String) }
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) { result.error("TEST_FAILED", "SMS fixture failed", null) }
                return@setMethodCallHandler
            }

            when (call.method) {
                "clearPendingSms" -> {
                    try { SmsEventHandler.clear(applicationContext); result.success(true) }
                    catch (e: Exception) { result.error("SMS_QUEUE_ERROR", "Could not clear pending messages", null) }
                }
                "acknowledgeSms" -> {
                    try {
                        SmsEventHandler.acknowledge(applicationContext, call.argument<String>("id") ?: "")
                        result.success(true)
                    } catch (e: Exception) { result.error("SMS_QUEUE_ERROR", e.message, null) }
                }
                "openAppUpdate" -> {
                    val uri = Uri.parse(call.argument<String>("url") ?: "")
                    if (uri.scheme != "https" || uri.host.isNullOrBlank()) {
                        result.error("INVALID_URL", "A secure update address is required", null)
                    } else {
                        try { startActivity(Intent(Intent.ACTION_VIEW, uri)); result.success(true) }
                        catch (e: Exception) { result.error("UPDATE_OPEN_ERROR", e.message, null) }
                    }
                }


                "openSmsConversation" -> {

                    val sender = call.argument<String>("sender")

                    if (sender.isNullOrBlank()) {
                        result.error(
                            "INVALID_SENDER",
                            "Sender number is required.",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    openSmsConversation(
                        sender,
                        result
                    )
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // =========================================================
    // OPEN SMS CONVERSATION
    // =========================================================

    private fun openSmsConversation(
        sender: String,
        result: MethodChannel.Result
    ) {
        try {

            val normalizedSender = sender
                .replace(" ", "")
                .replace("-", "")
                .replace("(", "")
                .replace(")", "")

            val intent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("sms:$normalizedSender")
            )

            startActivity(intent)

            result.success(true)

        } catch (e: Exception) {

            result.error(
                "SMS_OPEN_ERROR",
                e.message
                    ?: "Unable to open the messaging application.",
                null
            )
        }
    }
}
