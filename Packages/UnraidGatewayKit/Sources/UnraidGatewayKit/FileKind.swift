import Foundation

/// What a client can do with a file, decided by its extension: Apple formats play with AVFoundation,
/// other media with libmpv, text-like files, PDF, EPUB, comics and archives have viewers, the rest
/// only shows details.
public enum FileKind: String, Sendable {
    case folder, video, audio, mpvVideo, mpvAudio, image, text, pdf, epub, comic, archive, other

    private static let videoExt: Set<String> = ["mp4", "m4v", "mov", "hevc", "ts", "m3u8"]
    private static let audioExt: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "caf"]
    private static let mpvVideoExt: Set<String> = ["mkv", "avi", "wmv", "flv", "webm", "mpg", "mpeg", "m2ts", "mts", "vob", "ogv", "ogm", "3gp", "divx", "rm", "rmvb", "asf", "mp2", "iso", "ts2"]
    private static let mpvAudioExt: Set<String> = ["flac", "ogg", "oga", "opus", "wma", "ape", "mka", "dsf", "dff", "ac3", "dts", "wv", "tta", "mpc", "aif"]
    private static let imageExt: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp"]
    private static let textExt: Set<String> = ["txt", "nfo", "md", "markdown", "json", "xml", "log", "csv", "tsv", "ini", "conf", "cfg", "yaml", "yml", "toml", "sh", "py", "js", "ts", "swift", "go", "rb", "php", "html", "htm", "css", "srt", "sub", "ass", "vtt", "plist", "rtf", "text", "readme", "diz", "sfv", "m3u", "cue", "url", "env", "gitignore", "lua", "sql", "c", "h", "cpp", "java", "kt", "rs", "bat", "ps1", "tex", "bib", "opml"]
    private static let comicExt: Set<String> = ["cbz"]
    private static let archiveExt: Set<String> = ["zip", "epub2"]

    public static func of(_ e: FSEntry) -> FileKind { of(name: e.name, isDirectory: e.isDirectory) }

    public static func of(name: String, isDirectory: Bool) -> FileKind {
        if isDirectory { return .folder }
        let ext = (name as NSString).pathExtension.lowercased()
        if ext.isEmpty, name.uppercased() == name || name.lowercased().hasPrefix("readme") { return .text }
        if videoExt.contains(ext) { return .video }; if audioExt.contains(ext) { return .audio }
        if mpvVideoExt.contains(ext) { return .mpvVideo }; if mpvAudioExt.contains(ext) { return .mpvAudio }
        if imageExt.contains(ext) { return .image }; if textExt.contains(ext) { return .text }
        if ext == "pdf" { return .pdf }; if ext == "epub" { return .epub }
        if comicExt.contains(ext) { return .comic }; if archiveExt.contains(ext) { return .archive }
        return .other
    }

    public var symbol: String {
        switch self {
        case .folder: return "folder.fill"
        case .video, .mpvVideo: return "film"
        case .audio, .mpvAudio: return "music.note"
        case .image: return "photo"
        case .text: return "doc.text"
        case .pdf: return "doc.richtext"
        case .epub: return "book"
        case .comic: return "book.pages"
        case .archive: return "doc.zipper"
        case .other: return "doc"
        }
    }
    /// Localization key of the human-readable kind (looked up in the app catalog).
    public var labelKey: String {
        switch self {
        case .folder: return "Folder"
        case .video, .mpvVideo: return "Video"
        case .audio, .mpvAudio: return "Audio"
        case .image: return "Image"
        case .text: return "Text"
        case .pdf: return "PDF"
        case .epub: return "E-book"
        case .comic: return "Comic"
        case .archive: return "Archive"
        case .other: return "File"
        }
    }
    public var isMedia: Bool { [.video, .audio, .mpvVideo, .mpvAudio].contains(self) }
    /// Kinds the apps can show with a viewer of their own.
    public var hasViewer: Bool { self != .other && self != .folder }
    /// Playable by AVFoundation without help.
    public var isNativeMedia: Bool { self == .video || self == .audio }
    /// Needs libmpv.
    public var needsMPV: Bool { self == .mpvVideo || self == .mpvAudio }
}

