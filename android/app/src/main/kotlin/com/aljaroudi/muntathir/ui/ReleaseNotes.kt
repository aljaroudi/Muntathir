package com.aljaroudi.muntathir.ui

import android.content.Context
import android.icu.util.ULocale
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.aljaroudi.muntathir.BuildConfig
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.components.currentLocale
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.Locale

@Serializable
internal data class ReleaseNote(val version: String, val platforms: List<String>, val notes: Map<String, String>, val releaseDates: Map<String, String> = emptyMap()) {
    fun text(locale: Locale): String {
        val script = ULocale.addLikelySubtags(ULocale.forLocale(locale)).script
        val key = notes.keys.firstOrNull { tag ->
            val candidate = Locale.forLanguageTag(tag)
            candidate.language == locale.language && (candidate.script.isEmpty() || candidate.script == script)
        }
        return notes[locale.toLanguageTag()] ?: notes[key] ?: notes.getValue("en-US")
    }
}

internal fun compareVersions(left: String, right: String): Int {
    val a = left.split('.').map(String::toInt)
    val b = right.split('.').map(String::toInt)
    for (index in 0 until maxOf(a.size, b.size)) {
        val difference = (a.getOrNull(index) ?: 0).compareTo(b.getOrNull(index) ?: 0)
        if (difference != 0) return difference
    }
    return 0
}

@Composable
internal fun releaseHistory(): List<ReleaseNote> {
    val context = LocalContext.current
    return remember(context) {
        val json = context.assets.open("changelog.json").bufferedReader().use { it.readText() }
        Json.decodeFromString<List<ReleaseNote>>(json)
            .filter { "android" in it.platforms && compareVersions(it.version, BuildConfig.VERSION_NAME) <= 0 }
            .sortedWith { a, b -> compareVersions(b.version, a.version) }
    }
}

internal fun pendingReleaseNotes(history: List<ReleaseNote>, installed: String, seen: String?, onboarded: Boolean): List<ReleaseNote> {
    if (!onboarded) return emptyList()
    return history.filter {
        compareVersions(it.version, installed) <= 0 &&
            (if (seen == null) it.version == installed else compareVersions(it.version, seen) > 0)
    }
}

@Composable
internal fun ReleaseNotesPrompt(onboarded: Boolean) {
    val preferences = LocalContext.current.getSharedPreferences("release-notes", Context.MODE_PRIVATE)
    val installed = BuildConfig.VERSION_NAME
    val history = releaseHistory()
    var pending by remember { mutableStateOf(emptyList<ReleaseNote>()) }
    fun markSeen() = preferences.edit().putString("seen", installed).apply()
    LaunchedEffect(onboarded) {
        val seen = preferences.getString("seen", null)
        if (seen != null && compareVersions(seen, installed) >= 0) return@LaunchedEffect
        pending = pendingReleaseNotes(history, installed, seen, onboarded)
        if (pending.isEmpty()) markSeen()
    }
    if (pending.isNotEmpty()) ReleaseNotesSheet(pending) {
        markSeen()
        pending = emptyList()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReleaseNotesSheet(entries: List<ReleaseNote>, dismiss: () -> Unit) {
    val locale = currentLocale()
    ModalBottomSheet(onDismissRequest = dismiss) {
        LazyColumn(modifier = Modifier.padding(horizontal = 24.dp)) {
            item { Text(stringResource(R.string.what_s_new), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() }) }
            items(entries, key = { it.version }) { entry ->
                Text(entry.version, Modifier.padding(top = 16.dp).semantics { heading() }, style = MaterialTheme.typography.titleMedium)
                entry.releaseDates["android"]?.let { day ->
                    Text(day, style = MaterialTheme.typography.bodySmall)
                }
                Text(entry.text(locale))
            }
            item { TextButton(onClick = dismiss) { Text(stringResource(R.string.done)) } }
        }
    }
}
