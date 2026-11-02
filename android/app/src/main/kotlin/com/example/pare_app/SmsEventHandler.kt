package com.example.pare_app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Encrypted queue; Flutter acknowledges receipt after saving history. */
object SmsEventHandler {
    var eventSink: EventChannel.EventSink? = null
    private const val alias = "pare_sms_pending"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun read(context: Context): JSONArray {
        val raw = context.getSharedPreferences(alias, 0).getString("queue", null) ?: return JSONArray()
        val parts = raw.split(":", limit = 2)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
        return JSONArray(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
    }
    private fun write(context: Context, queue: JSONArray) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val payload = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(cipher.doFinal(queue.toString().toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        check(context.getSharedPreferences(alias, 0).edit().putString("queue", payload).commit())
    }
    @Synchronized fun enqueue(context: Context, senderNumber: String, senderName: String, body: String, timestamp: Long) {
        val id = MessageDigest.getInstance("SHA-256").digest("$senderNumber|$timestamp|$body".toByteArray()).joinToString("") { "%02x".format(it) }
        val queue = read(context)
        for (i in 0 until queue.length()) if (queue.getJSONObject(i).getString("id") == id) return
        while (queue.length() >= 100) queue.remove(0)
        val data = JSONObject().put("id", id).put("senderNumber", senderNumber).put("senderName", senderName)
            .put("body", body).put("receivedAt", timestamp)
            .put("owner", context.getSharedPreferences("FlutterSharedPreferences", 0).getString("flutter.sms_owner", ""))
        queue.put(data)
        write(context, queue)
        deliver(data)
    }
    private fun deliver(data: JSONObject) {
        eventSink?.success(mapOf("id" to data.getString("id"), "senderNumber" to data.getString("senderNumber"),
            "senderName" to data.getString("senderName"), "body" to data.getString("body"), "receivedAt" to data.getLong("receivedAt"), "owner" to data.optString("owner", "")))
    }
    @Synchronized fun drain(context: Context) {
        val queue = read(context)
        for (i in 0 until queue.length()) deliver(queue.getJSONObject(i))
    }
    @Synchronized fun clear(context: Context) { write(context, JSONArray()) }

    @Synchronized fun pending(context: Context): List<Map<String, Any>> {
        val queue = read(context)
        return (0 until queue.length()).map { index ->
            val item = queue.getJSONObject(index)
            mapOf("id" to item.getString("id"), "senderNumber" to item.getString("senderNumber"),
                "senderName" to item.getString("senderName"), "body" to item.getString("body"),
                "receivedAt" to item.getLong("receivedAt"), "owner" to item.optString("owner", ""))
        }
    }

    @Synchronized fun acknowledge(context: Context, id: String) {
        val queue = read(context)
        for (i in queue.length() - 1 downTo 0) if (queue.getJSONObject(i).getString("id") == id) queue.remove(i)
        write(context, queue)
    }
}
