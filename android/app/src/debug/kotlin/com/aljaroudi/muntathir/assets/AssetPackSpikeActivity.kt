package com.aljaroudi.muntathir.assets

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import com.aljaroudi.muntathir.data.HadithDatabase
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.time.measureTimedValue

/**
 * P1.8 spike, debug builds only: fetches the hadith pack with Play Asset Delivery and runs FTS5 queries on it.
 * Install with `just android-local-testing`, then
 * `adb shell am start -n com.aljaroudi.muntathir/.assets.AssetPackSpikeActivity`. Logs use the tag "AssetPackSpike".
 */
class AssetPackSpikeActivity : ComponentActivity() {
    private val lines = mutableStateListOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MuntathirTheme {
                Scaffold { padding ->
                    Text(
                        lines.joinToString("\n"),
                        Modifier
                            .fillMaxSize()
                            .padding(padding)
                            .verticalScroll(rememberScrollState())
                            .padding(16.dp),
                    )
                }
            }
        }
        lifecycleScope.launch { run(PlayAssetPackBackend(this@AssetPackSpikeActivity)) }
    }

    private suspend fun run(backend: AssetPackBackend) {
        for (pack in ContentPack.entries) report("${pack.packName}: ${backend.status(pack)}")
        val pack = ContentPack.Hadith
        var status = backend.status(pack)
        if (status !is PackStatus.Installed) {
            report("Fetching ${pack.packName}: ${backend.download(pack)}")
            status =
                backend.updates(pack).first {
                    report("  $it")
                    if (it is PackStatus.WaitingForWifi || it is PackStatus.RequiresConfirmation) backend.confirm(this)
                    it is PackStatus.Installed || it is PackStatus.Failed || it is PackStatus.Canceled
                }
        }
        val assets = (status as? PackStatus.Installed)?.assets ?: return report("Not installed: $status")
        withContext(Dispatchers.IO) {
            val file = File(assets, pack.database)
            HadithDatabase.open(file).use { db ->
                report("Opened ${file.name}: v${db.userVersion}, ${db.count()} hadith")
                for (query in listOf("انما الاعمال بالنيات", "الاعمال", "intentions", "seeking knowledge")) {
                    val (matches, duration) = measureTimedValue { db.search(query) }
                    report("“$query”: ${matches.size} matches in $duration, first ${matches.take(3)}")
                }
            }
        }
    }

    private fun report(line: String) {
        Log.i("AssetPackSpike", line)
        runOnUiThread { lines += line }
    }
}
