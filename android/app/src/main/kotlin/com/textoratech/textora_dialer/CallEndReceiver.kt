package com.textoratech.textora_dialer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat

class CallEndReceiver : BroadcastReceiver() {
    companion object {
        private const val CHANNEL_ID = "textora_dialer_call_channel"
        private const val NOTIFICATION_ID = 2026
        private const val PREFS_NAME = "TextoraDialerPrefs"
        private const val MAX_CALL_AGE_MS = 45 * 60 * 1000L // 45 minutes max call session
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // Strict Privacy & Scope Guard:
        // NEVER show notifications or auto-open app for personal calls, incoming calls,
        // or any call dialed outside Textora Dialer!
        val isCrmActive = prefs.getBoolean("is_crm_call_active", false)
        if (!isCrmActive) {
            return
        }

        val callTimestamp = prefs.getLong("crm_call_timestamp", 0L)
        val elapsed = System.currentTimeMillis() - callTimestamp
        if (elapsed !in 0..MAX_CALL_AGE_MS) {
            // Expired initiated session (> 45 min). Clear flag and do nothing.
            prefs.edit().putBoolean("is_crm_call_active", false).apply()
            return
        }

        when (state) {
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                // Outgoing CRM call has been dialed / connected
                prefs.edit().putBoolean("crm_call_was_offhook", true).apply()
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                val wasOffhook = prefs.getBoolean("crm_call_was_offhook", false)
                val phone = prefs.getString("active_phone", null)

                // Clear active CRM call flag immediately to prevent future personal calls from triggering
                prefs.edit()
                    .putBoolean("is_crm_call_active", false)
                    .putBoolean("crm_call_was_offhook", false)
                    .apply()

                // Trigger auto-open and status update notification only if the call was actually placed (went offhook)
                if (wasOffhook) {
                    onCallEnded(context, phone)
                }
            }
        }
    }

    private fun onCallEnded(context: Context, phone: String?) {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
            putExtra("auto_opened_after_call", true)
        }

        // 1. Attempt direct foreground launch to bring app right back
        if (launchIntent != null) {
            try {
                context.startActivity(launchIntent)
            } catch (_: Exception) {
            }
        }

        // 2. High-priority Heads-up Notification (Guarantees 1-tap open on Android 10+ background restriction)
        showCallNotification(context, launchIntent, phone)
    }

    private fun showCallNotification(context: Context, launchIntent: Intent?, phone: String?) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Textora Call Status Update",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifies when a CRM lead call ends to log outcome and notes"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val pendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        val title = if (!phone.isNullOrBlank()) "Lead Call Ended • +91 $phone" else "Call Ended • Update Lead Status"
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(title)
            .setContentText("Tap to record connected duration & disposition")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify(NOTIFICATION_ID, notification)
    }
}
