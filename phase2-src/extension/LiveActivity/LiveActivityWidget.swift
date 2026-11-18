// The Live Activity's face, one of three views: the line being sung with the next one under it, the
// tracks up next, or the control menu, a tab bar over Controls, Queue and Timer. A tap reaches the
// tweak as an intent and the new state takes over a second to render, so every on/off control is a
// Toggle, whose look the system flips the moment it is tapped, and what only changes after the render
// is marked invalidatable. iOS clips a lock screen Live Activity at 160 points, so every view is kept
// under it. Built with the tweak's LiveActivityShared.swift by scripts/build-extension.sh.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let green = Color(red: 0.12, green: 0.84, blue: 0.38)
private let idle = Color.white.opacity(0.08)

private typealias State = SGLyricsAttributes.ContentState
private typealias Tab = SGLyricsAttributes.Tab

@main
struct SGLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        SGLyricsLiveActivity()
    }
}

extension SGLyricsAttributes.Tab {
    var symbol: String {
        switch self {
        case .controls: "slider.horizontal.3"
        case .queue: "list.bullet"
        case .timer: "moon.zzz"
        }
    }

    var title: String {
        switch self {
        case .controls: "Controls"
        case .queue: "Queue"
        case .timer: "Timer"
        }
    }
}

struct SGLyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SGLyricsAttributes.self) { context in
            ContentView(state: context.state, upNext: 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, context.state.view == .panel ? 12 : 16)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "spotify:"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Group {
                        if context.state.view == .panel {
                            Summary(state: context.state)
                        } else {
                            ContentView(state: context.state, upNext: 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundStyle(green)
            } compactTrailing: {
                if let end = context.state.timerEnd, end > Date() {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(green)
                        .frame(maxWidth: 44)
                } else if context.state.view == .lyrics, !context.state.line.isEmpty {
                    ScrollingLyrics(line: context.state.line, lineStart: context.state.lineStart,
                                    lineDuration: context.state.lineDuration, refreshTime: context.state.refreshTime,
                                    size: 21, color: green)
                        .direction(of: context.state.line)
                } else {
                    Image(systemName: context.state.paused ? "pause.fill" : "waveform")
                        .foregroundStyle(green)
                }
            } minimal: {
                if let end = context.state.timerEnd, end > Date() {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(green)
                } else if context.state.view == .lyrics, !context.state.line.isEmpty {
                    ScrollingLyrics(line: context.state.line, lineStart: context.state.lineStart,
                                    lineDuration: context.state.lineDuration, refreshTime: context.state.refreshTime,
                                    size: 20, color: green)
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(green)
                }
            }
            .widgetURL(URL(string: "spotify:"))
        }
    }
}

// 单行滚动歌词：短则静止，长则从右往左滚动（复刻灵动歌词），左右两侧渐隐。
// 单行滚动歌词：短则静止，长则从右往左滚动（复刻灵动歌词的 ClockEffect 大半径转动）。
private struct ScrollingLyrics: View {
    let line: String
    let lineStart: Double?
    let lineDuration: Double?
    let refreshTime: Double?
    let size: CGFloat          // 字体 pt
    let color: Color

    private static let edgePadding: CGFloat = 6
    private static let fadeWidth: CGFloat = 3

    private var textWidth: CGFloat {
        (line as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size)]).width
    }
    private var textHeight: CGFloat {
        (line as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size)]).height
    }

    var body: some View {
        GeometryReader { proxy in
            let W = proxy.size.width
            let C = textWidth
            let H = textHeight
            if C + Self.edgePadding * 2 <= W || lineDuration == nil || lineStart == nil {
                // 静止：文字不超宽，或无时间数据
                Text(line)
                    .font(.system(size: size))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .frame(width: W, alignment: .leading)
                    .clipped()
                    .mask(fadeMask(width: W))
            } else {
                // 滚动：大半径转动，切向运动近似水平
                Text(line)
                    .font(.system(size: size))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
                    .modifier(ClockAnimationModifier(
                        start: lineStart! - (refreshTime ?? lineStart!),
                        refreshTime: refreshTime ?? lineStart!,
                        duration: lineDuration!,
                        contentWidth: C,
                        contentHeight: H,
                        viewWidth: W))
                    .frame(width: W, alignment: .leading)
                    .clipped()
                    .mask(fadeMask(width: W))
            }
        }
        .frame(height: size + 2)
    }

    private func fadeMask(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fadeWidth)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fadeWidth)
        }
    }
}

// 大半径转动近似水平滚动（灵动歌词 ClockAnimationModifier 的几何，逐项复刻）。
private struct ClockAnimationModifier: ViewModifier {
    let start: Double          // 加到 refreshTime 相位的时间偏移（秒）
    let refreshTime: Double    // Unix 秒相位锚点
    let duration: Double       // 行时长（秒，≤6）
    let contentWidth: CGFloat  // C
    let contentHeight: CGFloat // H
    let viewWidth: CGFloat     // W

    private static let totalDuration: Double = 3600

    func body(content: Content) -> some View {
        let T = Self.totalDuration
        // L = C + 20 - W
        let L = contentWidth + 20 - viewWidth
        // angleSpan = 360 * duration / T，R = L / (angleSpan * π/180)
        let angleSpan = 360.0 * duration / T
        let R = L / (angleSpan * .pi / 180.0)
        // theta0 = (360*start/T + 360*fmod(refreshTime,T)/T + 180*duration/T) * π/180
        let thetaDeg = 360.0 * start / T + 360.0 * fmod(refreshTime, T) / T + 180.0 * duration / T
        let theta = thetaDeg * .pi / 180.0

        return ZStack(alignment: .top) {
            Color.clear
            content
        }
        .frame(width: 2 * R, height: 2 * R)
        .rotationEffect(.radians(theta), anchor: .center)
        .clockHandRotationEffect(period: .custom(-T))
        .offset(x: 0, y: R - contentHeight / 2)
    }
}

private struct ContentView: View {
    let state: State
    let upNext: Int

    var body: some View {
        switch state.view {
        case .lyrics: LyricsView(state: state)
        case .queue: QueueView(state: state, upNext: upNext)
        case .panel: PanelView(state: state)
        }
    }
}

// MARK: - Lyrics and queue

private struct LyricsView: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.line)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .direction(of: state.line)
            if let translation = state.lineTranslation, !translation.isEmpty {
                Text(translation)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .direction(of: state.nextLine)
            }
        }
    }
}

// Whether a line is written right to left, told by its first letter the way the Unicode bidi algorithm
// tells a paragraph's direction. Each line is asked on its own, since a song can mix scripts, and the
// phone's language has no say in it. The tweak's lyrics page asks the same (SGRKaraokeView.m).
private func readsRightToLeft(_ text: String) -> Bool {
    guard let first = text.unicodeScalars.first(where: { $0.properties.isAlphabetic }) else { return false }
    switch first.value {
    case 0x0590...0x08FF,      // Hebrew, Arabic, Syriac, Thaana, N'Ko and on
         0xFB1D...0xFDFF,      // Hebrew and Arabic presentation forms
         0xFE70...0xFEFF,      // Arabic presentation forms B
         0x10800...0x10FFF,    // the old scripts written right to left
         0x1E800...0x1EFFF:    // Mende Kikakui and Adlam
        return true
    default:
        return false
    }
}

private extension View {
    // A line written right to left is laid out right to left, against the right edge; any other is left
    // the way it was.
    @ViewBuilder func direction(of line: String) -> some View {
        if readsRightToLeft(line) {
            frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            self
        }
    }
}

private struct QueueView: View {
    let state: State
    let upNext: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("下一首")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            if state.tracks.isEmpty {
                Text("暂无下一首")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            ForEach(Array(state.tracks.prefix(upNext).enumerated()), id: \.offset) { _, track in
                // A tap skips ahead to the track.
                Button(intent: SGPlayQueuedTrackIntent(track.uri)) {
                    (Text(track.title).fontWeight(.semibold) + Text("  " + track.artist).foregroundColor(.white.opacity(0.5)))
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Control menu

// The expanded Dynamic Island has room for one line of the menu.
private struct Summary: View {
    let state: State

    var body: some View {
        Group {
            switch state.tab {
            case .controls:
                Text("\(state.title) · \(state.artist)")
            case .queue:
                Text(state.tracks.first.map { "下一首：\($0.title)" } ?? "暂无下一首")
            case .timer:
                if let end = state.timerEnd, end > Date() {
                    Text("将在 \(Text(timerInterval: Date()...end, countsDown: true)) 后停止播放")
                } else if state.timerEndOfTrack {
                    Text("本曲播放结束后停止")
                } else {
                    Text("未设置睡眠定时")
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .invalidatableContent()
    }
}

private struct PanelView: View {
    let state: State

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Toggle(isOn: tab == state.tab, intent: SGLiveActivityActionIntent("tab:\(tab.rawValue)")) {
                        EmptyView()
                    }
                    .toggleStyle(TabStyle(tab: tab))
                }
            }
            Group {
                switch state.tab {
                case .controls: ControlsPage(state: state)
                case .queue: QueuePage(state: state)
                case .timer: TimerPage(state: state)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TabStyle: ToggleStyle {
    let tab: Tab

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tab.symbol)
            if configuration.isOn {
                Text(tab.title)
            }
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(Capsule().fill(configuration.isOn ? green.opacity(0.22) : idle))
        .foregroundStyle(configuration.isOn ? green : .white.opacity(0.7))
    }
}

private struct ChipLabel: View {
    let symbol: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
            Text(label)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }
}

private struct ChipStyle: ToggleStyle {
    let symbol: String
    var onSymbol: String?
    let label: String
    var onLabel: String?
    // Play and pause flips its symbol but is not a setting, so it keeps the idle fill either way.
    var lights = true

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        ChipLabel(symbol: on ? onSymbol ?? symbol : symbol, label: on ? onLabel ?? label : label)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on && lights ? green.opacity(0.22) : idle))
            .foregroundStyle(on && lights ? green : .white)
    }
}

private struct ChipButton: View {
    let action: String
    let symbol: String
    let label: String
    var lit = false

    var body: some View {
        Button(intent: SGLiveActivityActionIntent(action)) {
            ChipLabel(symbol: symbol, label: label)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(lit ? green.opacity(0.22) : idle))
                .foregroundStyle(lit ? green : .white)
        }
        .buttonStyle(.plain)
    }
}

private struct ControlsPage: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                Text(state.artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .lineLimit(1)
            .invalidatableContent()
            HStack(spacing: 6) {
                ChipButton(action: "previous", symbol: "backward.fill", label: "Previous")
                Toggle(isOn: !state.paused, intent: SGLiveActivityActionIntent("toggle")) { EmptyView() }
                    .toggleStyle(ChipStyle(symbol: "play.fill", onSymbol: "pause.fill", label: "Play", onLabel: "Pause", lights: false))
                ChipButton(action: "next", symbol: "forward.fill", label: "Next")
                Toggle(isOn: state.shuffle, intent: SGLiveActivityActionIntent("shuffle")) { EmptyView() }
                    .toggleStyle(ChipStyle(symbol: "shuffle", label: "Shuffle"))
                // Three states, so a button: the new one shows once the render lands.
                ChipButton(action: "repeat", symbol: state.repeatMode == 2 ? "repeat.1" : "repeat",
                           label: "Repeat", lit: state.repeatMode != 0)
                    .invalidatableContent()
            }
        }
    }
}

private struct QueuePage: View {
    let state: State

    var body: some View {
        VStack(spacing: 4) {
            if state.tracks.isEmpty {
                Text("暂无下一首")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            ForEach(Array(state.tracks.prefix(3).enumerated()), id: \.offset) { _, track in
                Button(intent: SGPlayQueuedTrackIntent(track.uri)) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(green)
                        Text(track.title)
                            .font(.footnote.weight(.semibold))
                        Text(track.artist)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(idle))
                }
                .buttonStyle(.plain)
            }
        }
        .invalidatableContent()
    }
}

private struct TimerPage: View {
    let state: State

    var body: some View {
        Group {
            if (state.timerEnd.map { $0 > Date() } ?? false) || state.timerEndOfTrack {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("停止播放")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                        if let end = state.timerEnd {
                            Text(timerInterval: Date()...end, countsDown: true)
                                .font(.system(size: 34, weight: .bold).monospacedDigit())
                                .foregroundStyle(green)
                        } else {
                            Text("本曲结束")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(green)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        if state.timerEnd != nil {
                            ChipButton(action: "timer:add", symbol: "plus", label: "15 min")
                        }
                        ChipButton(action: "timer:cancel", symbol: "xmark", label: "Cancel")
                    }
                    .frame(width: state.timerEnd != nil ? 140 : 66)
                }
            } else {
                HStack(spacing: 8) {
                    ChipButton(action: "timer:15", symbol: "moon", label: "15 min")
                    ChipButton(action: "timer:30", symbol: "moon", label: "30 min")
                    ChipButton(action: "timer:60", symbol: "moon", label: "1 hour")
                    ChipButton(action: "timer:track", symbol: "music.note", label: "End of track")
                }
            }
        }
        .invalidatableContent()
    }
}
