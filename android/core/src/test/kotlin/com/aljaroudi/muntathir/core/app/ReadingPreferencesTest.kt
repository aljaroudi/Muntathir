package com.aljaroudi.muntathir.core.app

import com.aljaroudi.muntathir.core.highlight.HighlightColor
import com.aljaroudi.muntathir.core.highlight.HighlightPalette
import com.aljaroudi.muntathir.core.quran.QuranTranslation
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Validation from Swift `ReadingPreferencesSyncTests`, palette and translation selection tests. */
class ReadingPreferencesTest {
    @Test
    fun hadithChoicesUseTheSwiftKeysAndValidation() {
        val chosen = ReadingPreferences(hadithEnglishEnabled = false, supplicationTranslation = "ur")
        assertEquals(chosen, ReadingPreferences.decode(chosen.encode()))
        assertTrue("\"hadithEnglishEnabled.v2\":false" in chosen.encode())
        assertTrue("\"supplicationTranslation.v2\":\"ur\"" in chosen.encode())
        val invalid = """{"hadithEnglishEnabled.v2":"yes","supplicationTranslation.v2":"ur:edition"}"""
        assertEquals(ReadingPreferences(), ReadingPreferences.decode(invalid))
        // Unchosen, English follows the device languages.
        assertTrue(ReadingPreferences().showsHadithEnglish(listOf(Locale.ENGLISH)))
        assertFalse(ReadingPreferences().showsHadithEnglish(listOf(Locale.forLanguageTag("ar"), Locale.ENGLISH)))
        assertFalse(chosen.showsHadithEnglish(listOf(Locale.ENGLISH)))
    }

    @Test
    fun roundTripsAndRejectsInvalidValuesKeyByKey() {
        val custom =
            ReadingPreferences(
                readingSizePercent = 140,
                quranReadingMode = QuranReadingMode.Mushaf,
                quranTranslationSelection = "de.bubenheim",
                highlightColorCount = 12,
                highlightColorOrder = HighlightPalette.order(HighlightColor.entries.reversed()),
                savedGroupByDate = true,
                showArabicDiacritics = false,
            )
        assertEquals(custom, ReadingPreferences.decode(custom.encode()))
        val invalid =
            """{"readingSizePercent":999,"quranReadingMode":"pages","quranTranslationSelection.v2":"xx.none",
            |"highlightColorCount":true,"highlightColorOrder":"yellow,yellow","savedGroupByDate":1}
            """.trimMargin()
        assertEquals(ReadingPreferences(), ReadingPreferences.decode(invalid))
        assertEquals(ReadingPreferences(), ReadingPreferences.decode("not json"))
        // Strings aren't numbers and numbers aren't booleans, as with NSNumber/CFBoolean checks.
        val mistyped = """{"readingSizePercent":"120","savedGroupByDate":"true","highlightColorCount":6.5}"""
        assertEquals(ReadingPreferences(), ReadingPreferences.decode(mistyped))
        val partial = """{"readingSizePercent":120,"quranTranslationSelection.v2":""}"""
        assertEquals(
            ReadingPreferences(readingSizePercent = 120, quranTranslationSelection = QuranTranslation.NONE),
            ReadingPreferences.decode(partial),
        )
        assertEquals(
            ReadingPreferences(),
            ReadingPreferences(readingSizePercent = 70, highlightColorCount = 0).validated(),
        )
    }

    @Test
    fun paletteDefaultsOrderingAndValidation() {
        assertEquals(
            listOf(
                HighlightColor.Yellow,
                HighlightColor.Green,
                HighlightColor.Blue,
                HighlightColor.Pink,
                HighlightColor.Purple,
                HighlightColor.Orange,
            ),
            ReadingPreferences().highlightColors,
        )
        val order = "cyan," + HighlightPalette.names.filter { it != "cyan" }.joinToString(",")
        assertTrue(HighlightPalette.validOrder(order))
        assertEquals(listOf(HighlightColor.Cyan, HighlightColor.Yellow), HighlightPalette.colors(order, 2))
        assertEquals(12, HighlightPalette.colors(order).size)
        assertFalse(HighlightPalette.validOrder(HighlightPalette.defaultOrder + ","))
        assertFalse(HighlightPalette.validOrder("yellow"))
        assertEquals(HighlightPalette.colors(HighlightPalette.defaultOrder, 1), HighlightPalette.colors("bad", 0))
    }

    @Test
    fun translationLanguageDefaultsAndSelection() {
        val catalog = QuranTranslation.catalog
        assertEquals(13, catalog.size)
        assertEquals(12, QuranTranslation.downloadable.size)
        assertEquals("en.qarai", QuranTranslation.preferred(catalog, Locale.UK)?.id)
        assertNull(QuranTranslation.preferred(catalog, Locale.forLanguageTag("ar")))
        assertEquals("es.bornez", QuranTranslation.preferred(catalog, Locale.forLanguageTag("es"))?.id)
        assertEquals("zh.majian", QuranTranslation.preferred(catalog, Locale.forLanguageTag("zh-Hant-TW"))?.id)
        assertEquals("zh.majian", QuranTranslation.preferred(catalog, Locale.forLanguageTag("zh-TW"))?.id)
        assertEquals("zh.jian", QuranTranslation.preferred(catalog, Locale.forLanguageTag("zh-CN"))?.id)
        val english = listOf(Locale.ENGLISH)
        assertEquals("en.qarai", QuranTranslation.resolve(QuranTranslation.AUTO, english)?.id)
        assertNull(QuranTranslation.resolve(QuranTranslation.NONE, english))
        assertEquals("de.bubenheim", QuranTranslation.resolve(QuranTranslation.AUTO, listOf(Locale.GERMAN))?.id)
        // Arabic stops the search rather than falling through to English.
        assertNull(QuranTranslation.resolve(QuranTranslation.AUTO, listOf(Locale.forLanguageTag("ar"), Locale.ENGLISH)))
        assertEquals(
            "en.qarai",
            QuranTranslation.resolve(QuranTranslation.AUTO, listOf(Locale.JAPANESE, Locale.ENGLISH))?.id,
        )
        assertEquals("fr.hamidullah", QuranTranslation.resolve("fr.hamidullah", english)?.id)
    }
}
