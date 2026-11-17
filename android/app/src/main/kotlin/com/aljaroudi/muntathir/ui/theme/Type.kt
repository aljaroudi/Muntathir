package com.aljaroudi.muntathir.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.aljaroudi.muntathir.R

/**
 * IBM Plex Sans Arabic, the app's interface font (iOS uses the system font). Bundled rather than downloaded so it
 * renders offline, on first launch and in home screen widgets. Reading text keeps [ReaderBodyFont].
 */
val AppFont =
    FontFamily(
        Font(R.font.ibm_plex_sans_arabic_regular, FontWeight.Normal),
        Font(R.font.ibm_plex_sans_arabic_medium, FontWeight.Medium),
        Font(R.font.ibm_plex_sans_arabic_semibold, FontWeight.SemiBold),
        Font(R.font.ibm_plex_sans_arabic_bold, FontWeight.Bold),
    )

/** Translations and other non-Arabic reading text: the system font, like iOS readers. */
val ReaderBodyFont = FontFamily.Default

/** KFGQPC Hafs, converted losslessly from the iOS `QPCHafs.woff2`. Quran text only. */
val QuranFont = FontFamily(Font(R.font.qpc_hafs))

/** Arabic Hadith and supplication text, same as iOS. */
val HadithFont =
    FontFamily(
        Font(R.font.lateef_light, FontWeight.Light),
        Font(R.font.lateef_regular, FontWeight.Normal),
    )

val Typography =
    Typography().run {
        fun TextStyle.app() = copy(fontFamily = AppFont)
        copy(
            displayLarge = displayLarge.app(),
            displayMedium = displayMedium.app(),
            displaySmall = displaySmall.app(),
            headlineLarge = headlineLarge.app(),
            headlineMedium = headlineMedium.app(),
            headlineSmall = headlineSmall.app(),
            titleLarge = titleLarge.app(),
            titleMedium = titleMedium.app(),
            titleSmall = titleSmall.app(),
            bodyLarge = bodyLarge.app(),
            bodyMedium = bodyMedium.app(),
            bodySmall = bodySmall.app(),
            labelLarge = labelLarge.app(),
            labelMedium = labelMedium.app(),
            labelSmall = labelSmall.app(),
        )
    }
