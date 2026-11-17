package com.aljaroudi.muntathir.ui.settings

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SectionFooter
import com.aljaroudi.muntathir.ui.components.SectionHeader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private class Credit(
    val title: String,
    val url: String,
)

/** Swift `Settings.bundle/Credits.plist`, shown in the app since Android has no Settings bundle. */
private val translations =
    listOf(
        Credit("马坚", "https://tanzil.net/trans/zh.jian"),
        Credit("马坚", "https://tanzil.net/trans/zh.majian"),
        Credit("Ali Quli Qara’i", "https://tanzil.net/trans/en.qarai"),
        Credit("Bubenheim & Elyas", "https://tanzil.net/trans/de.bubenheim"),
        Credit("Кулиев", "https://tanzil.net/trans/ru.kuliev"),
        Credit("Bornez", "https://tanzil.net/trans/es.bornez"),
        Credit("فولادوند", "https://tanzil.net/trans/fa.fooladvand"),
        Credit("Hamidullah", "https://tanzil.net/trans/fr.hamidullah"),
        Credit("Kementerian Agama", "https://tanzil.net/trans/id.indonesian"),
        Credit("Piccardo", "https://tanzil.net/trans/it.piccardo"),
        Credit("Basmeih", "https://tanzil.net/trans/ms.basmeih"),
        Credit("Diyanet Vakfı", "https://tanzil.net/trans/tr.vakfi"),
        Credit("جوادی", "https://tanzil.net/trans/ur.jawadi"),
    )

private val supplications =
    listOf(
        Credit("Supplication of Kumayl — en — Duas.org", "https://www.duas.org/mobile/dua-kumayl-habib.html"),
        Credit("Supplication of Kumayl — ur — Duas.org", "https://www.duas.org/ppt/Dua_Kumayl_5languages.pptx"),
        Credit("Al-Sabah Supplication — en — Duas.org", "https://www.duas.org/mobile/dua-sabah.html"),
        Credit("Al-Nudba Supplication — en — Duas.org", "https://www.duas.org/nudba.htm"),
        Credit("Al-Nudba Supplication — ur — Duas.org", "https://www.duas.org/ppt/Dua_al_Nudbah_Eng_Urdu.ppsx"),
    )

@Composable
fun CreditsScreen(
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val adhan by produceState(
        "",
    ) { value = withContext(Dispatchers.IO) { context.asset("licenses/Adhan-LICENSE.txt") } }
    val sounds by produceState("") {
        value =
            withContext(Dispatchers.IO) { context.asset("licenses/AdhanSounds-CREDITS.txt") }
    }
    val plex by produceState("") {
        value = withContext(Dispatchers.IO) { context.asset("licenses/IBMPlexSansArabic-OFL.txt") }
    }
    val open: (String) -> Unit = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it))) }
    ScreenScaffold(R.string.sources_and_licenses, modifier, onBack) { padding ->
        LazyColumn(contentPadding = padding) {
            item { SectionHeader(stringResource(R.string.calculations)) }
            item {
                ListItem(headlineContent = {
                    Text("Adhan Swift 1.5.0")
                }, supportingContent = { Text(adhan, style = MaterialTheme.typography.bodySmall) })
            }
            item { SectionHeader(stringResource(R.string.quran_translations)) }
            items(translations) { CreditRow(it, open) }
            item { SectionHeader(stringResource(R.string.supplication_translations)) }
            items(supplications) { CreditRow(it, open) }
            item {
                SectionFooter(
                    stringResource(R.string.duas_org_credit) + " https://www.duas.org/mobile/about-us.html",
                )
            }
            item { SectionHeader(stringResource(R.string.adhan_sounds)) }
            item { Text(sounds, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(16.dp)) }
            item { SectionHeader(stringResource(R.string.fonts)) }
            item {
                ListItem(headlineContent = {
                    Text("IBM Plex Sans Arabic")
                }, supportingContent = { Text(plex, style = MaterialTheme.typography.bodySmall) })
            }
        }
    }
}

@Composable
private fun CreditRow(
    credit: Credit,
    open: (String) -> Unit,
) {
    ListItem(
        headlineContent = { Text(credit.title) },
        supportingContent = { Text(credit.url, style = MaterialTheme.typography.bodySmall) },
        modifier = Modifier.selectable(selected = false, role = Role.Button) { open(credit.url) },
    )
}

private fun android.content.Context.asset(path: String): String =
    runCatching { assets.open(path).use { it.readBytes().decodeToString() } }.getOrDefault("")
