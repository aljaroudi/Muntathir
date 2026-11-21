package com.aljaroudi.muntathir.watch

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.core.net.toUri
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.aljaroudi.muntathir.watch.data.Surfaces
import com.aljaroudi.muntathir.watch.data.WatchStore
import com.aljaroudi.muntathir.watch.ui.PrayerListScreen
import com.aljaroudi.muntathir.watch.ui.Stored
import com.aljaroudi.muntathir.watch.ui.WatchTheme
import kotlinx.coroutines.launch

/** Swift `MuntathirWatchApp`: the prayer list, catching up with the phone whenever it comes to the front. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                if (WatchStore.sync(this@MainActivity)) Surfaces.refresh(this@MainActivity)
            }
        }
        setContent {
            // Null until the saved snapshot has been read, so the sync hint doesn't flash on launch.
            val stored by produceState<Stored?>(null) {
                WatchStore.snapshots(this@MainActivity).collect { value = Stored(it) }
            }
            WatchTheme { PrayerListScreen(stored, onOpenPhone = ::openOnPhone) }
        }
    }

    /** Opens the app's Play listing on the phone, which offers Open (or Install). */
    private fun openOnPhone() {
        val intent =
            Intent(Intent.ACTION_VIEW)
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .setData("market://details?id=$packageName".toUri())
        RemoteActivityHelper(this).startRemoteActivity(intent)
    }
}
