package com.textoratech.textora_dialer

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.textoratech.textora_dialer/telephony"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("TextoraDialerPrefs", Context.MODE_PRIVATE)
            when (call.method) {
                "setCallInitiated" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    val leadId = call.argument<String>("leadId") ?: ""
                    prefs.edit()
                        .putBoolean("is_crm_call_active", true)
                        .putBoolean("crm_call_was_offhook", false)
                        .putLong("crm_call_timestamp", System.currentTimeMillis())
                        .putString("active_phone", phone)
                        .putString("active_lead_id", leadId)
                        .apply()
                    result.success(true)
                }
                "clearCallState" -> {
                    prefs.edit()
                        .putBoolean("is_crm_call_active", false)
                        .putBoolean("crm_call_was_offhook", false)
                        .apply()
                    result.success(true)
                }
                "getActiveCallState" -> {
                    val isCrmActive = prefs.getBoolean("is_crm_call_active", false)
                    val phone = prefs.getString("active_phone", null)
                    val leadId = prefs.getString("active_lead_id", null)
                    result.success(mapOf(
                        "isCrmActive" to isCrmActive,
                        "phone" to phone,
                        "leadId" to leadId
                    ))
                }
                else -> result.notImplemented()
            }
        }
    }
}
