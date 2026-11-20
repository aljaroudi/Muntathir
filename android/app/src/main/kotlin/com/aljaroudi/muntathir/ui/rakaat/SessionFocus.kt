package com.aljaroudi.muntathir.ui.rakaat

import android.app.NotificationManager
import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Do Not Disturb (priority only) for a rakaat session, when the user granted notification policy access.
 *
 * Only turns DND on when it was off, and marks that with a no-backup file so [recover] can turn it off again after
 * the process dies mid-session. DND the user already had on is left alone, and a filter the user changes during the
 * session isn't overridden.
 */
@Singleton
class SessionFocus
    @Inject
    constructor(
        @ApplicationContext context: Context,
    ) {
        private val manager = context.getSystemService(NotificationManager::class.java)
        private val marker = File(context.noBackupFilesDir, MARKER)

        val available: Boolean get() = manager.isNotificationPolicyAccessGranted

        fun begin() {
            if (!available || marker.exists()) return
            if (manager.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL) return
            runCatching {
                marker.createNewFile()
                manager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
            }.onFailure { marker.delete() }
        }

        fun end() {
            if (!marker.exists()) return
            if (available &&
                manager.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_PRIORITY
            ) {
                runCatching { manager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL) }
            }
            marker.delete()
        }

        /** Turns off the DND a session that never ended (the process died) left on. */
        fun recover() = end()

        private companion object {
            const val MARKER = "rakaat-session-focus"
        }
    }
