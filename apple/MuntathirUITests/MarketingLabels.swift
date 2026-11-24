import XCTest

// Shared by the iOS (MarketingScreenshotTests) and Mac (MacMarketingScreenshotTests) store captures.

private func captureLocale(_ identifier: String) -> Locale {
    Locale(identifier: identifier.isEmpty ? "en-US" : identifier)
}

/// Calendar, Next month, Tools, no-translation option, Highlight — in the capture language.
func marketingLabels(for identifier: String) throws -> [String] {
    let locale = captureLocale(identifier)
    let language = try XCTUnwrap(locale.language.languageCode?.identifier)
        + (locale.language.languageCode?.identifier == "zh" ? "-\(locale.language.script!.identifier)" : "")
    return try XCTUnwrap([
        "en": ["Calendar", "Next month", "Tools", "None", "Highlight"],
        "ar": ["التقويم", "الشهر التالي", "الأدوات", "بدون ترجمة", "تظليل"],
        "fa": ["تقویم", "ماه بعد", "ابزارها", "هیچ‌کدام", "برجسته‌سازی"],
        "fr": ["Calendrier", "Mois suivant", "Outils", "Aucune", "Surligner"],
        "de": ["Kalender", "Nächster Monat", "Werkzeuge", "Keine", "Markieren"],
        "id": ["Kalender", "Bulan berikutnya", "Alat", "Tidak ada", "Sorot"],
        "it": ["Calendario", "Mese successivo", "Strumenti", "Nessuna", "Evidenzia"],
        "ja": ["カレンダー", "次の月", "ツール", "なし", "ハイライト"],
        "ms": ["Kalendar", "Bulan seterusnya", "Alatan", "Tiada", "Serlahkan"],
        "ru": ["Календарь", "Следующий месяц", "Инструменты", "Нет", "Выделить"],
        "es": ["Calendario", "Mes siguiente", "Herramientas", "Ninguna", "Resaltar"],
        "tr": ["Takvim", "Sonraki ay", "Araçlar", "Yok", "Vurgula"],
        "ur": ["تقویم", "اگلا مہینہ", "اوزار", "کوئی نہیں", "نمایاں کریں"],
        "zh-Hans": ["日历", "下个月", "工具", "无", "高亮"],
        "zh-Hant": ["行事曆", "下個月", "工具", "無", "螢光標記"],
    ][language], "Unsupported capture language: \(identifier)")
}

/// The Quran translation picker row the capture selects for this language.
func marketingTranslationLabel(for identifier: String) throws -> String {
    let locale = captureLocale(identifier)
    let language = locale.language.languageCode?.identifier ?? "en"
    let translationLanguage = switch language {
    case "de", "ru", "es", "fa": language
    case "zh": locale.language.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans"
    default: "en"
    }
    return language == "ar" ? try marketingLabels(for: identifier)[3] : try XCTUnwrap(locale.localizedString(forIdentifier: translationLanguage))
}
