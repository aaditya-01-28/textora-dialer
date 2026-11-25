package com.textoratech.textora_dialer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.textoratech.textora_dialer/telephony"
    private val AGENDA_CHANNEL_ID = "textora_agenda_channel"
    private var methodChannel: MethodChannel? = null
    private var pendingOpenAgenda: Boolean = false

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("open_agenda", false)) {
            pendingOpenAgenda = true
            methodChannel?.invokeMethod("openAgenda", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (intent?.getBooleanExtra("open_agenda", false) == true) {
            pendingOpenAgenda = true
        }

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
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
                "showAgendaNotification" -> {
                    val notificationId = call.argument<Int>("notificationId") ?: (System.currentTimeMillis() % 100000).toInt()
                    val title = call.argument<String>("title") ?: "Agenda Reminder"
                    val body = call.argument<String>("body") ?: "Upcoming task scheduled"
                    val phone = call.argument<String>("phone")
                    val meetingLink = call.argument<String>("meetingLink")
                    val leadId = call.argument<String>("leadId")

                    showAgendaNotification(notificationId, title, body, phone, meetingLink, leadId)
                    result.success(true)
                }
                "consumeOpenAgendaIntent" -> {
                    val shouldOpen = pendingOpenAgenda
                    pendingOpenAgenda = false
                    result.success(shouldOpen)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun showAgendaNotification(
        notificationId: Int,
        title: String,
        body: String,
        phone: String?,
        meetingLink: String?,
        leadId: String?
    ) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                AGENDA_CHANNEL_ID,
                "Textora Agenda & Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Timely reminders for scheduled callbacks and client demos"
                enableVibration(true)
                enableLights(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
            putExtra("open_agenda", true)
            if (!leadId.isNullOrBlank()) {
                putExtra("lead_id", leadId)
            }
        }

        val contentPendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                notificationId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        val builder = NotificationCompat.Builder(this, AGENDA_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(contentPendingIntent)
            .setVibrate(longArrayOf(0, 300, 200, 300))

        if (!phone.isNullOrBlank()) {
            val callIntent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val callPendingIntent = PendingIntent.getActivity(
                this,
                notificationId + 100000,
                callIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(
                android.R.drawable.sym_action_call,
                "Call $phone",
                callPendingIntent
            )
        }

        if (!meetingLink.isNullOrBlank()) {
            val meetIntent = Intent(Intent.ACTION_VIEW, Uri.parse(meetingLink)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val meetPendingIntent = PendingIntent.getActivity(
                this,
                notificationId + 200000,
                meetIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(
                android.R.drawable.ic_menu_view,
                "Join Meeting",
                meetPendingIntent
            )
        }

        notificationManager.notify(notificationId, builder.build())
    }
}
