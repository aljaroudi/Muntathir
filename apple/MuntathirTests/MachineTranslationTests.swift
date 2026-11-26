import Foundation
@testable import Muntathir
import Testing

struct MachineTranslationTests {
    private let arabic = Locale.Language(identifier: "ar")

    @Test func skipsLanguagesTheReaderPrefers() {
        #expect(MachineTranslation.target(from: arabic, preferred: ["ar", "en"]) == nil)
        #expect(MachineTranslation.target(from: arabic, preferred: ["en-US", "ar-SA"]) == nil)
        #expect(MachineTranslation.target(from: Locale.Language(identifier: "fr"), preferred: ["fr-CA"]) == nil)
    }

    @Test func targetsTheTopPreferredLanguage() {
        #expect(MachineTranslation.target(from: arabic, preferred: ["en-US"])?.languageCode == "en")
        #expect(MachineTranslation.target(from: Locale.Language(identifier: "fa"), preferred: ["ar", "en"])?.languageCode == "ar")
        #expect(MachineTranslation.target(from: arabic, preferred: []) == nil)
    }

    @Test func splitsParagraphs() {
        #expect(MachineTranslation.paragraphs("One\n\n  Two \n") == ["One", "Two"])
    }
}
