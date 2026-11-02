package com.example.pare_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.ContactsContract
import android.provider.Telephony

class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {

            val settings = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (!settings.getBoolean("flutter.protection_activated", false) ||
                !settings.getBoolean("flutter.isLoggedIn", false) ||
                !settings.getBoolean("flutter.msg_detection", true)) return
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)

            if (messages.isNotEmpty()) {

                // Actual phone number of the SMS sender
                val senderNumber =
                    messages[0].originatingAddress ?: "Unknown"

                // Full SMS content
                val fullBody = messages.joinToString(separator = "") { sms ->
                    sms.messageBody ?: ""
                }

                // Optional contact name
                val contactName =
                    try { getContactName(context, senderNumber) } catch (_: SecurityException) { null }

                try { SmsEventHandler.enqueue(
                    context = context.applicationContext,
                    senderNumber = senderNumber,
                    senderName = contactName ?: "",
                    body = fullBody,
                    timestamp = messages[0].timestampMillis
                )
                    SmsAnalysisJob.schedule(context.applicationContext)
                } catch (e: Exception) { android.util.Log.e("PARE", "Could not queue SMS", e) }
            }
        }
    }

    private fun getContactName(
        context: Context,
        phoneNumber: String?
    ): String? {

        if (phoneNumber == null) return null

        val uri =
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI
                .buildUpon()
                .appendPath(phoneNumber)
                .build()

        val projection =
            arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)

        context.contentResolver.query(
            uri,
            projection,
            null,
            null,
            null
        )?.use { cursor ->

            if (cursor.moveToFirst()) {

                val nameIndex =
                    cursor.getColumnIndex(
                        ContactsContract.PhoneLookup.DISPLAY_NAME
                    )

                if (nameIndex >= 0) {
                    return cursor.getString(nameIndex)
                }
            }
        }

        return null
    }
}
