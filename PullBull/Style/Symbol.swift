import SwiftUI

extension Image {
    /// A symbol by name: one of the app's own custom symbols (`pullbull.*`, in the asset catalog) or an SF Symbol.
    /// Lets glyphs travel as plain strings whichever set they come from.
    init(symbol name: String) {
        if name.hasPrefix("pullbull.") {
            self.init(name)
        } else {
            self.init(systemName: name)
        }
    }
}
