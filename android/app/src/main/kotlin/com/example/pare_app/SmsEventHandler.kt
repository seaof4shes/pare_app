package com.example.pare_app

import io.flutter.plugin.common.EventChannel

object SmsEventHandler {
    var eventSink: EventChannel.EventSink? = null

    fun sendSmsToFlutter(sender: String, body: String) {
        val smsData = mapOf(
            "sender" to sender,
            "body" to body
        )

        eventSink?.success(smsData)
    }
}