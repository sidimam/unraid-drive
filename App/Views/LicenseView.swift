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
            Text("Third-party software: on Apple TV, formats the system cannot play are decoded by libmpv and FFmpeg (LGPL 2.1 or later) shipped through MPVKit; source code and licenses at github.com/mpvkit/MPVKit.").font(.footnote).foregroundStyle(.secondary).padding([.horizontal, .bottom])
        }
        .navigationTitle("License")
        .inlineNavigationTitle()
    }
}
