package com.example.pare_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.ContactsContract
import android.provider.Telephony

class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)

            if (messages.isNotEmpty()) {
                val senderNumber = messages[0].originatingAddress ?: "Unknown"

                val fullBody = messages.joinToString(separator = "") { sms ->
                    sms.messageBody ?: ""
                }

                val contactName = getContactName(context, senderNumber)

                // 👇 Use contact name if available
                val displayName = contactName ?: senderNumber

                SmsEventHandler.sendSmsToFlutter(displayName, fullBody)
            }
        }
    }

    private fun getContactName(context: Context, phoneNumber: String?): String? {
        if (phoneNumber == null) return null

        val uri = ContactsContract.PhoneLookup.CONTENT_FILTER_URI.buildUpon()
            .appendPath(phoneNumber)
            .build()

        val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)

        context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(ContactsContract.PhoneLookup.DISPLAY_NAME)
                return cursor.getString(nameIndex)
            }
        }

        return null
    }
}