package com.aljaroudi.muntathir.core.quran

import com.aljaroudi.muntathir.core.text.QuranSearchText

/** Verse references for display. Port of Swift `QuranReference`. */
object QuranReference {
    private val isolateStart = Char(0x2066)
    private val isolateEnd = Char(0x2069)

    /**
     * `"2:255"`, or in Arabic `"البقرة 2:255"` with the numeric run isolated so right-to-left text can't
     * reverse chapter and verse.
     */
    fun display(
        reference: String,
        language: String,
        names: Map<Int, String>,
    ): String {
        if (language != "ar") return reference
        val surah = QuranSearchText.reference(reference)?.first ?: return reference
        val name = names[surah] ?: return reference
        return "$name $isolateStart$reference$isolateEnd"
    }
}
