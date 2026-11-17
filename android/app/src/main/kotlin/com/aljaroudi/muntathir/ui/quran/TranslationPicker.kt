package com.aljaroudi.muntathir.ui.quran

import android.icu.text.LocaleDisplayNames
import android.icu.util.ULocale
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.quran.DownloadState
import com.aljaroudi.muntathir.core.quran.QuranTranslation
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.downloads.AssetDownloadButton
import com.aljaroudi.muntathir.ui.downloads.AssetDownloadProgress
import com.aljaroudi.muntathir.ui.downloads.AssetDownloadSizes
import java.util.Locale

/** The picker while [open], then the download sheet when the choice still has to be downloaded. */
@Composable
fun TranslationPickerHost(
    translations: QuranTranslations,
    open: Boolean,
    onClose: () -> Unit,
) {
    var requested by rememberSaveable { mutableStateOf<String?>(null) }
    if (open) TranslationPickerDialog(translations, onDownload = { requested = it.id }, onDismiss = onClose)
    requested?.let(QuranTranslation::of)?.let { QuranDownloadSheet(translations, it) { requested = null } }
}

/** The translation's language in the interface language, e.g. "German" or "Chinese (Traditional)". */
fun QuranTranslation.languageName(locale: Locale): String =
    LocaleDisplayNames
        .getInstance(ULocale.forLocale(locale), LocaleDisplayNames.DialectHandling.DIALECT_NAMES)
        .localeDisplayName(ULocale.forLanguageTag(language))
        .replaceFirstChar { it.titlecase(locale) }

/**
 * Swift `QuranTranslationPicker`: Auto, None or a language. Choosing a translation that isn't downloaded (or
 * Auto resolving to one) asks to download it, via [onDownload].
 */
@Composable
fun TranslationPickerDialog(
    translations: QuranTranslations,
    onDownload: (QuranTranslation) -> Unit,
    onDismiss: () -> Unit,
) {
    val state by translations.state.collectAsStateWithLifecycle()
    val locale = currentLocale()

    fun choose(selection: String) {
        translations.select(selection)
        onDismiss()
        val resolved =
            if (selection ==
                QuranTranslation.AUTO
            ) {
                translations.state.value.active
            } else {
                QuranTranslation.of(selection)
            }
        if (resolved != null && !translations.state.value.isInstalled(resolved.id)) onDownload(resolved)
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.translation)) },
        text = {
            Column(
                Modifier.verticalScroll(rememberScrollState()).selectableGroup().testTag("quran-translation-picker"),
            ) {
                Option(
                    stringResource(R.string.auto),
                    null,
                    state.selection == QuranTranslation.AUTO,
                    false,
                    "quran-translation-auto",
                ) {
                    choose(QuranTranslation.AUTO)
                }
                Option(
                    stringResource(R.string.none),
                    null,
                    state.selection == QuranTranslation.NONE,
                    false,
                    "quran-translation-none",
                ) {
                    choose(QuranTranslation.NONE)
                }
                for (translation in QuranTranslation.catalog) {
                    Option(
                        translation.languageName(locale),
                        translation.translator,
                        state.selection == translation.id,
                        !state.isInstalled(translation.id),
                        "quran-translation-option-${translation.id}",
                    ) { choose(translation.id) }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun Option(
    title: String,
    subtitle: String?,
    selected: Boolean,
    needsDownload: Boolean,
    tag: String,
    onClick: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = subtitle?.let { { Text(it) } },
        leadingContent = { RadioButton(selected = selected, onClick = null) },
        trailingContent =
            if (needsDownload) {
                (
                    {
                        Icon(
                            Icons.Outlined.Download,
                            stringResource(R.string.download),
                        )
                    }
                )
            } else {
                null
            },
        modifier = Modifier.selectable(selected, role = Role.RadioButton, onClick = onClick).testTag(tag),
    )
}

/** Swift `QuranDownloadView`: download the translations pack, then close once [requested] is installed. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuranDownloadSheet(
    translations: QuranTranslations,
    requested: QuranTranslation,
    onDismiss: () -> Unit,
) {
    val state by translations.state.collectAsStateWithLifecycle()
    val dismiss by rememberUpdatedState(onDismiss)
    val activity = LocalActivity.current
    LaunchedEffect(state.revision) { if (state.isInstalled(requested.id)) dismiss() }
    val failed = state.downloadState == DownloadState.Failed
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.quran_translations), style = MaterialTheme.typography.titleLarge)
            Text(
                stringResource(
                    if (failed) {
                        R.string.unable_to_download_please_try_again
                    } else {
                        R.string.download_translations_to_read_offline
                    },
                ),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            if (state.isDownloading) {
                AssetDownloadProgress(state.progress, state.downloadState == DownloadState.Installing, state.preparing)
                ConfirmationPrompt(state.needsConfirmation) { activity?.let(translations::confirm) }
            } else {
                AssetDownloadButton(
                    AssetDownloadSizes.QURAN_TRANSLATIONS,
                    retry = failed,
                    onClick = { translations.download(requested.id) },
                    enabled = !state.busy,
                    modifier = Modifier.testTag("quran-download"),
                )
            }
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) }
        }
    }
}

/** Play is waiting for Wi-Fi or the user's confirmation. */
@Composable
fun ConfirmationPrompt(
    waiting: Boolean,
    onContinue: () -> Unit,
) {
    if (!waiting) return
    Text(
        stringResource(R.string.download_waiting_for_confirmation),
        style = MaterialTheme.typography.bodySmall,
        textAlign = TextAlign.Center,
    )
    TextButton(onClick = onContinue) { Text(stringResource(R.string.continue_text)) }
}
