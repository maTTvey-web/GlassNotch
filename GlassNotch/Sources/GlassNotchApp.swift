import SwiftUI
import Combine
import AppKit
import EventKit
import IOKit.ps
import UniformTypeIdentifiers
import ServiceManagement

// MARK: - GlassNotch geometry
enum Metrics {
    static var screen: NSScreen { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main! }
    static var h: CGFloat { screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32 }
    static var w: CGFloat {
        let s = screen
        if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea { return s.frame.width - l.width - r.width }
        return 190
    }
}

enum GlassNotchLayout {
    static var openW: CGFloat { CGFloat(UserDefaults.standard.object(forKey: "openW") as? Double ?? 680) }
    static var openH: CGFloat { CGFloat(UserDefaults.standard.object(forKey: "openH") as? Double ?? 195) }
    static var botR: CGFloat { CGFloat(UserDefaults.standard.object(forKey: "openRadius") as? Double ?? 28) }
    static let wing: CGFloat = 56     // side "wings" next to the closed notch (artwork / equalizer)
}

// MARK: - Music
enum Action { case prev, toggle, next, seek(Double) }

struct Track: Equatable {
    var app, title, artist: String
    var playing: Bool
    var art: URL?
    var pos: Double, dur: Double
    var web: Browser? = nil
    var wi = 0, ti = 0
    var info = ""
    var progress: Double { dur > 0 ? min(pos / dur, 1) : 0 }
}

@discardableResult
func osa(_ src: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", src]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func number(_ x: String) -> Double {
    let v = Double(x.replacingOccurrences(of: ",", with: ".")) ?? 0
    return v.isFinite ? v : 0
}

enum Player: CaseIterable {
    case spotify, music
    var name: String { self == .spotify ? "Spotify" : "Music" }
    var bundle: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var script: String {
        let art = self == .spotify ? "(artwork url of current track)" : "\"\""
        let dur = self == .spotify ? "((duration of current track) / 1000)" : "(duration of current track)"
        return """
        tell application "\(name)"
            if player state is stopped then return ""
            return (name of current track) & "|" & (artist of current track) & "|" & (player state as string) & "|" & \(art) & "|" & (player position as string) & "|" & (\(dur) as string)
        end tell
        """
    }
    func read() -> Track? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty else { return nil }
        guard let out = osa(script) else { return nil }
        let p = out.components(separatedBy: "|")
        guard p.count == 6 else { return nil }
        return Track(app: name, title: p[0], artist: p[1], playing: p[2] == "playing",
                     art: URL(string: p[3]), pos: number(p[4]), dur: number(p[5]))
    }
}

/// Music from browser tabs. Reads navigator.mediaSession, so any site that fills it works.
enum Browser: String, CaseIterable {
    case chrome = "Google Chrome", brave = "Brave Browser", edge = "Microsoft Edge", arc = "Arc", safari = "Safari"

    var bundle: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .brave: return "com.brave.Browser"
        case .edge: return "com.microsoft.edgemac"
        case .arc: return "company.thebrowser.Browser"
        case .safari: return "com.apple.Safari"
        }
    }

    var short: String { self == .chrome ? "Chrome" : self == .brave ? "Brave" : self == .edge ? "Edge" : rawValue }

    static let hosts = ["soundcloud.com", "open.spotify.com", "youtube.com", "music.apple.com",
                        "deezer.com", "tidal.com", "bandcamp.com", "music.yandex"]

    static let sep = "§§"
    static let find = "var l=[].slice.call(document.querySelectorAll('video,audio')).filter(function(x){return x.readyState>0&&x.duration>0});var e=l.filter(function(x){return !x.paused})[0]||l[0];function c(q){var b=document.querySelector(q);if(b)b.click()};"
    static let probe = "(function(){var m=navigator.mediaSession.metadata;" + Browser.find +
        "if(!m||!e)return '';var a=m.artwork.length?m.artwork[m.artwork.length-1].src:'';" +
        "var v=new URLSearchParams(location.search).get('v');if(!a&&v)a='https://i.ytimg.com/vi/'+v+'/hqdefault.jpg';" +
        "var ar=m.artist;if(!ar){var ch=document.querySelector('ytd-channel-name a');ar=ch?ch.textContent.trim():location.hostname.replace('www.','')}" +
        "var q=document.querySelector('#description-inline-expander');" +
        "var d=q?q.textContent:((document.querySelector('meta[name=description]')||{}).content||'');" +
        "d=d.split(String.fromCharCode(10)).join(' ').trim().slice(0,140);" +
        "return [m.title,ar,e.paused?'0':'1',a,e.currentTime,e.duration,d].join('" + Browser.sep + "')})()"

    static func js(_ a: Action) -> String {
        switch a {
        case .toggle: return find + "if(e){if(e.paused){e.play()}else{e.pause()}}"
        case .next: return find + "c('.skipControl__next,[data-testid=control-button-skip-forward],.ytp-next-button,ytmusic-player-bar .next-button,[aria-label=Next]')"
        case .prev: return find + "c('.skipControl__previous,[data-testid=control-button-skip-back],.ytp-prev-button,ytmusic-player-bar .previous-button,[aria-label=Previous]')"
        case .seek(let f): return find + "if(e){e.currentTime=e.duration*\(f)}"
        }
    }

    func scan() -> [Track] {
        guard UserDefaults.standard.object(forKey: "browser_" + rawValue) as? Bool ?? true else { return [] }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty else { return [] }
        let cond = Browser.hosts.map { "u contains \"\($0)\"" }.joined(separator: " or ")
        let call = self == .safari ? "do JavaScript \"\(Browser.probe)\" in t" : "execute t javascript \"\(Browser.probe)\""
        let src = """
        tell application "\(rawValue)"
            set out to ""
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                set ti to 0
                repeat with t in tabs of w
                    set ti to ti + 1
                    try
                        set u to URL of t
                        if \(cond) then
                            try
                                set r to \(call)
                                if r is not "" then set out to out & (wi as string) & "\(Browser.sep)" & (ti as string) & "\(Browser.sep)" & r & linefeed
                            on error
                                if u contains "youtube.com/watch" or u contains "soundcloud.com/" or u contains "open.spotify.com" then
                                    set out to out & (wi as string) & "\(Browser.sep)" & (ti as string) & "\(Browser.sep)~\(Browser.sep)" & (title of t) & "\(Browser.sep)" & u & linefeed
                                end if
                            end try
                        end if
                    end try
                end repeat
            end repeat
            return out
        end tell
        """
        guard let out = osa(src) else { return [] }
        return out.components(separatedBy: "\n").compactMap { line in
            let p = line.components(separatedBy: Browser.sep)
            if p.count == 5, p[2] == "~" { return limited(p) }
            guard p.count == 9, !p[2].isEmpty else { return nil }
            return Track(app: short, title: p[2], artist: p[3], playing: p[4] == "1",
                         art: URL(string: p[5]), pos: number(p[6]), dur: number(p[7]),
                         web: self, wi: Int(p[0]) ?? 0, ti: Int(p[1]) ?? 0, info: p[8])
        }
    }

    private func limited(_ p: [String]) -> Track? {
        var title = p[3]
        var artist = ""
        if (URL(string: p[4])?.host ?? "").contains("spotify") {
            // Spotify Web puts "Song • Artist" in the tab title only while a track is playing
            let parts = title.components(separatedBy: " • ")
            guard parts.count >= 2 else { return nil }
            title = parts[0]
            artist = parts[1...].joined(separator: " • ")
        }
        for tail in [" - YouTube", " | Free Listening on SoundCloud"] {
            title = title.replacingOccurrences(of: tail, with: "")
        }
        if title.hasPrefix("("), let r = title.firstIndex(of: ")") {
            title = String(title[title.index(after: r)...]).trimmingCharacters(in: .whitespaces)
        }
        let v = URLComponents(string: p[4])?.queryItems?.first { $0.name == "v" }?.value
        let host = (URL(string: p[4])?.host ?? "").replacingOccurrences(of: "www.", with: "")
        return Track(app: short, title: title, artist: artist.isEmpty ? host : artist, playing: true,
                     art: v.flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/hqdefault.jpg") },
                     pos: 0, dur: 0, web: self, wi: Int(p[0]) ?? 0, ti: Int(p[1]) ?? 0, info: L("limited"))
    }

    func run(_ a: Action, wi: Int, ti: Int) {
        let tab = "(tab \(ti) of window \(wi))"
        let code = Browser.js(a)
        if self == .safari {
            osa("tell application \"\(rawValue)\" to do JavaScript \"\(code)\" in \(tab)")
        } else {
            osa("tell application \"\(rawValue)\" to execute \(tab) javascript \"\(code)\"")
        }
    }
}

// MARK: - State
final class GlassNotchState: ObservableObject {
    static let shared = GlassNotchState()
    static let defaultAccent = Color(red: 0.42, green: 0.62, blue: 1.0)

    @Published var expanded = false
    @Published var track: Track?
    @Published var files: [URL] = []
    @Published var artImage: NSImage?
    @Published var accent: Color = GlassNotchState.defaultAccent
    @Published var batteryHover = false
    /// True when the closed notch shows artwork/equalizer wings (same rule as the view).
    var wingsActive: Bool {
        let d = UserDefaults.standard
        return track != nil && (d.object(forKey: "musicEnabled") as? Bool ?? true) && (d.object(forKey: "showMusicBubble") as? Bool ?? true)
    }
    var hasBubbles: Bool { track != nil || !files.isEmpty }
    private var timer: Timer?
    private var artURL: URL?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    private let queue = DispatchQueue(label: "notch.music")
    private var busy = false

    func refresh() {
        let d = UserDefaults.standard
        guard d.object(forKey: "musicEnabled") as? Bool ?? true else {
            if track != nil { track = nil }
            loadArt(nil)
            return
        }
        guard !busy else { return }
        busy = true
        let web = d.object(forKey: "webMusic") as? Bool ?? true
        queue.async {
            var all = Player.allCases.compactMap { $0.read() }
            if web { all += Browser.allCases.flatMap { $0.scan() } }
            let t = all.first { $0.playing } ?? all.first
            DispatchQueue.main.async {
                self.busy = false
                if t != self.track { self.track = t }
                self.loadArt(t?.art)
            }
        }
    }

    func control(_ a: Action) {
        guard let t = track else { return }
        queue.async {
            if let b = t.web {
                b.run(a, wi: t.wi, ti: t.ti)
            } else {
                let cmd: String
                switch a {
                case .prev: cmd = "previous track"
                case .toggle: cmd = "playpause"
                case .next: cmd = "next track"
                case .seek(let f): cmd = "set player position to \(Int(t.dur * f))"
                }
                osa("tell application \"\(t.app)\" to \(cmd)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refresh() }
        }
    }

    func seek(_ fraction: Double) {
        guard let t = track, t.dur > 0 else { return }
        let f = min(max(fraction, 0), 1)
        track?.pos = t.dur * f
        control(.seek(f))
    }

    // Artwork + accent color taken from the cover (the blue artist name / progress bar in the design)
    private func loadArt(_ url: URL?) {
        guard url != artURL else { return }
        artURL = url
        guard let url else {
            artImage = nil
            accent = GlassNotchState.defaultAccent
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            let c = GlassNotchState.dominantColor(img)
            DispatchQueue.main.async {
                guard let self, self.artURL == url else { return }
                self.artImage = img
                self.accent = c
            }
        }.resume()
    }

    static func dominantColor(_ img: NSImage) -> Color {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return defaultAccent }
        let n = 16
        var px = [UInt8](repeating: 0, count: n * n * 4)
        px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8,
                                      bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        }
        var r = 0.0, g = 0.0, b = 0.0, sum = 0.0
        for i in 0..<(n * n) {
            let pr = Double(px[i * 4]) / 255, pg = Double(px[i * 4 + 1]) / 255, pb = Double(px[i * 4 + 2]) / 255
            let mx = max(pr, pg, pb), mn = min(pr, pg, pb)
            let w = 0.02 + (mx - mn) * mx   // vivid, bright pixels weigh more
            r += pr * w; g += pg * w; b += pb * w; sum += w
        }
        guard sum > 0 else { return defaultAccent }
        let ns = NSColor(srgbRed: r / sum, green: g / sum, blue: b / sum, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        ns.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return Color(hue: Double(h), saturation: Double(max(s, 0.45)), brightness: Double(max(v, 0.9)))
    }
}

// MARK: - Language
enum Lang {
    static let all = [("system", ""), ("en", "English"), ("es", "Español"), ("fr", "Français"), ("ja", "日本語"), ("ru", "Русский")]
    static var code: String {
        let c = UserDefaults.standard.string(forKey: "language") ?? "system"
        if c != "system" { return c }
        let sys = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        return all.contains { $0.0 == sys } ? sys : "en"
    }
    static let en = [
        "browser.ask": "GlassNotch can show what plays in Chrome, Brave, Edge or Arc (SoundCloud, YouTube, Spotify Web). It will switch on one browser setting for you. macOS will ask for Accessibility and Automation access, please allow both.",
        "browser.note": "Safari: Develop > Allow JavaScript from Apple Events (once). Without it only the title shows, with no controls.",
        "acc.need": "Allow GlassNotch in System Settings > Privacy & Security > Accessibility, then press the button again.",
        "limited": "Limited: allow browser access in Settings",
    ]
    // order: es, fr, ja, ru
    static let table: [String: [String]] = [
        "General": ["General", "Général", "一般", "Общие"],
        "Look": ["Aspecto", "Apparence", "外観", "Вид"],
        "Music": ["Música", "Musique", "ミュージック", "Музыка"],
        "Shelf": ["Estante", "Étagère", "シェルフ", "Полка"],
        "About": ["Acerca de", "À propos", "情報", "О программе"],
        "Language": ["Idioma", "Langue", "言語", "Язык"],
        "System": ["Sistema", "Système", "システム", "Система"],
        "Launch at login": ["Abrir al iniciar sesión", "Ouvrir à la connexion", "ログイン時に起動", "Запускать при входе"],
        "Open on hover (off = click the notch)": ["Abrir al pasar el ratón (apagado = clic)", "Ouvrir au survol (désactivé = clic)", "ホバーで開く（オフ＝クリック）", "Открывать при наведении (выкл = по клику)"],
        "Calendar": ["Calendario", "Calendrier", "カレンダー", "Календарь"],
        "Battery": ["Batería", "Batterie", "バッテリー", "Батарея"],
        "GlassNotch color": ["Color del notch", "Couleur de l'encoche", "ノッチの色", "Цвет челки"],
        "Keep it black so the notch blends with the cutout.": ["Déjalo en negro para que se funda con el borde de la pantalla.", "Garde-le noir pour qu'il se fonde avec l'encoche.", "ノッチと自然に馴染ませるには黒のままにしてください。", "Чтобы челка сливалась с вырезом, оставь чёрный."],
        "Accent": ["Acento", "Accent", "アクセント", "Акцент"],
        "From artwork": ["De la portada", "De la pochette", "ジャケットから", "Из обложки"],
        "Custom color": ["Color propio", "Couleur perso", "カスタム", "Свой цвет"],
        "Accent color": ["Color de acento", "Couleur d'accent", "アクセントの色", "Цвет акцента"],
        "Width": ["Ancho", "Largeur", "幅", "Ширина"],
        "Height": ["Alto", "Hauteur", "高さ", "Высота"],
        "Reset look": ["Restablecer aspecto", "Réinitialiser l'apparence", "外観をリセット", "Сбросить вид"],
        "Enable music": ["Activar música", "Activer la musique", "ミュージックを有効化", "Включить музыку"],
        "Artwork and equalizer next to the notch": ["Portada y ecualizador junto al notch", "Pochette et égaliseur à côté de l'encoche", "ノッチ横にジャケットとイコライザを表示", "Обложка и эквалайзер возле челки"],
        "Music from browsers (SoundCloud, YouTube, Spotify Web...)": ["Música del navegador (SoundCloud, YouTube, Spotify Web...)", "Musique du navigateur (SoundCloud, YouTube, Spotify Web...)", "ブラウザの音楽（SoundCloud、YouTube、Spotify Web など）", "Музыка из браузера (SoundCloud, YouTube, Spotify Web...)"],
        "Allow browser access": ["Permitir acceso al navegador", "Autoriser l'accès au navigateur", "ブラウザへのアクセスを許可", "Разрешить доступ к браузеру"],
        "browser.note": ["Safari: Desarrollo > Permitir JavaScript desde eventos de Apple (una vez). Sin eso solo se muestra el título, sin controles.", "Safari : Développement > Autoriser JavaScript provenant d'événements Apple (une fois). Sinon seul le titre s'affiche, sans commandes.", "Safari：開発 > Apple Events からの JavaScript を許可（一度だけ）。未設定の場合はタイトルのみ表示され、操作はできません。", "Safari: Разработка > Разрешить JavaScript из событий Apple (один раз). Без этого видно только название, без управления."],
        "File shelf": ["Estante de archivos", "Étagère de fichiers", "ファイルシェルフ", "Полка для файлов"],
        "Floating shelf island": ["Isla flotante del estante", "Îlot flottant de l'étagère", "フローティングシェルフ", "Плавающий островок полки"],
        "Clear shelf": ["Vaciar estante", "Vider l'étagère", "シェルフを空にする", "Очистить полку"],
        "Nothing playing": ["Nada en reproducción", "Rien en lecture", "再生中なし", "Ничего не играет"],
        "Drop files here": ["Suelta archivos aquí", "Dépose des fichiers ici", "ここにファイルをドロップ", "Перетащи файлы сюда"],
        "Calendar access is off": ["Acceso al calendario desactivado", "Accès au calendrier désactivé", "カレンダーへのアクセスがオフです", "Нет доступа к календарю"],
        "Open Privacy settings": ["Abrir ajustes de privacidad", "Ouvrir les réglages de confidentialité", "プライバシー設定を開く", "Открыть настройки приватности"],
        "No events today": ["Sin eventos hoy", "Aucun événement aujourd'hui", "今日の予定はありません", "Сегодня событий нет"],
        "Enjoy your free time!": ["¡Disfruta tu tiempo libre!", "Profite de ton temps libre !", "自由な時間を楽しんで！", "Наслаждайся свободным временем!"],
        "All day": ["Todo el día", "Toute la journée", "終日", "Весь день"],
        "Remove": ["Quitar", "Retirer", "削除", "Убрать"],
        "Settings…": ["Ajustes…", "Réglages…", "設定…", "Настройки…"],
        "Quit GlassNotch": ["Salir de GlassNotch", "Quitter GlassNotch", "GlassNotch を終了", "Выйти из GlassNotch"],
        "Allow music from browsers?": ["¿Permitir música de los navegadores?", "Autoriser la musique des navigateurs ?", "ブラウザの音楽を許可しますか？", "Разрешить музыку из браузеров?"],
        "browser.ask": ["GlassNotch puede mostrar lo que suena en Chrome, Brave, Edge o Arc (SoundCloud, YouTube, Spotify Web). Activará un ajuste del navegador por ti. macOS pedirá acceso de Accesibilidad y Automatización; permite ambos.", "GlassNotch peut afficher ce qui joue dans Chrome, Brave, Edge ou Arc (SoundCloud, YouTube, Spotify Web). Il activera un réglage du navigateur pour toi. macOS demandera l'accès Accessibilité et Automatisation, autorise les deux.", "Chrome、Brave、Edge、Arc で再生中の音楽や動画（SoundCloud、YouTube、Spotify Web）を表示できます。ブラウザの設定を1つ自動でオンにします。macOS が「アクセシビリティ」と「オートメーション」の許可を求めるので、両方許可してください。", "GlassNotch покажет, что играет в Chrome, Brave, Edge или Arc (SoundCloud, YouTube, Spotify Web). Он сам включит одну настройку браузера. macOS спросит доступ к «Универсальному доступу» и «Автоматизации», разреши оба."],
        "acc.need": ["Permite GlassNotch en Ajustes del Sistema > Privacidad y seguridad > Accesibilidad y vuelve a pulsar el botón.", "Autorise GlassNotch dans Réglages Système > Confidentialité et sécurité > Accessibilité, puis appuie de nouveau sur le bouton.", "システム設定 > プライバシーとセキュリティ > アクセシビリティ で GlassNotch を許可し、もう一度ボタンを押してください。", "Разреши GlassNotch в Системные настройки > Конфиденциальность > Универсальный доступ и нажми кнопку ещё раз."],
        "limited": ["Limitado: permite el acceso al navegador en Ajustes", "Limité : autorise l'accès au navigateur dans Réglages", "制限あり：設定でブラウザアクセスを許可", "Ограничено: разреши доступ к браузеру в настройках"],
        "Corner roundness": ["Redondez", "Arrondi", "角の丸み", "Скругление"],
        "Animation (left = faster)": ["Animación (izq. = más rápida)", "Animation (gauche = plus rapide)", "アニメーション（左ほど速い）", "Анимация (влево = быстрее)"],
        "Artwork next to the notch": ["Portada junto al notch", "Pochette à côté de l'encoche", "ノッチ横にジャケット", "Обложка возле челки"],
        "Equalizer next to the notch": ["Ecualizador junto al notch", "Égaliseur à côté de l'encoche", "ノッチ横にイコライザ", "Эквалайзер возле челки"],
        "Browsers to scan": ["Navegadores a escanear", "Navigateurs à analyser", "スキャンするブラウザ", "Какие браузеры проверять"],
        "Reset all settings": ["Restablecer todo", "Tout réinitialiser", "すべてリセット", "Сбросить все настройки"],
        "Welcome to GlassNotch": ["Bienvenido a GlassNotch", "Bienvenue dans GlassNotch", "GlassNotch へようこそ", "Добро пожаловать в GlassNotch"],
        "Grant the permissions once and everything works.": ["Concede los permisos una vez y todo funciona.", "Accorde les autorisations une fois et tout fonctionne.", "一度だけ許可すれば、すべて動作します。", "Дай разрешения один раз, и всё заработает."],
        "Calendar events": ["Eventos del calendario", "Événements du calendrier", "カレンダーの予定", "События календаря"],
        "Spotify and Apple Music": ["Spotify y Apple Music", "Spotify et Apple Music", "Spotify と Apple Music", "Spotify и Apple Music"],
        "Browsers (YouTube, SoundCloud...)": ["Navegadores (YouTube, SoundCloud...)", "Navigateurs (YouTube, SoundCloud...)", "ブラウザ（YouTube、SoundCloud など）", "Браузеры (YouTube, SoundCloud...)"],
        "Grant": ["Permitir", "Autoriser", "許可する", "Разрешить"],
        "Finish": ["Terminar", "Terminer", "完了", "Готово"],
        "Permissions…": ["Permisos…", "Autorisations…", "権限…", "Разрешения…"],
        "Open Spotify or Music first, then press again.": ["Abre Spotify o Música primero y vuelve a pulsar.", "Ouvre d'abord Spotify ou Musique, puis réessaie.", "先に Spotify または ミュージック を開いてから、もう一度押してください。", "Сначала открой Spotify или Музыку и нажми ещё раз."],
        "Work": ["Trabajo", "Travail", "仕事", "Работа"],
        "Meeting island in the notch": ["Isla de reunión en el notch", "Îlot de réunion dans l'encoche", "ノッチに会議を表示", "Островок встречи у челки"],
        "Remind before meeting (min)": ["Avisar antes de la reunión (min)", "Rappel avant la réunion (min)", "会議の何分前に表示（分）", "Напомнить до встречи (мин)"],
        "Focus (min)": ["Enfoque (min)", "Concentration (min)", "集中（分）", "Фокус (мин)"],
        "Break (min)": ["Descanso (min)", "Pause (min)", "休憩（分）", "Перерыв (мин)"],
        "Timer sound": ["Sonido del temporizador", "Son du minuteur", "タイマー音", "Звук таймера"],
        "Join": ["Unirse", "Rejoindre", "参加", "Войти"],
        "Focus": ["Enfoque", "Concentration", "集中", "Фокус"],
        "Break": ["Descanso", "Pause", "休憩", "Перерыв"],
        "New note…": ["Nueva nota…", "Nouvelle note…", "新しいメモ…", "Новая заметка…"],
        "Now": ["Ahora", "Maintenant", "今", "Сейчас"],
        "Add website": ["Añadir sitio web", "Ajouter un site", "サイトを追加", "Добавить сайт"],
        "Paste a link, the icon and name are filled in automatically.": ["Pega un enlace; el icono y el nombre se rellenan solos.", "Colle un lien, l'icône et le nom se remplissent automatiquement.", "リンクを貼ると、アイコンと名前は自動で入ります。", "Вставь ссылку, иконка и название подставятся сами."],
        "Add": ["Añadir", "Ajouter", "追加", "Добавить"],
        "Cancel": ["Cancelar", "Annuler", "キャンセル", "Отмена"],
        "Quick open": ["Apertura rápida", "Ouverture rapide", "クイック起動", "Быстрый запуск"],
        "Add app…": ["Añadir app…", "Ajouter une app…", "アプリを追加…", "Добавить приложение…"],
        "Add website…": ["Añadir sitio web…", "Ajouter un site…", "サイトを追加…", "Добавить сайт…"],
        "Plug in the charger": ["Conecta el cargador", "Branche le chargeur", "充電してください", "Поставь на зарядку"],
        "Low battery island": ["Isla de batería baja", "Îlot de batterie faible", "低バッテリー表示", "Островок низкой зарядки"],
        "Show below (%)": ["Mostrar por debajo de (%)", "Afficher sous (%)", "この残量以下で表示（%）", "Показывать ниже (%)"],
        "Clock island": ["Isla del reloj", "Îlot horloge", "時計を表示", "Островок с часами"],
        "Show seconds": ["Mostrar segundos", "Afficher les secondes", "秒を表示", "Показывать секунды"],
        "Nothing here yet": ["Aún no hay nada", "Rien pour l'instant", "まだありません", "Пока пусто"],
        "Allow": ["Permitir", "Autoriser", "許可", "Разрешить"],
        "Not now": ["Ahora no", "Plus tard", "今はしない", "Не сейчас"],
        "Done": ["Listo", "Terminé", "完了", "Готово"],
        "Open your browser first, then try again.": ["Abre primero el navegador y vuelve a intentarlo.", "Ouvre d'abord le navigateur, puis réessaie.", "先にブラウザを開いてから、もう一度お試しください。", "Сначала открой браузер и нажми ещё раз."],
    ]
}

func L(_ key: String) -> String {
    if Lang.code == "en" { return Lang.en[key] ?? key }
    guard let i = ["es", "fr", "ja", "ru"].firstIndex(of: Lang.code), let v = Lang.table[key] else { return key }
    return v[i]
}

// MARK: - Colors
extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }

    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }

    var isLight: Bool {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.6
    }
}

// MARK: - Battery
final class BatteryState: ObservableObject {
    static let shared = BatteryState()
    @Published var level = 100
    @Published var charging = false
    @Published var present = false
    var isLow: Bool {
        let d = UserDefaults.standard
        guard d.object(forKey: "lowBatteryIsland") as? Bool ?? true, d.object(forKey: "batteryEnabled") as? Bool ?? true else { return false }
        let th = Int(d.object(forKey: "lowBatteryLevel") as? Double ?? 20)
        return present && !charging && level <= th
    }
    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            present = false
            return
        }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let mx = d[kIOPSMaxCapacityKey] as? Int, mx > 0 else { continue }
            let l = cur * 100 / mx
            let c = (d[kIOPSIsChargingKey] as? Bool) ?? false
            if l != level { level = l }
            if c != charging { charging = c }
            if !present { present = true }
            return
        }
        present = false
    }
}

// MARK: - Calendar
struct EventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
    let url: URL?
}

/// Finds a Zoom / Meet / Teams / Webex link in the event's url, location or notes.
func meetingURL(_ ev: EKEvent) -> URL? {
    let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com"]
    var texts: [String] = []
    if let u = ev.url?.absoluteString { texts.append(u) }
    if let l = ev.location { texts.append(l) }
    if let n = ev.notes { texts.append(n) }
    guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    for t in texts {
        for m in det.matches(in: t, options: [], range: NSRange(t.startIndex..., in: t)) {
            if let u = m.url, let h = u.host, hosts.contains(where: { h.hasSuffix($0) }) { return u }
        }
    }
    return nil
}

final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()
    @Published var events: [EventItem] = []
    @Published var authorized: Bool?   // nil = not asked yet
    private let store = EKEventStore()
    private var started = false
    private var timer: Timer?

    private init() {
        if UserDefaults.standard.object(forKey: "calendarEnabled") as? Bool ?? true { start() }
    }

    func start() {
        guard !started else { return }
        started = true
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
                self?.reload()
            }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.reload() }
    }

    func reload() {
        guard authorized == true else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let now = Date()
        events = store.events(matching: pred)
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .map { ev in
                EventItem(id: (ev.eventIdentifier ?? UUID().uuidString) + "\(ev.startDate.timeIntervalSince1970)",
                          title: ev.title ?? "Event",
                          start: ev.startDate, end: ev.endDate, allDay: ev.isAllDay,
                          color: Color(nsColor: ev.calendar.color ?? NSColor.systemBlue),
                          url: meetingURL(ev))
            }
    }
}

// MARK: - Focus timer
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()
    @Published var remaining: Double = 25 * 60
    @Published var running = false
    @Published var onBreak = false
    private var timer: Timer?
    private var end: Date?

    private var focusMin: Double { UserDefaults.standard.object(forKey: "focusMin") as? Double ?? 25 }
    private var breakMin: Double { UserDefaults.standard.object(forKey: "breakMin") as? Double ?? 5 }
    var total: Double { (onBreak ? breakMin : focusMin) * 60 }
    var progress: Double { total > 0 ? min(max(1 - remaining / total, 0), 1) : 0 }

    private init() { remaining = total }

    func applySettings() { if !running { remaining = total } }
    func toggle() { running ? pause() : start() }

    func start() {
        guard !running else { return }
        if remaining <= 0 { remaining = total }
        end = Date().addingTimeInterval(remaining)
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    func pause() {
        if let end { remaining = max(0, end.timeIntervalSinceNow) }
        running = false
        timer?.invalidate()
        timer = nil
        end = nil
    }

    func reset() { pause(); remaining = total }
    func switchMode() { pause(); onBreak.toggle(); remaining = total }

    private func tick() {
        guard let end else { return }
        let r = end.timeIntervalSinceNow
        if r <= 0 {
            pause()
            if UserDefaults.standard.object(forKey: "timerSound") as? Bool ?? true { NSSound(named: NSSound.Name("Glass"))?.play() }
            onBreak.toggle()
            remaining = total
        } else if Int(r) != Int(remaining) {
            remaining = r
        }
    }
}

// MARK: - Quick notes
struct Note: Identifiable {
    let id = UUID()
    var text: String
}

final class NotesStore: ObservableObject {
    static let shared = NotesStore()
    @Published var items: [Note] = []

    private init() {
        items = (UserDefaults.standard.stringArray(forKey: "notes") ?? []).map { Note(text: $0) }
    }

    func add(_ t: String) {
        let v = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        items.insert(Note(text: v), at: 0)
        save()
    }

    func remove(_ n: Note) {
        items.removeAll { $0.id == n.id }
        save()
    }

    private func save() { UserDefaults.standard.set(items.map { $0.text }, forKey: "notes") }
}

struct NotesPanel: View {
    @ObservedObject var store = NotesStore.shared
    @State private var text = ""
    @FocusState private var focused: Bool
    var fg: Color
    var accent: Color

    private func add() {
        store.add(text)
        text = ""
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField(L("New note…"), text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { add() }
                Button(action: add) { Image(systemName: "plus.circle.fill").font(.system(size: 16)) }
                    .buttonStyle(.plain).foregroundStyle(accent)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9).fill(fg.opacity(0.12)))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(store.items) { n in
                        HStack(spacing: 8) {
                            Text(n.text).font(.system(size: 12)).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(n.text, forType: .string)
                            } label: { Image(systemName: "doc.on.doc").font(.system(size: 11)) }
                                .buttonStyle(.plain).foregroundStyle(Color.gray)
                            Button { store.remove(n) } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                                .buttonStyle(.plain).foregroundStyle(Color.gray)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear {
            // The notch panel normally never takes keyboard focus; allow it while the notes tab is open.
            GlassNotchPanel.current?.allowKey = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                GlassNotchPanel.current?.makeKey()
                focused = true
            }
        }
        .onDisappear {
            GlassNotchPanel.current?.allowKey = false
            GlassNotchPanel.current?.resignKey()
        }
    }
}

// MARK: - Clock
enum GlassNotchClock {
    static let hms: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()
    static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    static func string(_ d: Date) -> String {
        (UserDefaults.standard.object(forKey: "clockSeconds") as? Bool ?? true ? hms : hm).string(from: d)
    }
    static func full(_ d: Date) -> String { hms.string(from: d) }
}

// MARK: - Volume + brightness
/// Brightness goes through Apple's private DisplayServices (loaded at runtime, hidden if unavailable).
enum DisplayBrightness {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32
    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    static func get() -> Double? {
        guard let h = lib, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        let f = unsafeBitCast(sym, to: GetFn.self)
        var v: Float = 0
        return f(CGMainDisplayID(), &v) == 0 ? Double(v) : nil
    }

    static func set(_ x: Double) {
        guard let h = lib, let sym = dlsym(h, "DisplayServicesSetBrightness") else { return }
        _ = unsafeBitCast(sym, to: SetFn.self)(CGMainDisplayID(), Float(x))
    }
}

final class SystemControls: ObservableObject {
    static let shared = SystemControls()
    @Published var volume = 0.5
    @Published var brightness = 0.5
    let hasBrightness = DisplayBrightness.get() != nil
    private let q = DispatchQueue(label: "notch.sys")
    private var pending: Int?
    private var working = false

    func refresh() {
        if let b = DisplayBrightness.get() { brightness = b }
        q.async {
            guard let out = osa("set v to get volume settings\nreturn output volume of v as string"), let v = Double(out) else { return }
            DispatchQueue.main.async { self.volume = v / 100 }
        }
    }

    func setVolume(_ x: Double) {
        let c = min(max(x, 0), 1)
        volume = c
        pending = Int(c * 100)
        guard !working else { return }
        working = true
        drain()
    }

    private func drain() {
        guard let p = pending else { working = false; return }
        pending = nil
        q.async {
            osa("set volume output volume \(p)")
            DispatchQueue.main.async { self.drain() }
        }
    }

    func setBrightness(_ x: Double) {
        let c = min(max(x, 0.02), 1)
        brightness = c
        DisplayBrightness.set(c)
    }
}

// MARK: - Quick open
struct QuickItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var isApp: Bool
    var target: String   // app path or url
    var name: String
}

final class QuickStore: ObservableObject {
    static let shared = QuickStore()
    @Published var items: [QuickItem] = []
    @Published var icons: [UUID: NSImage] = [:]

    private init() {
        if let d = UserDefaults.standard.data(forKey: "quickItems"),
           let v = try? JSONDecoder().decode([QuickItem].self, from: d) { items = v }
        for i in items { loadIcon(i) }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: "quickItems") }
    }

    func add(_ it: QuickItem) {
        items.append(it)
        loadIcon(it)
        save()
    }

    func remove(_ it: QuickItem) {
        items.removeAll { $0.id == it.id }
        save()
    }

    func open(_ it: QuickItem) {
        if it.isApp {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: it.target), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        } else if let u = URL(string: it.target) {
            NSWorkspace.shared.open(u)
        }
    }

    /// Websites get their favicon automatically; apps use their own icon.
    func loadIcon(_ it: QuickItem) {
        guard !it.isApp, let host = URL(string: it.target)?.host,
              let u = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") else { return }
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.icons[it.id] = img }
        }.resume()
    }

    func addApp() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        guard p.runModal() == .OK else { return }
        for u in p.urls {
            add(QuickItem(isApp: true, target: u.path, name: u.deletingPathExtension().lastPathComponent))
        }
    }

    func addSite() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = L("Add website")
        a.informativeText = L("Paste a link, the icon and name are filled in automatically.")
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        f.placeholderString = "youtube.com"
        a.accessoryView = f
        a.addButton(withTitle: L("Add"))
        a.addButton(withTitle: L("Cancel"))
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return }
        var t = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t), let host = u.host else { return }
        let label = host.replacingOccurrences(of: "www.", with: "").components(separatedBy: ".").first ?? host
        add(QuickItem(isApp: false, target: t, name: label.prefix(1).uppercased() + label.dropFirst()))
    }
}

// MARK: - Islands
struct IslandItem {
    let id: String
    let width: CGFloat
    let left: Bool
    let content: AnyView
}

struct PlacedIsland: Identifiable {
    let item: IslandItem
    let x: CGFloat
    var id: String { item.id }
}

// MARK: - Shapes
/// GlassNotch shape: top corners flare outward so it melts into the screen edge.
struct GlassNotchShape: Shape {
    var topR: CGFloat, botR: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topR, botR) }
        set { topR = newValue.first; botR = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + topR, y: r.minY + topR), control: CGPoint(x: r.minX + topR, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + topR, y: r.maxY - botR))
        p.addQuadCurve(to: CGPoint(x: r.minX + topR + botR, y: r.maxY), control: CGPoint(x: r.minX + topR, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - topR - botR, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - topR, y: r.maxY - botR), control: CGPoint(x: r.maxX - topR, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - topR, y: r.minY + topR))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - topR, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct SpotifyMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<3 {
            let f = CGFloat(i)
            let y = r.minY + r.height * (0.12 + 0.34 * f) + r.height * 0.14
            let inset = r.width * 0.09 * f
            p.move(to: CGPoint(x: r.minX + inset, y: y))
            p.addQuadCurve(to: CGPoint(x: r.maxX - inset, y: y), control: CGPoint(x: r.midX, y: y - r.height * 0.24))
        }
        return p
    }
}

struct EqualizerView: View {
    var active: Bool
    var body: some View {
        TimelineView(.animation(paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<4) { i in
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: 3, height: active ? 5 + 10 * abs(sin(t * 4 + Double(i) * 1.3)) : 5 + 3 * Double(i % 3))
                }
            }
            .frame(height: 16)
        }
    }
}

struct BatteryIcon: View {
    var level: Int
    var charging: Bool
    var base: Color = .white
    var body: some View {
        let fill: Color = charging ? Color.green : (level <= 20 ? Color.red : base)
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).stroke(base.opacity(0.35), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2.5).fill(fill)
                    .frame(width: max(3, 22 * CGFloat(level) / 100), height: 9)
                    .padding(.leading, 2)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(base).frame(maxWidth: .infinity)
                }
            }
            .frame(width: 27, height: 13)
            RoundedRectangle(cornerRadius: 1).fill(base.opacity(0.4)).frame(width: 2, height: 5)
        }
    }
}

/// Own settings window. The system "showSettingsWindow:" is unreliable for menu-bar-only apps.
enum SettingsWindow {
    static var window: NSWindow?
    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "GlassNotch"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

func openSettings() { SettingsWindow.show() }

func formatTime(_ seconds: Double) -> String {
    let t = seconds.isFinite ? max(0, Int(seconds)) : 0
    return String(format: "%d:%02d", t / 60, t % 60)
}

enum GlassNotchTab { case home, shelf, timer, notes, quick, controls }

// MARK: - Main view
struct GlassNotchView: View {
    @ObservedObject var s = GlassNotchState.shared
    @ObservedObject var battery = BatteryState.shared
    @ObservedObject var calStore = CalendarStore.shared
    @AppStorage("musicEnabled") var musicOn = true
    @AppStorage("showMusicBubble") var musicBubble = true
    @AppStorage("shelfEnabled") var shelfOn = true
    @AppStorage("showShelfBubble") var shelfBubble = true
    @AppStorage("calendarEnabled") var calendarOn = true
    @AppStorage("batteryEnabled") var batteryOn = true
    @AppStorage("notchColor") var notchHex = "000000"
    @AppStorage("accentAuto") var accentAuto = true
    @AppStorage("accentColor") var accentHex = "6B9EFF"
    @AppStorage("openW") var openW = 680.0
    @AppStorage("openH") var openH = 195.0
    @AppStorage("openRadius") var openRadius = 28.0
    @AppStorage("animSpeed") var animSpeed = 0.45
    @AppStorage("showArtWing") var showArt = true
    @AppStorage("showEqWing") var showEq = true
    @AppStorage("language") var language = "system"
    @State private var tab: GlassNotchTab = .home
    @State private var dropping = false
    @ObservedObject var focus = FocusTimer.shared
    @ObservedObject var sys = SystemControls.shared
    @ObservedObject var quick = QuickStore.shared
    @AppStorage("lowBatteryIsland") var lowIsland = true
    @AppStorage("lowBatteryLevel") var lowLevel = 20.0
    @AppStorage("clockIsland") var clockOn = true
    @AppStorage("clockSeconds") var clockSec = true
    var lowBattery: Bool { batteryOn && lowIsland && battery.present && !battery.charging && battery.level <= Int(lowLevel) }
    @AppStorage("meetingEnabled") var meetingOn = true
    @AppStorage("meetingMinutes") var meetingMin = 15.0
    var notchColor: Color { Color(hex: notchHex) }
    var fg: Color { notchColor.isLight ? .black : .white }
    var accent: Color { accentAuto ? s.accent : Color(hex: accentHex) }
    /// Meeting that starts within the reminder window (or is running now).
    var soon: EventItem? {
        guard meetingOn, calendarOn else { return nil }
        let now = Date()
        return calStore.events.first { !$0.allDay && $0.end > now && $0.start.timeIntervalSince(now) <= meetingMin * 60 }
    }
    var morph: Animation { .spring(response: animSpeed, dampingFraction: 0.8) }
    let fly = Animation.spring(response: 0.55, dampingFraction: 0.6)

    var body: some View {
        let open = s.expanded
        let music = !open && musicOn && musicBubble && s.track != nil
        let shelf = !open && shelfOn && shelfBubble && !s.files.isEmpty
        let timerShow = !open && focus.running
        let meet: EventItem? = open ? nil : soon
        let list: [IslandItem] = open ? [] : islandItems(shelf: shelf, timer: timerShow, meet: meet)
        ZStack(alignment: .top) {
            // Separate small island for the file shelf (only when files are on the shelf)
            islands(list, wings: music)
            notch(open, wings: music)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.locale, Locale(identifier: Lang.code))
        .animation(morph, value: open)
        .animation(fly, value: music)
    }

    private func islandItems(shelf: Bool, timer: Bool, meet: EventItem?) -> [IslandItem] {
        var l: [IslandItem] = []
        if lowBattery {
            let hover = s.batteryHover
            l.append(IslandItem(id: "battery", width: hover ? 178 : 64, left: true, content: AnyView(
                Group {
                    if hover {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill").foregroundStyle(Color.yellow)
                            Text(L("Plug in the charger")).foregroundStyle(Color.red)
                        }
                    } else {
                        HStack(spacing: 4) {
                            BatteryIcon(level: battery.level, charging: false, base: fg).scaleEffect(0.8)
                            Text("\(battery.level)%").foregroundStyle(Color.red)
                        }
                    }
                })))
        }
        if timer {
            l.append(IslandItem(id: "timer", width: 66, left: true, content: AnyView(
                HStack(spacing: 4) {
                    Image(systemName: focus.onBreak ? "cup.and.saucer.fill" : "timer")
                    Text(formatTime(focus.remaining)).monospacedDigit()
                })))
        }
        if shelf {
            l.append(IslandItem(id: "shelf", width: 46, left: true, content: AnyView(
                HStack(spacing: 3) { Image(systemName: "tray.full.fill"); Text("\(s.files.count)") })))
        }
        if let ev = meet {
            let mins = max(0, Int(ev.start.timeIntervalSinceNow / 60))
            l.append(IslandItem(id: "meeting", width: 62, left: false, content: AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "video.fill").foregroundStyle(accent)
                    Text(mins > 0 ? "\(mins)m" : L("Now"))
                })))
        }
        if clockOn {
            l.append(IslandItem(id: "clock", width: clockSec ? 76 : 50, left: false, content: AnyView(
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(GlassNotchClock.string(ctx.date)).monospacedDigit()
                })))
        }
        return l
    }

    private func islands(_ items: [IslandItem], wings: Bool) -> some View {
        let closedW = Metrics.w + (wings ? 2 * GlassNotchLayout.wing : 0)
        var lx = closedW / 2 + 10
        var rx = closedW / 2 + 10
        var placed: [PlacedIsland] = []
        for it in items {
            if it.left {
                placed.append(PlacedIsland(item: it, x: -(lx + it.width / 2)))
                lx += it.width + 6
            } else {
                placed.append(PlacedIsland(item: it, x: rx + it.width / 2))
                rx += it.width + 6
            }
        }
        let slots = placed
        return ZStack(alignment: .top) {
            ForEach(slots) { p in
                p.item.content
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(fg)
                    .lineLimit(1)
                    .frame(width: p.item.width, height: Metrics.h - 6)
                    .background(notchColor, in: Capsule())
                    .offset(x: p.x, y: 3)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .animation(fly, value: slots.map { $0.id })
        .animation(fly, value: slots.map { $0.x })
    }

    // MARK: GlassNotch container
    private func notch(_ open: Bool, wings showWings: Bool) -> some View {
        let tr: CGFloat = open ? 20 : 6
        let shape = GlassNotchShape(topR: tr, botR: open ? CGFloat(openRadius) : 10)
        let width: CGFloat = open ? GlassNotchLayout.openW : Metrics.w + (showWings ? 2 * GlassNotchLayout.wing : 0)
        return ZStack(alignment: .top) {
            if open {
                content.transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            } else if showWings, let t = s.track {
                wings(t).transition(.opacity)
            }
        }
        .frame(width: width, height: open ? GlassNotchLayout.openH : Metrics.h, alignment: .top)
        .padding(.horizontal, tr)
        .background(notchColor, in: shape)
        .clipShape(shape)
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { if !s.files.contains(url) { s.files.append(url) } } }
                }
            }
            return true
        }
        .onChange(of: dropping) { _, v in
            if v && shelfOn { tab = .shelf }
        }
    }

    /// Closed state with music: artwork on the left, equalizer on the right (physical notch in the middle).
    private func wings(_ t: Track) -> some View {
        HStack(spacing: 0) {
            if showArt { art(t, Metrics.h - 12).padding(.leading, 9) }
            Spacer(minLength: 0)
            if showEq { EqualizerView(active: t.playing).padding(.trailing, 16) }
        }
        .frame(height: Metrics.h)
    }

    // MARK: Expanded content
    private var content: some View {
        let current: GlassNotchTab = (tab == .shelf && !shelfOn) ? .home : tab
        return VStack(spacing: 0) {
            topBar(current).frame(height: Metrics.h)
            Group {
                switch current {
                case .home: home
                case .shelf: shelfPanel
                case .timer: timerPanel
                case .notes: NotesPanel(fg: fg, accent: accent)
                case .quick: quickPanel
                case .controls: controlsPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 24).padding(.bottom, 16)
    }

    private func topBar(_ current: GlassNotchTab) -> some View {
        HStack(spacing: 18) {
            topButton("house.fill", active: current == .home) { tab = .home }
            if shelfOn { topButton("tray.fill", active: current == .shelf) { tab = .shelf } }
            topButton("timer", active: current == .timer) { tab = .timer }
            topButton("note.text", active: current == .notes) { tab = .notes }
            topButton("bolt.fill", active: current == .quick) { tab = .quick }
            topButton("slider.horizontal.3", active: current == .controls) { tab = .controls }
            Spacer()
            topButton("gearshape", active: false) { openSettings() }
            if batteryOn && battery.present {
                HStack(spacing: 6) {
                    Text("\(battery.level)%").font(.system(size: 14, weight: .medium))
                    BatteryIcon(level: battery.level, charging: battery.charging, base: fg)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private func topButton(_ icon: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium))
                .foregroundStyle(active ? fg : Color.gray)
        }
        .buttonStyle(.plain)
    }

    private var timerPanel: some View {
        VStack(spacing: 6) {
            Text(focus.onBreak ? L("Break") : L("Focus")).font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
            Text(formatTime(focus.remaining)).font(.system(size: 40, weight: .bold).monospacedDigit())
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(fg.opacity(0.15))
                    Capsule().fill(accent).frame(width: g.size.width * focus.progress)
                }
            }
            .frame(width: 300, height: 5)
            HStack(spacing: 28) {
                ctl("arrow.counterclockwise", 17) { focus.reset() }
                ctl(focus.running ? "pause.fill" : "play.fill", 26) { focus.toggle() }
                ctl("forward.end.fill", 17) { focus.switchMode() }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focus.applySettings() }
    }

    @ViewBuilder
    private func quickIcon(_ it: QuickItem) -> some View {
        if it.isApp {
            Image(nsImage: NSWorkspace.shared.icon(forFile: it.target)).resizable()
        } else if let img = quick.icons[it.id] {
            Image(nsImage: img).resizable().clipShape(RoundedRectangle(cornerRadius: 9))
        } else {
            Image(systemName: "globe").resizable().scaledToFit().padding(8)
        }
    }

    private var quickPanel: some View {
        HStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if quick.items.isEmpty {
                        Text(L("Nothing here yet")).font(.system(size: 11)).foregroundStyle(Color.gray)
                    }
                    ForEach(quick.items) { it in
                        Button { quick.open(it) } label: {
                            VStack(spacing: 4) {
                                quickIcon(it).frame(width: 42, height: 42)
                                Text(it.name).font(.system(size: 10)).lineLimit(1).frame(width: 62)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button(L("Remove")) { quick.remove(it) } }
                    }
                }
                .padding(.horizontal, 4)
            }
            VStack(spacing: 12) {
                ctl("plus.app", 20) { quick.addApp() }
                ctl("link.badge.plus", 20) { quick.addSite() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sliderRow(_ icon: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(Color.gray)
            Slider(value: value, in: 0...1).tint(accent)
        }
    }

    private var controlsPanel: some View {
        HStack(spacing: 26) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(spacing: 2) {
                    Text(GlassNotchClock.full(ctx.date)).font(.system(size: 34, weight: .bold).monospacedDigit())
                    Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 12)).foregroundStyle(Color.gray)
                }
            }
            .frame(width: 210)
            VStack(spacing: 16) {
                sliderRow("speaker.wave.2.fill", Binding(get: { sys.volume }, set: { sys.setVolume($0) }))
                if sys.hasBrightness {
                    sliderRow("sun.max.fill", Binding(get: { sys.brightness }, set: { sys.setBrightness($0) }))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { sys.refresh() }
    }

    @ViewBuilder
    private func joinButton(_ e: EventItem) -> some View {
        if let u = e.url {
            Button { NSWorkspace.shared.open(u) } label: {
                Label(L("Join"), systemImage: "video.fill").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(accent.opacity(0.28)))
        }
    }

    private var home: some View {
        let showMusic = musicOn && s.track != nil
        return HStack(alignment: .center, spacing: 18) {
            if showMusic { musicPanel.frame(maxWidth: .infinity, alignment: .leading) }
            if calendarOn { calendarPanel.frame(width: showMusic ? 290 : nil) }
        }
    }

    // MARK: Music
    private var musicPanel: some View {
        Group {
            if let t = s.track {
                HStack(spacing: 14) {
                    art(t, 108).overlay(alignment: .bottomTrailing) { badge(t).offset(x: 9, y: 9) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.title).font(.system(size: 16, weight: .bold)).lineLimit(1)
                        Text(t.artist).font(.system(size: 14, weight: .medium)).foregroundStyle(accent).lineLimit(1)
                        if !t.info.isEmpty {
                            Text(t.info).font(.system(size: 10)).foregroundStyle(Color.gray).lineLimit(1)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(fg.opacity(0.15))
                                Capsule().fill(accent).frame(width: g.size.width * t.progress)
                            }
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                                s.seek(v.location.x / max(g.size.width, 1))
                            })
                        }
                        .frame(height: 5).animation(.linear(duration: 1), value: t.progress)
                        .padding(.top, 4)
                        HStack {
                            Text(formatTime(t.pos))
                            Spacer()
                            Text(formatTime(t.dur))
                        }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                        HStack(spacing: 30) {
                            ctl("backward.fill", 20) { s.control(.prev) }
                            ctl(t.playing ? "pause.fill" : "play.fill", 28) { s.control(.toggle) }
                            ctl("forward.fill", 20) { s.control(.next) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note").font(.title2)
                    Text(L("Nothing playing")).font(.system(size: 11))
                }
                .foregroundStyle(Color.gray)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func badge(_ t: Track) -> some View {
        let isSpotify = t.app == "Spotify"
        let isWeb = t.web != nil
        let bg = isWeb ? Color(white: 0.3) : isSpotify ? Color(red: 0.11, green: 0.73, blue: 0.33) : Color(red: 0.98, green: 0.17, blue: 0.33)
        return ZStack {
            Circle().fill(bg)
            if isWeb {
                Image(systemName: "globe").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.white)
            } else if isSpotify {
                SpotifyMark()
                    .stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .frame(width: 20, height: 15)
            } else {
                Image(systemName: "music.note").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.white)
            }
        }
        .frame(width: 34, height: 34)
    }

    private func art(_ t: Track, _ size: CGFloat) -> some View {
        Group {
            if let img = s.artImage {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(Color.white))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 60 ? 14 : size * 0.22))
    }

    private func ctl(_ icon: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: size)) }.buttonStyle(.plain)
    }

    // MARK: Calendar
    private var calendarPanel: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let cal = Calendar.current
            let now = ctx.date
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 2) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(now, format: .dateTime.month(.abbreviated)).font(.system(size: 16, weight: .semibold))
                        Text(now, format: .dateTime.year()).font(.system(size: 16, weight: .light)).foregroundStyle(Color.gray)
                    }
                    .frame(width: 52, alignment: .leading)
                    ForEach(days, id: \.self) { d in
                        dayCell(d, today: cal.isDate(d, inSameDayAs: now))
                    }
                }
                eventsArea
            }
        }
    }

    private func dayCell(_ d: Date, today: Bool) -> some View {
        VStack(spacing: 4) {
            Text(d, format: .dateTime.weekday(.abbreviated))
                .font(.system(size: 10, weight: today ? .semibold : .regular))
                .foregroundStyle(today ? Color.white : Color.gray)
                .lineLimit(1)
            Text(d, format: .dateTime.day())
                .font(.system(size: 14, weight: .medium))
                .frame(width: 25, height: 25)
                .background(Circle().fill(today ? Color.blue : Color.clear))
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 9).fill(today ? Color.white.opacity(0.12) : Color.clear))
    }

    private var eventsArea: some View {
        Group {
            if calStore.authorized == false {
                VStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 26)).foregroundStyle(Color.gray)
                    Text(L("Calendar access is off")).font(.system(size: 12, weight: .semibold))
                    Button(L("Open Privacy settings")) {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(u)
                        }
                    }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                }
            } else if calStore.events.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "calendar.badge.checkmark").font(.system(size: 28)).foregroundStyle(Color.gray)
                    Text(L("No events today")).font(.system(size: 13, weight: .semibold))
                    Text(L("Enjoy your free time!")).font(.system(size: 11)).foregroundStyle(Color.gray)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(calStore.events.prefix(3)) { e in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 3, height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(e.allDay ? L("All day")
                                     : "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 10)).foregroundStyle(Color.gray)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) { joinButton(e) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Shelf
    private var shelfPanel: some View {
        Group {
            if s.files.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.title2)
                    Text(L("Drop files here")).font(.system(size: 11))
                }
                .foregroundStyle(Color.gray)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(s.files, id: \.self) { url in
                            VStack(spacing: 3) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 40, height: 40)
                                Text(url.lastPathComponent).font(.system(size: 9)).lineLimit(1).frame(width: 52)
                            }
                            .onDrag { NSItemProvider(object: url as NSURL) }
                            .onTapGesture { NSWorkspace.shared.open(url) }
                            .contextMenu { Button(L("Remove")) { s.files.removeAll { $0 == url } } }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5])))
    }
}

// MARK: - Settings
func notify(_ title: String, _ text: String) {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.runModal()
}

/// Safari hides the Develop menu by default: open Settings > Advanced and tick the last checkbox ("Show features for web developers").
let safariPrepare = """
tell application "System Events" to tell process "Safari"
    set frontmost to true
    keystroke "," using command down
    delay 1
    try
        set w to window 1
        click (last button of toolbar 1 of w)
        delay 0.7
        set lastCB to missing value
        repeat with e in (entire contents of w)
            try
                if role of e is "AXCheckBox" then set lastCB to e
            end try
        end repeat
        if lastCB is not missing value then
            if (value of lastCB) is 0 then click lastCB
        end if
        delay 0.5
    end try
    try
        keystroke "w" using command down
    end try
    delay 0.5
end tell
return "done"
"""

/// Ticks "Allow JavaScript from Apple Events" in the browser's menu bar.
func enableBrowserAccess() {
    let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(opts) else { notify("GlassNotch", L("acc.need")); return }
    DispatchQueue.global().async {
        var lines: [String] = []
        var any = false
        for b in Browser.allCases {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: b.bundle).isEmpty else { continue }
            let src = """
            tell application "System Events" to tell process "\(b.rawValue)"
                repeat with mb in menu bar items of menu bar 1
                    try
                        repeat with mi in menu items of menu 1 of mb
                            try
                                repeat with si in menu items of menu 1 of mi
                                    try
                                        set n to name of si
                                        if n contains "JavaScript" and n contains "Apple" then
                                            if (value of attribute "AXMenuItemMarkChar" of si) is missing value then click si
                                            return "ok"
                                        end if
                                    end try
                                end repeat
                            end try
                        end repeat
                    end try
                end repeat
            end tell
            return "no"
            """
            var ok = osa(src) == "ok"
            if !ok && b == .safari {
                osa(safariPrepare)
                ok = osa(src) == "ok"
            }
            any = any || ok
            lines.append("\(b.short): \(ok ? "✓" : "✗")")
            if !ok && b == .safari { lines.append(L("browser.note")) }
        }
        DispatchQueue.main.async {
            notify(any ? L("Done") : L("Open your browser first, then try again."), lines.joined(separator: "\n"))
        }
    }
}

func askBrowserAccess() {
    let d = UserDefaults.standard
    guard !d.bool(forKey: "askedBrowser") else { return }
    d.set(true, forKey: "askedBrowser")
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = L("Allow music from browsers?")
    a.informativeText = L("browser.ask")
    a.addButton(withTitle: L("Allow"))
    a.addButton(withTitle: L("Not now"))
    if a.runModal() == .alertFirstButtonReturn { enableBrowserAccess() }
}

func askPlayers() {
    DispatchQueue.global().async {
        var any = false
        for p in Player.allCases where !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundle).isEmpty {
            any = true
            osa("tell application \"\(p.name)\" to return name")
        }
        if !any { DispatchQueue.main.async { notify("GlassNotch", L("Open Spotify or Music first, then press again.")) } }
    }
}

struct OnboardingView: View {
    @ObservedObject var cal = CalendarStore.shared
    var done: () -> Void

    private func row(_ icon: String, _ title: String, _ ok: Bool, _ action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).frame(width: 28)
            Text(title)
            Spacer()
            if ok {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(L("Grant"), action: action)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 16) {
                Image(systemName: "rectangle.topthird.inset.filled").font(.system(size: 44)).foregroundStyle(.blue)
                Text(L("Welcome to GlassNotch")).font(.title.bold())
                Text(L("Grant the permissions once and everything works.")).foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    row("calendar", L("Calendar events"), cal.authorized == true) { CalendarStore.shared.start() }
                    row("music.note", L("Spotify and Apple Music"), false) { askPlayers() }
                    row("globe", L("Browsers (YouTube, SoundCloud...)"), AXIsProcessTrusted()) { enableBrowserAccess() }
                }
                Button(L("Finish")) { done() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(28)
            .frame(width: 460)
        }
    }
}

enum Onboarding {
    static var window: NSWindow?
    static func show() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(done: { window?.close() })))
            w.title = "GlassNotch"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    static func showIfNeeded() {
        if !UserDefaults.standard.bool(forKey: "onboarded") { show() }
    }
}

struct BrowserToggle: View {
    let b: Browser
    @AppStorage private var on: Bool
    init(b: Browser) {
        self.b = b
        _on = AppStorage(wrappedValue: true, "browser_" + b.rawValue)
    }
    var body: some View { Toggle(b.rawValue, isOn: $on) }
}

struct SettingsView: View {
    @AppStorage("hoverOpen") var hoverOpen = true
    @AppStorage("musicEnabled") var musicOn = true
    @AppStorage("showMusicBubble") var musicBubble = true
    @AppStorage("webMusic") var webMusic = true
    @AppStorage("shelfEnabled") var shelfOn = true
    @AppStorage("showShelfBubble") var shelfBubble = true
    @AppStorage("calendarEnabled") var calendarOn = true
    @AppStorage("batteryEnabled") var batteryOn = true
    @AppStorage("launchAtLogin") var launch = false
    @AppStorage("notchColor") var notchHex = "000000"
    @AppStorage("accentAuto") var accentAuto = true
    @AppStorage("accentColor") var accentHex = "6B9EFF"
    @AppStorage("openW") var openW = 680.0
    @AppStorage("openH") var openH = 195.0
    @AppStorage("openRadius") var openRadius = 28.0
    @AppStorage("animSpeed") var animSpeed = 0.45
    @AppStorage("showArtWing") var showArt = true
    @AppStorage("showEqWing") var showEq = true
    @AppStorage("language") var language = "system"

    @AppStorage("meetingEnabled") var meetingOn = true
    @AppStorage("meetingMinutes") var meetingMin = 15.0
    @AppStorage("focusMin") var focusMin = 25.0
    @AppStorage("breakMin") var breakMin = 5.0
    @AppStorage("timerSound") var timerSound = true
    @AppStorage("lowBatteryIsland") var lowIsland = true
    @AppStorage("lowBatteryLevel") var lowLevel = 20.0
    @AppStorage("clockIsland") var clockOn = true
    @AppStorage("clockSeconds") var clockSec = true
    @ObservedObject var quick = QuickStore.shared

    private func picker(_ hex: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.hex })
    }

    var body: some View {
        TabView {
            Form {
                Picker(L("Language"), selection: $language) {
                    ForEach(Lang.all, id: \.0) { Text($0.0 == "system" ? L("System") : $0.1).tag($0.0) }
                }
                Toggle(L("Launch at login"), isOn: $launch).onChange(of: launch) { _, v in
                    if v { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                }
                Toggle(L("Open on hover (off = click the notch)"), isOn: $hoverOpen)
                Toggle(L("Calendar"), isOn: $calendarOn).onChange(of: calendarOn) { _, v in
                    if v { CalendarStore.shared.start() }
                }
                Toggle(L("Battery"), isOn: $batteryOn)
                Toggle(L("Low battery island"), isOn: $lowIsland)
                Slider(value: $lowLevel, in: 5...50, step: 5) { Text("\(L("Show below (%)")): \(Int(lowLevel))") }
                Toggle(L("Clock island"), isOn: $clockOn)
                Toggle(L("Show seconds"), isOn: $clockSec)
            }
            .tabItem { Label(L("General"), systemImage: "gearshape") }
            Form {
                ColorPicker(L("GlassNotch color"), selection: picker($notchHex), supportsOpacity: false)
                Text(L("Keep it black so the notch blends with the cutout.")).font(.caption).foregroundStyle(.secondary)
                Picker(L("Accent"), selection: $accentAuto) {
                    Text(L("From artwork")).tag(true)
                    Text(L("Custom color")).tag(false)
                }
                if !accentAuto { ColorPicker(L("Accent color"), selection: picker($accentHex), supportsOpacity: false) }
                Slider(value: $openW, in: 560...740, step: 10) { Text(L("Width")) }
                Slider(value: $openH, in: 170...225, step: 5) { Text(L("Height")) }
                Slider(value: $openRadius, in: 14...40, step: 2) { Text(L("Corner roundness")) }
                Slider(value: $animSpeed, in: 0.25...0.8, step: 0.05) { Text(L("Animation (left = faster)")) }
                Button(L("Reset look")) {
                    notchHex = "000000"; accentAuto = true; accentHex = "6B9EFF"; openW = 680; openH = 195
                    openRadius = 28; animSpeed = 0.45
                }
            }
            .tabItem { Label(L("Look"), systemImage: "paintpalette") }
            Form {
                Toggle(L("Enable music"), isOn: $musicOn)
                Toggle(L("Artwork and equalizer next to the notch"), isOn: $musicBubble)
                Toggle(L("Artwork next to the notch"), isOn: $showArt).disabled(!musicBubble)
                Toggle(L("Equalizer next to the notch"), isOn: $showEq).disabled(!musicBubble)
                Toggle(L("Music from browsers (SoundCloud, YouTube, Spotify Web...)"), isOn: $webMusic)
                Section(L("Browsers to scan")) {
                    ForEach(Browser.allCases, id: \.self) { BrowserToggle(b: $0) }
                }
                Button(L("Allow browser access")) { enableBrowserAccess() }
                Text(L("browser.note")).font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label(L("Music"), systemImage: "music.note") }
            Form {
                Toggle(L("File shelf"), isOn: $shelfOn)
                Toggle(L("Floating shelf island"), isOn: $shelfBubble)
                Button(L("Clear shelf")) { GlassNotchState.shared.files.removeAll() }
            }
            .tabItem { Label(L("Shelf"), systemImage: "tray") }
            Form {
                ForEach(quick.items) { it in
                    HStack(spacing: 10) {
                        Group {
                            if it.isApp {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: it.target)).resizable()
                            } else if let img = quick.icons[it.id] {
                                Image(nsImage: img).resizable()
                            } else {
                                Image(systemName: "globe").resizable().scaledToFit()
                            }
                        }
                        .frame(width: 22, height: 22)
                        Text(it.name)
                        Spacer()
                        Button(L("Remove")) { quick.remove(it) }
                    }
                }
                Button(L("Add app…")) { quick.addApp() }
                Button(L("Add website…")) { quick.addSite() }
            }
            .tabItem { Label(L("Quick open"), systemImage: "bolt.fill") }
            Form {
                Toggle(L("Meeting island in the notch"), isOn: $meetingOn)
                Slider(value: $meetingMin, in: 5...30, step: 5) { Text("\(L("Remind before meeting (min)")): \(Int(meetingMin))") }
                Slider(value: $focusMin, in: 10...60, step: 5) { Text("\(L("Focus (min)")): \(Int(focusMin))") }
                    .onChange(of: focusMin) { _, _ in FocusTimer.shared.applySettings() }
                Slider(value: $breakMin, in: 3...15, step: 1) { Text("\(L("Break (min)")): \(Int(breakMin))") }
                    .onChange(of: breakMin) { _, _ in FocusTimer.shared.applySettings() }
                Toggle(L("Timer sound"), isOn: $timerSound)
            }
            .tabItem { Label(L("Work"), systemImage: "briefcase") }
            VStack(spacing: 10) {
                Text("GlassNotch").font(.title2.bold())
                Text("MIT License").foregroundStyle(.secondary)
                Button(L("Reset all settings")) {
                    let d = UserDefaults.standard
                    for k in d.dictionaryRepresentation().keys where k != "notes" { d.removeObject(forKey: k) }
                    GlassNotchState.shared.files.removeAll()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem { Label(L("About"), systemImage: "info.circle") }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 500)
        .onAppear { launch = SMAppService.mainApp.status == .enabled }
    }
}

// MARK: - Window + app
final class GlassNotchPanel: NSPanel {
    static weak var current: GlassNotchPanel?
    var allowKey = false
    override var canBecomeKey: Bool { allowKey }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = GlassNotchState.shared
    var panel: GlassNotchPanel!

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let s = Metrics.screen.frame
        panel = GlassNotchPanel(contentRect: NSRect(x: s.midX - 400, y: s.maxY - 240, width: 800, height: 240),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .mainMenu + 3
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: GlassNotchView())
        GlassNotchPanel.current = panel
        panel.orderFrontRegardless()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in self?.handle(e) }
        NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in self?.handle(e); return e }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { Onboarding.showIfNeeded() }
    }

    func handle(_ e: NSEvent) {
        let m = NSEvent.mouseLocation, s = Metrics.screen.frame
        let hover = UserDefaults.standard.object(forKey: "hoverOpen") as? Bool ?? true
        let tw = Metrics.w + (state.hasBubbles ? 260 : 60)
        let trigger = NSRect(x: s.midX - tw / 2, y: s.maxY - Metrics.h - 2, width: tw, height: Metrics.h + 2)
        let openH = GlassNotchLayout.openH + 10
        let openRect = NSRect(x: s.midX - (GlassNotchLayout.openW + 40) / 2, y: s.maxY - openH, width: GlassNotchLayout.openW + 40, height: openH)
        var overBat = false
        if !state.expanded && BatteryState.shared.isLow {
            let closedW = Metrics.w + (state.wingsActive ? 2 * GlassNotchLayout.wing : 0)
            let bw: CGFloat = state.batteryHover ? 178 : 64
            let batRect = NSRect(x: s.midX - closedW / 2 - 10 - bw, y: s.maxY - Metrics.h, width: bw, height: Metrics.h)
            overBat = batRect.contains(m)
        }
        if state.batteryHover != overBat { state.batteryHover = overBat }
        var want = state.expanded
        if state.expanded { want = openRect.contains(m) }
        else if hover || e.type != .mouseMoved { want = trigger.contains(m) && !overBat }
        if want != state.expanded {
            state.expanded = want
            panel.ignoresMouseEvents = !want
        }
    }
}

@main
struct GlassNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("GlassNotch", systemImage: "rectangle.topthird.inset.filled") {
            Button(L("Settings…")) { openSettings() }
                .keyboardShortcut(",")
            Button(L("Permissions…")) { Onboarding.show() }
            Divider()
            Button(L("Quit GlassNotch")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
