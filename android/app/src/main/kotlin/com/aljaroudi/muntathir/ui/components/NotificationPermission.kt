package com.aljaroudi.muntathir.ui.components

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.NotificationManagerCompat

/**
 * Swift `NotificationService.authorize()`: returns a function that asks for notification permission when
 * needed (API 33+) and reports whether notifications can be shown.
 */
@Composable
fun rememberNotificationPermission(onResult: (Boolean) -> Unit): () -> Unit {
    val context = LocalContext.current
    val callback by rememberUpdatedState(onResult)
    val enabled = { NotificationManagerCompat.from(context).areNotificationsEnabled() }
    val launcher =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            callback(granted && enabled())
        }
    return {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !enabled()) {
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            callback(enabled())
        }
    }
}
