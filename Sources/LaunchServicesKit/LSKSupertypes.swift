import Foundation

/// infat 认可的标准回退类型（supertype）。
/// 完整移植自 infat-lib `uti.rs` — rawValue 为 kebab-case 名称（与 infat CLI/配置兼容），
/// `utiString` 为对应的 macOS UTI。
public enum SuperType: String, CaseIterable, Sendable {
    // Text & Documents
    case text
    case plainText = "plain-text"
    case csv
    case json
    case xml
    case yaml
    case html
    case markdown
    case rtf

    // Images
    case image
    case rawImage = "raw-image"
    case png
    case jpeg
    case gif
    case tiff
    case svg
    case webp
    case heic
    case heif
    case bmp

    // Audio
    case audio
    case mp3
    case wav
    case aiff
    case midi
    case mp4Audio = "mp4-audio"
    case appleProtectedMp4Audio = "apple-protected-mp4-audio"
    case flac
    case oggAudio = "ogg-audio"
    case ac3Audio = "ac3-audio"
    case aacAudio = "aac-audio"

    // Video
    case video
    case mpeg2TransportStream = "mpeg2-transport-stream"
    case movie
    case quicktimeMovie = "quicktime-movie"
    case mp4Movie = "mp4-movie"
    case appleProtectedMp4Video = "apple-protected-mp4-video"
    case mpeg
    case mpeg2Video = "mpeg2-video"
    case avi
    case dvMovie = "dv-movie"
    case realMedia = "real-media"
    case realAudio = "real-audio"
    case webm
    case matroska
    case m3uPlaylist = "m3u-playlist"

    // Archives
    case archive
    case zip
    case gzip
    case tar
    case bz2
    case appleArchive = "apple-archive"

    // Source Code
    case sourcecode
    case typeScript = "typescript"
    case cSource = "c-source"
    case cHeader = "c-header"
    case cppSource = "cpp-source"
    case cppHeader = "cpp-header"
    case objcSource = "objc-source"
    case objcPlusPlusSource = "objc-plus-plus-source"
    case swiftSource = "swift-source"
    case shell
    case makefile
    case javascript
    case pythonScript = "python-script"
    case rubyScript = "ruby-script"
    case perlScript = "perl-script"
    case phpScript = "php-script"
    case appleScript = "apple-script"
    case assemblySource = "assembly-source"

    // System
    case data
    case directory
    case folder
    case symlink
    case executable
    case unixExecutable = "unix-executable"
    case appBundle = "app-bundle"
    case framework
    case diskImage = "disk-image"
    case volume
    case mountPoint = "mount-point"
    case aliasFile = "alias-file"

    // 3D Content
    case threeDContent = "3d-content"
    case usd
    case usdz
    case realityFile = "reality-file"
    case sceneKitScene = "scenekit-scene"

    // Fonts
    case font

    // Cryptographic
    case pkcs12
    case x509Certificate = "x509-certificate"

    // URLs
    case url
    case fileUrl = "file-url"
    case urlBookmarkData = "url-bookmark-data"

    // Property Lists
    case propertyList = "property-list"
    case xmlPropertyList = "xml-property-list"
    case binaryPropertyList = "binary-property-list"

    // Misc
    case log
    case bookmark
    case internetLocation = "internet-location"
    case internetShortcut = "internet-shortcut"

    // Apple-specific
    case defaultAppWebBrowser = "default-app-web-browser"
    case defaultAppMailClient = "default-app-mail-client"
    case m4vVideo = "m4v-video"
    case m4aAudio = "m4a-audio"

    /// 对应的 macOS UTI 字符串（与 infat `uti_string()` 逐一对应）
    public var utiString: String {
        switch self {
        // Text & Documents
        case .text: return "public.text"
        case .plainText: return "public.plain-text"
        case .csv: return "public.comma-separated-values-text"
        case .json: return "public.json"
        case .xml: return "public.xml"
        case .yaml: return "public.yaml"
        case .html: return "public.html"
        case .markdown: return "net.daringfireball.markdown"
        case .rtf: return "public.rtf"

        // Images
        case .image: return "public.image"
        case .rawImage: return "public.camera-raw-image"
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        case .gif: return "com.compuserve.gif"
        case .tiff: return "public.tiff"
        case .svg: return "public.svg-image"
        case .webp: return "org.webmproject.webp"
        case .heic: return "public.heic"
        case .heif: return "public.heif"
        case .bmp: return "com.microsoft.bmp"

        // Audio
        case .audio: return "public.audio"
        case .mp3: return "public.mp3"
        case .wav: return "com.microsoft.waveform-audio"
        case .aiff: return "public.aiff-audio"
        case .midi: return "public.midi-audio"
        case .mp4Audio: return "public.mpeg-4-audio"
        case .appleProtectedMp4Audio: return "com.apple.protected-mpeg-4-audio"
        case .flac: return "org.xiph.flac"
        case .oggAudio: return "org.xiph.ogg-audio"
        case .ac3Audio: return "public.ac3-audio"
        case .aacAudio: return "public.aac-audio"

        // Video
        case .video: return "public.video"
        case .mpeg2TransportStream: return "mpeg2-transport-stream"
        case .movie: return "public.movie"
        case .quicktimeMovie: return "com.apple.quicktime-movie"
        case .mp4Movie: return "public.mpeg-4"
        case .appleProtectedMp4Video: return "com.apple.protected-mpeg-4-video"
        case .mpeg: return "public.mpeg"
        case .mpeg2Video: return "public.mpeg-2-video"
        case .avi: return "public.avi"
        case .dvMovie: return "public.dv-movie"
        case .realMedia: return "com.real.realmedia"
        case .realAudio: return "com.real.realaudio"
        case .webm: return "org.webmproject.webm"
        case .matroska: return "org.matroska.mkv"
        case .m3uPlaylist: return "m3u-playlist"

        // Archives
        case .archive: return "public.archive"
        case .zip: return "public.zip-archive"
        case .gzip: return "org.gnu.gnu-zip-archive"
        case .tar: return "public.tar-archive"
        case .bz2: return "public.bzip2-archive"
        case .appleArchive: return "com.apple.archive"

        // Source Code
        case .sourcecode: return "public.source-code"
        case .typeScript: return "com.microsoft.typescript"
        case .cSource: return "public.c-source"
        case .cHeader: return "public.c-header"
        case .cppSource: return "public.c-plus-plus-source"
        case .cppHeader: return "public.c-plus-plus-header"
        case .objcSource: return "public.objective-c-source"
        case .objcPlusPlusSource: return "public.objective-c-plus-plus-source"
        case .swiftSource: return "public.swift-source"
        case .shell: return "public.shell-script"
        case .makefile: return "public.make-source"
        case .javascript: return "com.netscape.javascript-source"
        case .pythonScript: return "public.python-script"
        case .rubyScript: return "public.ruby-script"
        case .perlScript: return "public.perl-script"
        case .phpScript: return "public.php-script"
        case .appleScript: return "com.apple.applescript.text"
        case .assemblySource: return "public.assembly-source"

        // System
        case .data: return "public.data"
        case .directory: return "public.directory"
        case .folder: return "public.folder"
        case .symlink: return "public.symlink"
        case .executable: return "public.executable"
        case .unixExecutable: return "public.unix-executable"
        case .appBundle: return "com.apple.application-bundle"
        case .framework: return "com.apple.framework"
        case .diskImage: return "public.disk-image"
        case .volume: return "public.volume"
        case .mountPoint: return "com.apple.mount-point"
        case .aliasFile: return "com.apple.alias-file"

        // 3D Content
        case .threeDContent: return "public.3d-content"
        case .usd: return "com.pixar.universal-scene-description"
        case .usdz: return "com.pixar.universal-scene-description-mobile"
        case .realityFile: return "com.apple.reality"
        case .sceneKitScene: return "com.apple.scenekit.scene"

        // Fonts
        case .font: return "public.font"

        // Cryptographic
        case .pkcs12: return "com.rsa.pkcs-12"
        case .x509Certificate: return "public.x509-certificate"

        // URLs
        case .url: return "public.url"
        case .fileUrl: return "public.file-url"
        case .urlBookmarkData: return "com.apple.bookmark"

        // Property Lists
        case .propertyList: return "com.apple.property-list"
        case .xmlPropertyList: return "com.apple.xml-property-list"
        case .binaryPropertyList: return "com.apple.binary-property-list"

        // Misc
        case .log: return "public.log"
        case .bookmark: return "public.bookmark"
        case .internetLocation: return "com.apple.web-internet-location"
        case .internetShortcut: return "com.microsoft.internet-shortcut"

        // Apple-specific
        case .defaultAppWebBrowser: return "com.apple.default-app.web-browser"
        case .defaultAppMailClient: return "com.apple.default-app.mail-client"
        case .m4vVideo: return "com.apple.m4v-video"
        case .m4aAudio: return "com.apple.m4a-audio"
        }
    }

    /// infat CLI 中接受的别名（与 `uti.rs` 的 FromStr 逐条对应）
    private static let aliases: [String: SuperType] = [
        "md": .markdown,
        "ts": .typeScript,
        "comma-separated-text": .csv,
        "mpeg4-movie": .mp4Movie,
        "mp4": .mp4Movie,
        "m3u": .m3uPlaylist,
    ]

    /// 解析用户输入（kebab-case、大小写不敏感、下划线归一为连字符）
    public static func parse(_ input: String) -> SuperType? {
        let normalized = input.lowercased().replacingOccurrences(of: "_", with: "-")
        return SuperType(rawValue: normalized) ?? aliases[normalized]
    }

    /// 按 UTI 反查（对应 infat 的 `from_uti_string`）
    public static func from(utiString: String) -> SuperType? {
        SuperType.allCases.first { $0.utiString == utiString }
    }
}
