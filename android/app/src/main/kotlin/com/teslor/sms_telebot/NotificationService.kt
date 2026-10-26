// Copyright (c) 2025-2026 Pavel D. (teslor)
// SPDX-License-Identifier: AGPL-3.0-or-later

package com.teslor.sms_telebot

import android.app.Notification
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class NotificationService : NotificationListenerService() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    companion object {
        private const val TAG = "NotificationService"
        private const val MAX_LEN = 1000
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null || sbn.packageName == packageName) return

        val now = System.currentTimeMillis()
        val postTime = if (sbn.postTime > 0) sbn.postTime else now
        if (kotlin.math.abs(now - postTime) > TimeUnit.DAYS.toMillis(2)) return // drop old pushes

        val notification = sbn.notification ?: return
        if (sbn.isOngoing && notification.category != Notification.CATEGORY_CALL) return
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return

        val dbManager = DbManager.getInstance(applicationContext)
        val settings = dbManager.getSettings(listOf("isRunning", "forwardPushes", "pushedAppsJson"))
        if (settings["isRunning"] != "1" || settings["forwardPushes"] != "1") return
        val pushedAppsJson = settings["pushedAppsJson"]
        if (pushedAppsJson.isNullOrBlank() || !pushedAppsJson.contains("\"${sbn.packageName}\"")) return

        serviceScope.launch {
            try {
                processNotification(sbn, notification, postTime)
            } catch (e: Exception) {
                AppLog.e(TAG, "Failed to process notification from ${sbn.packageName}", e)
            }
        }
    }

    private fun processNotification(sbn: StatusBarNotification, notification: Notification, postTime: Long) {
        val extras = notification.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val bodyLines = extractMessageLines(extras)
        if (title.isBlank() && bodyLines.isEmpty()) return

        val appLabel = getAppLabel(sbn.packageName)
        val sender = when {
            title.isBlank() -> appLabel
            title.equals(appLabel, ignoreCase = true) -> appLabel
            else -> "$appLabel: $title"
        }

        val bodyFull = if (bodyLines.isNotEmpty()) bodyLines.joinToString("\n") else ""
        val body = if (bodyFull.length > MAX_LEN) bodyFull.take(MAX_LEN).trimEnd() + "..." else bodyFull
        val rawId = if (notification.category == Notification.CATEGORY_CALL) {
            // Avoid repeating pushes for the same call in short interval
            val timeBucket = sbn.postTime / 40_000L
            "${normalizeForDedup(sender)}|$body|${sbn.id}|${sbn.tag}|$timeBucket"
        } else {
            "${normalizeForDedup(sender)}|$body|${sbn.id}|${sbn.tag}"
        }
        val pushId = MessageHelpers.generateId(rawId)
        AppLog.d(TAG) {
            "Processing push (key=${sbn.key}, cat=${notification.category}, on=${sbn.isOngoing})"
        }

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

    private fun extractMessageLines(extras: Bundle): List<String> {
        val shortText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()

        // Expanded lines; take the newest (last) one
        val textLines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.map { it.toString().trim() }?.filter { it.isNotEmpty() }?.takeIf { it.isNotEmpty() }
        if (textLines != null) return listOf(textLines.last())

        // Structured per-message array (Android 7.0+); take the last entry
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            @Suppress("DEPRECATION")
            val messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
                ?.mapNotNull { (it as? Bundle)?.getCharSequence("text")?.toString()?.trim()
                ?.takeIf { text -> text.isNotEmpty() } }
            val lastMsg = messages?.lastOrNull()
            if (lastMsg != null && !lastMsg.equals(shortText, ignoreCase = true)) return listOf(lastMsg)
        }

        // Expanded text (message body/preview)
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        if (bigText.isNotEmpty() && !bigText.equals(shortText, ignoreCase = true)) {
            val t = shortText.takeIf { it.isNotEmpty() && bigText.endsWith(it, ignoreCase = true) } ?: bigText
            return splitBodyLines(t)
        }

        if (shortText.isNotEmpty()) return splitBodyLines(shortText)
        return emptyList()
    }

    private fun splitBodyLines(raw: String) = raw.lines().map { it.trim() }.filter { it.isNotEmpty() }
    private fun normalizeForDedup(text: String) = text.filterNot { it in " +-()" }

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
