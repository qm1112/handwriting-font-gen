import SwiftUI
import PencilKit
import UIKit

struct ContentView: View {
    @StateObject private var apiClient = APIClient()

    @State private var selectedCategory: CharsetCategory = .basic50
    @State private var allCharacters: [CharItem] = []
    @State private var groupProgress: [String: GroupProgress] = [:]
    @State private var currentIndex: Int = 0
    @State private var svgPathCache: [String: String] = [:]

    @State private var drawing = PKDrawing()
    @State private var canvasSize: CGSize = CGSize(width: 600, height: 600)

    @State private var pencilOnly: Bool = true
    @AppStorage("handwriting_canvas_scale") private var canvasScale: Double = 1.0
    @AppStorage("handwriting_reference_font") private var referenceFontRaw: String = ReferenceFontOption.kaiti.rawValue
    @AppStorage("handwriting_reference_opacity") private var referenceOpacity: Double = 0.16
    @AppStorage("handwriting_font_tag") private var fontTag: String = "default"
    @AppStorage("handwriting_show_right_panel") private var showRightPanel: Bool = true

    @State private var availableTags: [TagItem] = []
    @State private var tagInput: String = "default"
    @State private var syncTask: Task<Void, Never>?

    @State private var isLoading: Bool = false
    @State private var isSaving: Bool = false
    @State private var isExporting: Bool = false
    @State private var showExportAlert: Bool = false
    @State private var exportFontName: String = "MyHandwriting"
    @State private var exportedFileURL: URL?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var referenceFont: ReferenceFontOption {
        ReferenceFontOption(rawValue: referenceFontRaw) ?? .kaiti
    }

    private var filteredCharacters: [CharItem] {
        allCharacters.filter { $0.category == selectedCategory.rawValue }
    }

    private var currentChar: CharItem? {
        guard !filteredCharacters.isEmpty,
              currentIndex >= 0,
              currentIndex < filteredCharacters.count else {
            return nil
        }
        return filteredCharacters[currentIndex]
    }

    private var currentGroupProgress: GroupProgress? {
        groupProgress[selectedCategory.rawValue]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            characterPreviewBanner
            Divider()

            HStack(spacing: 16) {
                leftActionRail
                Spacer(minLength: 0)

                PencilCanvasView(
                    drawing: $drawing,
                    pencilOnly: $pencilOnly,
                    referenceChar: currentChar?.char ?? "",
                    referenceFont: referenceFont,
                    referenceOpacity: referenceOpacity,
                    canvasSize: $canvasSize
                )
                .frame(width: 680, height: 680)
                .scaleEffect(canvasScale)
                .frame(width: 680 * canvasScale, height: 680 * canvasScale)
                .padding(.vertical, 12)

                Spacer(minLength: 0)

                if showRightPanel {
                    Divider()
                    VStack(spacing: 0) {
                        HStack {
                            Text("设置")
                                .font(.headline)
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showRightPanel = false
                                }
                            } label: {
                                Image(systemName: "sidebar.right")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("折叠设置栏")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground))

                        Divider()

                        settingsPanel
                    }
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
        .task {
            tagInput = fontTag
            await loadData()
        }
        .onChange(of: currentIndex) { _ in
            Task { await loadCurrentCharIfCompleted() }
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("导出 TTF 字体", isPresented: $showExportAlert) {
            TextField("字体名称", text: $exportFontName)
            Button("取消", role: .cancel) {}
            Button("生成并导出") {
                Task { await exportTTF() }
            }
        } message: {
            Text("请输入导出的字体名称（将打包所有已完成字符）")
        }
        .sheet(isPresented: Binding(
            get: { exportedFileURL != nil },
            set: { if !$0 { exportedFileURL = nil } }
        )) {
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Picker("字库分组", selection: $selectedCategory) {
                ForEach(CharsetCategory.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedCategory) { _ in
                jumpToFirstPendingOrZero()
                drawing = PKDrawing()
                Task {
                    await prefetchCompletedCharsInCurrentGroup()
                    await loadCurrentCharIfCompleted()
                }
            }

            if let prog = currentGroupProgress {
                HStack(spacing: 6) {
                    ProgressView(value: Double(prog.completed), total: Double(max(prog.total, 1)))
                        .frame(width: 96)
                    Text("\(prog.completed)/\(prog.total) (\(String(format: "%.1f", prog.percentage))%)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let item = currentChar {
                HStack(spacing: 10) {
                    Button {
                        moveCharacter(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(currentIndex <= 0)

                    HStack(spacing: 8) {
                        Text(item.char)
                            .font(.system(size: 30, weight: .bold))
                            .frame(minWidth: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("U+\(item.unicodeHex)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                            Text(fontTag)
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                        }
                        if item.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)

                    Button {
                        moveCharacter(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(currentIndex >= filteredCharacters.count - 1)
                }
            } else if isLoading {
                ProgressView()
            } else {
                Text("暂无字符数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let msg = statusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            Button {
                showExportAlert = true
            } label: {
                if isExporting {
                    ProgressView()
                } else {
                    Label("导出 TTF", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isExporting || isLoading)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRightPanel.toggle()
                }
            } label: {
                Label(showRightPanel ? "收起" : "设置", systemImage: "sidebar.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    private var characterPreviewBanner: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(filteredCharacters.enumerated()), id: \.element.id) { index, item in
                        let isSelected = index == currentIndex
                        let cachedPath = svgPathCache[item.unicodeHex.uppercased()]

                        Button {
                            currentIndex = index
                            drawing = PKDrawing()
                        } label: {
                            VStack(spacing: 2) {
                                ZStack {
                                    if item.isCompleted,
                                       let pathStr = cachedPath,
                                       !pathStr.isEmpty,
                                       SVGPathShape.hasValidPath(pathStr) {
                                        SVGPathShape(svgPath: pathStr, sourceSize: 1000)
                                            .fill(Color.primary)
                                            .frame(width: 20, height: 20)
                                    } else {
                                        Text(item.char)
                                            .font(.system(size: 16, weight: item.isCompleted ? .semibold : .regular))
                                            .foregroundColor(item.isCompleted ? .primary : .secondary.opacity(0.45))
                                            .frame(width: 20, height: 20)
                                    }
                                }
                                .frame(width: 22, height: 26)
                                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                                .cornerRadius(5)

                                Rectangle()
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                                    .frame(width: 20, height: 2.5)
                                    .cornerRadius(1.25)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .frame(height: 40)
            .background(Color(.secondarySystemBackground).opacity(0.6))
            .onChange(of: currentIndex) { _ in
                if let item = currentChar {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }
        }
    }

    private var leftActionRail: some View {
        VStack(spacing: 14) {
            Button {
                undoLastStroke()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title2)
                    Text("撤销")
                        .font(.caption)
                }
                .frame(width: 72, height: 68)
            }
            .buttonStyle(.bordered)
            .disabled(drawing.strokes.isEmpty || isSaving)

            Button(role: .destructive) {
                drawing = PKDrawing()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.title2)
                    Text("清空")
                        .font(.caption)
                }
                .frame(width: 72, height: 68)
            }
            .buttonStyle(.bordered)
            .disabled(drawing.strokes.isEmpty || isSaving)

            Spacer()

            Button {
                Task { await saveAndNext() }
            } label: {
                VStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                    }
                    Text("保存并\n下一个")
                        .font(.caption.bold())
                        .multilineTextAlignment(.center)
                }
                .frame(width: 72, height: 86)
            }
            .buttonStyle(.borderedProminent)
            .disabled(drawing.strokes.isEmpty || currentChar == nil || isSaving)
        }
        .padding(.vertical, 20)
    }

    private var settingsPanel: some View {
        Form {
            Section("字体集 Tag") {
                HStack(spacing: 8) {
                    TextField("Tag 名称", text: $tagInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task { await switchTag(to: tagInput) }
                        }

                    Button("切换") {
                        Task { await switchTag(to: tagInput) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !availableTags.isEmpty {
                    ForEach(availableTags) { item in
                        Button {
                            tagInput = item.tag
                            Task { await switchTag(to: item.tag) }
                        } label: {
                            HStack {
                                Text(item.tag)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(item.completed) 字")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                if item.tag == fontTag {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }

            Section("服务器连接") {
                TextField("服务器地址", text: $apiClient.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button {
                    Task { await loadData() }
                } label: {
                    Label("重新同步进度", systemImage: "arrow.clockwise")
                }
            }

            Section("画布与输入") {
                Toggle("仅 Apple Pencil 书写", isOn: $pencilOnly)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("书写区域大小")
                        Spacer()
                        Text("\(Int(canvasScale * 100))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $canvasScale, in: 0.25...1.0, step: 0.05)
                }

                Picker("参考字体", selection: $referenceFontRaw) {
                    ForEach(ReferenceFontOption.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("参考字透明度")
                        Spacer()
                        Text("\(Int(referenceOpacity * 100))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $referenceOpacity, in: 0.0...0.8, step: 0.02)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func undoLastStroke() {
        guard !drawing.strokes.isEmpty else { return }
        var updated = drawing
        updated.strokes.removeLast()
        drawing = updated
    }

    private func moveCharacter(by offset: Int) {
        let next = currentIndex + offset
        guard next >= 0, next < filteredCharacters.count else { return }
        currentIndex = next
        drawing = PKDrawing()
    }

    private func jumpToFirstPendingOrZero() {
        if let idx = filteredCharacters.firstIndex(where: { !$0.isCompleted }) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }
    }

    private func switchTag(to newTag: String) async {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = trimmed.isEmpty ? "default" : trimmed
        tagInput = target
        fontTag = target
        svgPathCache.removeAll()
        drawing = PKDrawing()
        await loadData()
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let progressTask = apiClient.fetchProgress(tag: fontTag)
            async let tagsTask = apiClient.fetchTags()
            let progress = try await progressTask
            allCharacters = progress.characters
            groupProgress = progress.groups
            if let tagsResp = try? await tagsTask {
                availableTags = tagsResp.tags
            }
            jumpToFirstPendingOrZero()
            await prefetchCompletedCharsInCurrentGroup()
            await loadCurrentCharIfCompleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prefetchCompletedCharsInCurrentGroup() async {
        syncTask?.cancel()
        let completed = filteredCharacters.filter { $0.isCompleted }
        guard !completed.isEmpty else { return }
        let tag = fontTag
        let task = Task {
            await withTaskGroup(of: (String, String?).self) { group in
                for item in completed {
                    let hex = item.unicodeHex.uppercased()
                    if svgPathCache[hex] != nil { continue }
                    group.addTask {
                        let detail = try? await apiClient.fetchChar(hex: hex, tag: tag)
                        return (hex, detail?.mergedSvgPath)
                    }
                }
                for await (hex, svgPath) in group {
                    if Task.isCancelled { break }
                    if let path = svgPath, !path.isEmpty {
                        svgPathCache[hex] = path
                    }
                }
            }
        }
        syncTask = task
        await task.value
    }

    private func loadCurrentCharIfCompleted() async {
        guard let item = currentChar, item.isCompleted else { return }
        let hex = item.unicodeHex.uppercased()
        do {
            let detail = try await apiClient.fetchChar(hex: hex, tag: fontTag)
            if let path = detail.mergedSvgPath, !path.isEmpty {
                svgPathCache[hex] = path
            }
            if currentChar?.unicodeHex.uppercased() == hex,
               drawing.strokes.isEmpty,
               let strokesJson = detail.strokesJson,
               !strokesJson.isEmpty {
                drawing = makePKDrawing(from: strokesJson, canvasSize: canvasSize)
            }
        } catch {
            // 忽略单个字符拉取失败，避免打断书写流程
        }
    }

    private func makePKDrawing(from strokesJson: [[StrokePointData]], canvasSize: CGSize) -> PKDrawing {
        let width = max(canvasSize.width, 1)
        let height = max(canvasSize.height, 1)
        let ink = PKInk(.pen, color: .black)
        var pkStrokes: [PKStroke] = []

        for stroke in strokesJson {
            guard !stroke.isEmpty else { continue }
            var points: [PKStrokePoint] = []
            for (idx, pt) in stroke.enumerated() {
                let loc = CGPoint(x: pt.x / 1000.0 * width, y: pt.y / 1000.0 * height)
                let strokeWidth = max(CGFloat(pt.w) / 1000.0 * width, 1.0)
                let point = PKStrokePoint(
                    location: loc,
                    timeOffset: TimeInterval(idx) * 0.01,
                    size: CGSize(width: strokeWidth, height: strokeWidth),
                    opacity: 1.0,
                    force: 1.0,
                    azimuth: 0,
                    altitude: .pi / 2
                )
                points.append(point)
            }
            let path = PKStrokePath(controlPoints: points, creationDate: Date())
            pkStrokes.append(PKStroke(ink: ink, path: path))
        }
        return PKDrawing(strokes: pkStrokes)
    }

    private func saveAndNext() async {
        guard let item = currentChar else { return }
        isSaving = true
        defer { isSaving = false }

        let converted = StrokeConverter.convert(drawing: drawing, canvasSize: canvasSize)
        do {
            try await apiClient.saveChar(
                hex: item.unicodeHex,
                strokesJson: converted.strokesJson,
                mergedSvgPath: converted.mergedSvgPath,
                tag: fontTag
            )
            svgPathCache[item.unicodeHex.uppercased()] = converted.mergedSvgPath
            if let globalIdx = allCharacters.firstIndex(where: { $0.id == item.id }) {
                allCharacters[globalIdx].status = "completed"
            }
            if let prog = try? await apiClient.fetchProgress(tag: fontTag) {
                allCharacters = prog.characters
                groupProgress = prog.groups
            }
            if let tagsResp = try? await apiClient.fetchTags() {
                availableTags = tagsResp.tags
            }
            statusMessage = "已保存 \(item.char)"
            drawing = PKDrawing()
            if currentIndex < filteredCharacters.count - 1 {
                currentIndex += 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportTTF() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let fileURL = try await apiClient.exportTTF(fontName: exportFontName, tag: fontTag)
            exportedFileURL = fileURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct SVGPathShape: Shape {
    let svgPath: String
    let sourceSize: CGFloat

    static func hasValidPath(_ svgPath: String) -> Bool {
        let testRect = CGRect(x: 0, y: 0, width: 20, height: 20)
        return !buildPath(from: svgPath, in: testRect, sourceSize: 1000).isEmpty
    }

    func path(in rect: CGRect) -> Path {
        Self.buildPath(from: svgPath, in: rect, sourceSize: sourceSize)
    }

    static func buildPath(from svgPath: String, in rect: CGRect, sourceSize: CGFloat) -> Path {
        var path = Path()
        let scaleX = rect.width / max(sourceSize, 1)
        let scaleY = rect.height / max(sourceSize, 1)

        let dString = extractPathData(from: svgPath)
        guard !dString.isEmpty else { return path }
        let tokens = tokenize(dString)
        var i = 0
        var currentCmd: Character = "M"
        var currentPoint = CGPoint.zero
        var subpathStart = CGPoint.zero

        while i < tokens.count {
            let token = tokens[i]
            if token.count == 1, let ch = token.first, ch.isLetter {
                currentCmd = ch
                i += 1
                if currentCmd == "Z" || currentCmd == "z" {
                    path.closeSubpath()
                    currentPoint = subpathStart
                }
                continue
            }

            switch currentCmd {
            case "M":
                if i + 1 < tokens.count, let x = Double(tokens[i]), let y = Double(tokens[i + 1]) {
                    let pt = CGPoint(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY)
                    path.move(to: pt)
                    currentPoint = pt
                    subpathStart = pt
                    i += 2
                    currentCmd = "L"
                } else {
                    i += 1
                }
            case "m":
                if i + 1 < tokens.count, let dx = Double(tokens[i]), let dy = Double(tokens[i + 1]) {
                    let pt = CGPoint(x: currentPoint.x + CGFloat(dx) * scaleX, y: currentPoint.y + CGFloat(dy) * scaleY)
                    path.move(to: pt)
                    currentPoint = pt
                    subpathStart = pt
                    i += 2
                    currentCmd = "l"
                } else {
                    i += 1
                }
            case "L":
                if i + 1 < tokens.count, let x = Double(tokens[i]), let y = Double(tokens[i + 1]) {
                    let pt = CGPoint(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY)
                    path.addLine(to: pt)
                    currentPoint = pt
                    i += 2
                } else {
                    i += 1
                }
            case "l":
                if i + 1 < tokens.count, let dx = Double(tokens[i]), let dy = Double(tokens[i + 1]) {
                    let pt = CGPoint(x: currentPoint.x + CGFloat(dx) * scaleX, y: currentPoint.y + CGFloat(dy) * scaleY)
                    path.addLine(to: pt)
                    currentPoint = pt
                    i += 2
                } else {
                    i += 1
                }
            case "Q":
                if i + 3 < tokens.count,
                   let cx = Double(tokens[i]), let cy = Double(tokens[i + 1]),
                   let x = Double(tokens[i + 2]), let y = Double(tokens[i + 3]) {
                    let pt = CGPoint(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY)
                    path.addQuadCurve(
                        to: pt,
                        control: CGPoint(x: CGFloat(cx) * scaleX, y: CGFloat(cy) * scaleY)
                    )
                    currentPoint = pt
                    i += 4
                } else {
                    i += 1
                }
            case "q":
                if i + 3 < tokens.count,
                   let dcx = Double(tokens[i]), let dcy = Double(tokens[i + 1]),
                   let dx = Double(tokens[i + 2]), let dy = Double(tokens[i + 3]) {
                    let pt = CGPoint(x: currentPoint.x + CGFloat(dx) * scaleX, y: currentPoint.y + CGFloat(dy) * scaleY)
                    path.addQuadCurve(
                        to: pt,
                        control: CGPoint(x: currentPoint.x + CGFloat(dcx) * scaleX, y: currentPoint.y + CGFloat(dcy) * scaleY)
                    )
                    currentPoint = pt
                    i += 4
                } else {
                    i += 1
                }
            case "C":
                if i + 5 < tokens.count,
                   let c1x = Double(tokens[i]), let c1y = Double(tokens[i + 1]),
                   let c2x = Double(tokens[i + 2]), let c2y = Double(tokens[i + 3]),
                   let x = Double(tokens[i + 4]), let y = Double(tokens[i + 5]) {
                    let pt = CGPoint(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY)
                    path.addCurve(
                        to: pt,
                        control1: CGPoint(x: CGFloat(c1x) * scaleX, y: CGFloat(c1y) * scaleY),
                        control2: CGPoint(x: CGFloat(c2x) * scaleX, y: CGFloat(c2y) * scaleY)
                    )
                    currentPoint = pt
                    i += 6
                } else {
                    i += 1
                }
            case "c":
                if i + 5 < tokens.count,
                   let dc1x = Double(tokens[i]), let dc1y = Double(tokens[i + 1]),
                   let dc2x = Double(tokens[i + 2]), let dc2y = Double(tokens[i + 3]),
                   let dx = Double(tokens[i + 4]), let dy = Double(tokens[i + 5]) {
                    let pt = CGPoint(x: currentPoint.x + CGFloat(dx) * scaleX, y: currentPoint.y + CGFloat(dy) * scaleY)
                    path.addCurve(
                        to: pt,
                        control1: CGPoint(x: currentPoint.x + CGFloat(dc1x) * scaleX, y: currentPoint.y + CGFloat(dc1y) * scaleY),
                        control2: CGPoint(x: currentPoint.x + CGFloat(dc2x) * scaleX, y: currentPoint.y + CGFloat(dc2y) * scaleY)
                    )
                    currentPoint = pt
                    i += 6
                } else {
                    i += 1
                }
            default:
                i += 1
            }
        }

        return path
    }

    private static func extractPathData(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("<") else { return trimmed }

        let pattern = #"d\s*=\s*(?:"([^"]*)"|'([^']*)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ""
        }
        let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let matches = regex.matches(in: trimmed, options: [], range: nsRange)
        let parts: [String] = matches.compactMap { match in
            if let r1 = Range(match.range(at: 1), in: trimmed) {
                return String(trimmed[r1])
            }
            if let r2 = Range(match.range(at: 2), in: trimmed) {
                return String(trimmed[r2])
            }
            return nil
        }
        return parts.joined(separator: " ")
    }

    private static func tokenize(_ d: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                result.append(String(ch))
            } else if ch == " " || ch == "," || ch == "\n" || ch == "\t" {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
