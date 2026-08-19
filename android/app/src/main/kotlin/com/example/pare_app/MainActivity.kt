package com.example.pare_app

import android.content.Intent
import android.net.Uri

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val smsChannel = "pare_app/sms_receiver"
    private val blockChannel = "pare_app/block_sender"

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

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

            when (call.method) {

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