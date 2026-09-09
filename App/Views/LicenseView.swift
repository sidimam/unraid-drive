import SwiftUI

/// The MIT license the app ships under (bundled copy of the repository LICENSE file).
struct LicenseView: View {
    private var text: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"), let s = try? String(contentsOf: url, encoding: .utf8) else {
            return "MIT License — see github.com/sidimam/unraid-drive/blob/main/LICENSE"
        }
        return s
    }
    var body: some View {
        ScrollView {
            Text(text).font(.system(.footnote, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("License")
        .inlineNavigationTitle()
    }
}
