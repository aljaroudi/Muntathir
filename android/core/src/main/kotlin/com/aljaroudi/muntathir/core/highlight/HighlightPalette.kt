package com.aljaroudi.muntathir.core.highlight

/** The first `count` colors in the user's order form the quick picker. Swift `HighlightPalette`. */
object HighlightPalette {
    /** Serialized names (`yellow,green,…`) in declaration order. */
    val names: List<String> = HighlightColor.entries.map { it.serialName }
    val defaultOrder: String = names.joinToString(",")
    const val DEFAULT_COUNT = 6

    fun validOrder(value: String): Boolean {
        val parts = value.split(",")
        return parts.size == names.size && parts.toSet() == names.toSet()
    }

    fun colors(
        order: String,
        count: Int = HighlightColor.entries.size,
    ): List<HighlightColor> {
        val valid = if (validOrder(order)) order else defaultOrder
        return valid
            .split(",")
            .mapNotNull { name -> HighlightColor.entries.firstOrNull { it.serialName == name } }
            .take(count.coerceIn(1, HighlightColor.entries.size))
    }

    fun order(colors: List<HighlightColor>): String = colors.joinToString(",") { it.serialName }
}

/** The stored name, matching Swift's raw values. */
val HighlightColor.serialName: String get() = name.lowercase()
