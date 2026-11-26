package com.aljaroudi.muntathir.core.app

import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/** A destination that can be a tab shortcut or a Tools entry. Port of Swift `AppTool`; titles and icons are app resources. */
enum class AppTool(
    /** Swift raw value, used in stored preferences. */
    val id: String,
) {
    Calendar("calendar"),
    Events("events"),
    Quran("quran"),
    Hadith("hadith"),
    Supplications("supplications"),
    Sermons("sermons"),
    Dictionary("dictionary"),
    Rulings("rulings"),
    Figures("figures"),
    Tasbih("tasbih"),
    Rakaat("rakaat"),
    PrayerProgress("prayerProgress"),
    Qibla("qibla"),
    ;

    /** iOS accessibility identifier, reused as the Compose test tag. */
    val testTag: String
        get() =
            when (this) {
                Quran -> "holy-quran"
                Rakaat -> "rakaat-tracker"
                PrayerProgress -> "prayer-progress"
                else -> id
            }

    companion object {
        const val MAXIMUM_SHORTCUTS = 3

        val groups: List<List<AppTool>> =
            listOf(
                listOf(Quran, Hadith, Supplications, Sermons, Dictionary),
                listOf(Rulings),
                listOf(Calendar, Events, Figures),
                listOf(Qibla, Rakaat, Tasbih, PrayerProgress),
            )

        fun of(id: String): AppTool? = entries.firstOrNull { it.id == id }

        /** Drops unknown and repeated identifiers, keeping order, and caps the list at [MAXIMUM_SHORTCUTS]. */
        fun normalized(ids: List<String>): List<AppTool> = ids.mapNotNull(::of).distinct().take(MAXIMUM_SHORTCUTS)
    }
}

/** Stored as raw strings; decoding normalizes, so unknown or extra shortcuts never fail the whole blob. */
internal object ShortcutsSerializer : KSerializer<List<AppTool>> {
    private val strings = ListSerializer(String.serializer())
    override val descriptor: SerialDescriptor = strings.descriptor

    override fun serialize(
        encoder: Encoder,
        value: List<AppTool>,
    ) = strings.serialize(encoder, value.map { it.id })

    override fun deserialize(decoder: Decoder): List<AppTool> = AppTool.normalized(strings.deserialize(decoder))
}
