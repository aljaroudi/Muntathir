package com.aljaroudi.muntathir.ui.navigation

import android.content.Context
import android.content.Intent
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.core.app.AppTool

/** A request from outside the app (launcher shortcut, widget, Quick Settings tile) to show Today or a tool. */
data class OpenRequest(
    /** `null` opens Today. */
    val tool: AppTool?,
) {
    companion object {
        /** Also used by `res/xml/shortcuts.xml`: `today` or an [AppTool.id]. */
        const val EXTRA = "open"
        private const val TODAY = "today"

        fun intent(
            context: Context,
            tool: AppTool?,
        ): Intent =
            Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .putExtra(EXTRA, tool?.id ?: TODAY)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        fun from(intent: Intent?): OpenRequest? =
            when (val id = intent?.getStringExtra(EXTRA)) {
                null -> null
                TODAY -> OpenRequest(null)
                else -> AppTool.entries.firstOrNull { it.id == id }?.let(::OpenRequest)
            }
    }
}
