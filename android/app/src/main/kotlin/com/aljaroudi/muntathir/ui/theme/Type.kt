package com.aljaroudi.muntathir.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.aljaroudi.muntathir.R

val Typography = Typography()

/** KFGQPC Hafs, converted losslessly from the iOS `QPCHafs.woff2`. Quran text only. */
val QuranFont = FontFamily(Font(R.font.qpc_hafs))

/** Arabic Hadith and supplication text, same as iOS. */
val HadithFont =
    FontFamily(
        Font(R.font.lateef_light, FontWeight.Light),
        Font(R.font.lateef_regular, FontWeight.Normal),
    )
