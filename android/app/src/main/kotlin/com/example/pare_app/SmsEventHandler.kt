package com.example.pare_app

import io.flutter.plugin.common.EventChannel

object SmsEventHandler {

    var eventSink: EventChannel.EventSink? = null

    fun sendSmsToFlutter(
        senderNumber: String,
        senderName: String,
        body: String
    ) {

        val smsData = mapOf(
            "senderNumber" to senderNumber,
            "senderName" to senderName,
            "body" to body
        )

        eventSink?.success(smsData)
    }
}