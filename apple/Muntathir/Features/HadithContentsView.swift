import SwiftUI

struct HadithContentsView: View {
    let book: HadithCollection
    let reader: HadithReader
    var restoredState: HadithSessionState?

    var body: some View {
        HadithView(reader: reader, initialRequest: HadithRequest(collectionID: book.id), restoredState: restoredState)
    }
}
