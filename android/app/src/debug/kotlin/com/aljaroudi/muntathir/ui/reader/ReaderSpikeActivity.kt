package com.aljaroudi.muntathir.ui.reader

import android.os.Bundle
import android.util.TypedValue
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.aljaroudi.muntathir.core.highlight.HighlightRange
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.text.HadithText
import com.aljaroudi.muntathir.core.text.TextRange
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import kotlinx.serialization.json.Json
import java.io.File

/**
 * P1.7 spike, debug builds only: hadith text in [HighlightTextView]; highlights persist to a JSON file
 * (Room replaces this store in P3.4). Launch: `adb shell am start -n com.aljaroudi.muntathir/.ui.reader.ReaderSpikeActivity`.
 */
class ReaderSpikeActivity : ComponentActivity() {
    val store by lazy { HighlightSpikeStore(File(filesDir, "reader-spike-highlights.json")) }
    val content = HadithText.canonical(HadithText.markdown(SAMPLE))
    private var highlights by mutableStateOf(emptyList<ReadingHighlight>())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        highlights = store.load()
        setContent {
            MuntathirTheme {
                Scaffold { padding ->
                    HighlightText(
                        text = content,
                        highlights = highlights,
                        block = BLOCK,
                        onHighlight = ::save,
                        modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(24.dp),
                        configure = {
                            tag = VIEW_TAG
                            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
                        },
                    )
                }
            }
        }
    }

    private fun save(selection: List<TextRange>) {
        val ranges = selection.mapNotNull { HighlightRange.of(it, content.text) }
        if (ranges.isEmpty()) return
        val highlight =
            ReadingHighlight(
                source = "spike",
                isHadith = true,
                block = BLOCK,
                ranges = ranges,
                excerpt = ranges.joinToString(" … ") { it.quote },
                reference = "spike",
            )
        highlights = highlights + highlight
        store.save(highlights)
    }

    companion object {
        const val BLOCK = "arabic"
        const val VIEW_TAG = "reader-text"
        const val SAMPLE =
            "**حَدَّثَنَا** الْحُمَيْدِيُّ قَالَ: إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ، وَإِنَّمَا لِكُلِّ امْرِئٍ مَا نَوَى\n\n" +
                "- Actions are judged by intentions 😀.\n" +
                "- Every person will have what they intended.\n\n" +
                "> قَالَ رَسُولُ اللَّهِ ﷺ"
    }
}

class HighlightSpikeStore(
    private val file: File,
) {
    private val json = Json { ignoreUnknownKeys = true }

    fun load(): List<ReadingHighlight> = runCatching { json.decodeFromString<List<ReadingHighlight>>(file.readText()) }.getOrDefault(emptyList())

    fun save(highlights: List<ReadingHighlight>) = file.writeText(json.encodeToString(highlights))

    fun clear() {
        file.delete()
    }
}
