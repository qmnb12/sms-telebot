// Copyright (c) 2025-2026 Pavel D. (teslor)
// SPDX-License-Identifier: AGPL-3.0-or-later

package com.teslor.sms_telebot

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class NotificationService : NotificationListenerService() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null || sbn.isOngoing || sbn.packageName == packageName) return

        val notification = sbn.notification ?: return
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return

        val dbManager = DbManager.getInstance(applicationContext)
        val settings = dbManager.getSettings(listOf("isRunning", "forwardPushes", "pushedAppsJson"))
        if (settings["isRunning"] != "1" || settings["forwardPushes"] != "1") return
        val pushedAppsJson = settings["pushedAppsJson"]
        if (pushedAppsJson.isNullOrBlank() || !pushedAppsJson.contains("\"${sbn.packageName}\"")) return

        serviceScope.launch {
            try {
                processNotification(sbn, notification)
            } catch (e: Exception) {
                AppLog.e("NotificationService", "Failed to process notification from ${sbn.packageName}", e)
            }
        }
    }

    private fun processNotification(sbn: StatusBarNotification, notification: Notification) {
        val extras = notification.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val body = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)
            ?: extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.filterNotNull()?.joinToString("\n"))
            ?.toString()?.trim().orEmpty()
        if (title.isBlank() && body.isBlank()) return

        val appLabel = getAppLabel(sbn.packageName)
        val sender = when {
            title.isBlank() -> appLabel
            title.equals(appLabel, ignoreCase = true) -> appLabel
            else -> "$appLabel: $title"
        }
        val postTime = if (sbn.postTime > 0) sbn.postTime else System.currentTimeMillis()

        // Within a 5-second window, the ID for the same sender/body will be the same
        val timeWindow = postTime / 5000L
        val pushId = MessageHelpers.generateId("$sender|$body|$timeWindow")

        MessageProcessor.processAndForward(
            context = applicationContext,
            id = pushId,
            type = "push",
            sender = sender,
            body = body,
            simInfo = null,
            sourceAt = postTime,
            receivedAt = System.currentTimeMillis()
        )
    }

    private fun getAppLabel(packageName: String): String {
        return try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
            packageName
        }
    }
}
