package com.example.pare_app

import android.os.Handler
import android.os.Looper
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

object MpinCrypto {
    private val executor = Executors.newSingleThreadExecutor()
    fun install(engine: FlutterEngine) {
        val main = Handler(Looper.getMainLooper())
        MethodChannel(engine.dartExecutor.binaryMessenger, "pare_app/crypto").setMethodCallHandler { call, result ->
            if (call.method != "deriveMpin") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val pin = call.argument<String>("mpin") ?: ""
            val saltText = call.argument<String>("salt") ?: ""
            if (!pin.matches(Regex("[0-9]{6}")) || saltText.length > 32) {
                result.error("INVALID_MPIN_INPUT", "Invalid MPIN parameters", null)
                return@setMethodCallHandler
            }
            executor.execute {
                var spec: PBEKeySpec? = null
                try {
                    val salt = Base64.decode(saltText, Base64.NO_WRAP)
                    require(salt.size == 16)
                    val chars = pin.toCharArray()
                    spec = PBEKeySpec(chars, salt, 600_000, 256)
                    chars.fill('\u0000')
                    val bytes = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
                    val digest = Base64.encodeToString(bytes, Base64.NO_WRAP)
                    bytes.fill(0)
                    main.post { result.success(digest) }
                } catch (_: Exception) {
                    main.post { result.error("MPIN_DERIVATION_FAILED", "Could not verify MPIN securely", null) }
                } finally { spec?.clearPassword() }
            }
        }
    }
}
