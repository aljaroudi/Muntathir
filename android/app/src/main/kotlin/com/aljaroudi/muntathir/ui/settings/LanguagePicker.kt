package com.aljaroudi.muntathir.ui.settings

import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.core.os.LocaleListCompat
import com.aljaroudi.muntathir.R
import java.util.Locale

/** The 15 interface languages, matching `res/values-*` and the iOS catalog. */
val APP_LANGUAGES =
    listOf("ar", "en", "de", "es", "fa", "fr", "id", "it", "ja", "ms", "ru", "tr", "ur", "zh-Hans", "zh-Hant")

/** A language's name in that language, e.g. "العربية". */
fun languageName(tag: String): String {
    val locale = Locale.forLanguageTag(tag)
    return locale.getDisplayName(locale).replaceFirstChar { it.titlecase(locale) }
}

/** The per-app language tag, or `null` when following the system. */
fun currentLanguage(): String? =
    AppCompatDelegate.getApplicationLocales()[0]?.let { selected ->
        APP_LANGUAGES.firstOrNull {
            Locale.forLanguageTag(it).language == selected.language &&
                matchesScript(it, selected)
        }
    }

private fun matchesScript(
    tag: String,
    locale: Locale,
): Boolean {
    if (!tag.startsWith("zh")) return true
    val script = locale.script.ifEmpty { if (locale.country in setOf("TW", "HK", "MO")) "Hant" else "Hans" }
    return tag.endsWith(script)
}

/**
 * Swift `AppLanguageLink`, as an in-app picker: Android applies the per-app language immediately through
 * AppCompat, which recreates the activity (onboarding resumes on the same step).
 */
@Composable
fun AppLanguageRow(modifier: Modifier = Modifier) {
    var open by rememberSaveable { mutableStateOf(false) }
    val current = currentLanguage()
    ListItem(
        headlineContent = { Text(stringResource(R.string.app_language)) },
        supportingContent = { Text(current?.let(::languageName) ?: stringResource(R.string.system_default)) },
        leadingContent = { Icon(Icons.Outlined.Language, contentDescription = null) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = modifier.testTag("app-language").selectable(selected = false, role = Role.Button) { open = true },
    )
    if (open) {
        LanguageDialog(current, onDismiss = { open = false }) { tag ->
            open = false
            AppCompatDelegate.setApplicationLocales(
                if (tag == null) LocaleListCompat.getEmptyLocaleList() else LocaleListCompat.forLanguageTags(tag),
            )
        }
    }
}

@Composable
private fun LanguageDialog(
    current: String?,
    onDismiss: () -> Unit,
    onSelect: (String?) -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
        title = { Text(stringResource(R.string.choose_a_language)) },
        text = {
            LazyColumn {
                items(listOf<String?>(null) + APP_LANGUAGES) { tag ->
                    ListItem(
                        headlineContent = { Text(tag?.let(::languageName) ?: stringResource(R.string.system_default)) },
                        leadingContent = { RadioButton(selected = tag == current, onClick = null) },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .selectable(selected = tag == current, role = Role.RadioButton) { onSelect(tag) },
                    )
                }
            }
        },
    )
}
