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
    @State private var showSettings: Bool = false

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
                .frame(maxWidth: 680 * canvasScale, maxHeight: 680 * canvasScale)
                .padding(.vertical, 12)

                Spacer(minLength: 0)

                if showSettings {
                    Divider()
                    settingsPanel
                        .frame(width: 300)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
        .task {
            await loadData()
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
        HStack(spacing: 16) {
            Picker("字库分组", selection: $selectedCategory) {
                ForEach(CharsetCategory.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedCategory) { _ in
                jumpToFirstPendingOrZero()
                drawing = PKDrawing()
            }

            if let prog = currentGroupProgress {
                HStack(spacing: 8) {
                    ProgressView(value: Double(prog.completed), total: Double(max(prog.total, 1)))
                        .frame(width: 120)
                    Text("\(prog.completed)/\(prog.total) (\(String(format: "%.1f", prog.percentage))%)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let item = currentChar {
                HStack(spacing: 12) {
                    Button {
                        moveCharacter(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(currentIndex <= 0)

                    HStack(spacing: 8) {
                        Text(item.char)
                            .font(.title2.bold())
                        Text("U+\(item.unicodeHex)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                        if item.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
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
            .disabled(isExporting || isLoading)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings.toggle()
                }
            } label: {
                Label("设置", systemImage: showSettings ? "sidebar.right" : "gearshape")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var characterPreviewBanner: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(filteredCharacters.enumerated()), id: \.element.id) { index, item in
                        let isSelected = index == currentIndex
                        let cachedPath = svgPathCache[item.unicodeHex.uppercased()]

                        Button {
                            currentIndex = index
                            drawing = PKDrawing()
                        } label: {
                            VStack(spacing: 3) {
                                ZStack {
                                    if item.isCompleted, let pathStr = cachedPath, !pathStr.isEmpty {
                                        SVGPathShape(svgPath: pathStr, sourceSize: 1000)
                                            .fill(Color.primary)
                                            .frame(width: 28, height: 28)
                                    } else {
                                        Text(item.char)
                                            .font(.system(size: 20, weight: item.isCompleted ? .semibold : .regular))
                                            .foregroundColor(item.isCompleted ? .primary : .secondary.opacity(0.45))
                                            .frame(width: 28, height: 28)
                                    }
                                }
                                .frame(width: 34, height: 34)
                                .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                                .cornerRadius(6)

                                Rectangle()
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                                    .frame(width: 24, height: 3)
                                    .cornerRadius(1.5)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
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

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let progress = try await apiClient.fetchProgress()
            allCharacters = progress.characters
            groupProgress = progress.groups
            jumpToFirstPendingOrZero()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                mergedSvgPath: converted.mergedSvgPath
            )
            svgPathCache[item.unicodeHex.uppercased()] = converted.mergedSvgPath
            if let globalIdx = allCharacters.firstIndex(where: { $0.id == item.id }) {
                allCharacters[globalIdx].status = "completed"
            }
            if let prog = try? await apiClient.fetchProgress() {
                allCharacters = prog.characters
                groupProgress = prog.groups
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
            let fileURL = try await apiClient.exportTTF(fontName: exportFontName)
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

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / max(sourceSize, 1)
        let scaleY = rect.height / max(sourceSize, 1)

        let tokens = tokenize(svgPath)
        var i = 0
        var currentCmd: Character = "M"

        while i < tokens.count {
            let token = tokens[i]
            if token.count == 1, let ch = token.first, ch.isLetter {
                currentCmd = ch
                i += 1
                if currentCmd == "Z" || currentCmd == "z" {
                    path.closeSubpath()
                }
                continue
            }

            switch currentCmd {
            case "M":
                if i + 1 < tokens.count, let x = Double(tokens[i]), let y = Double(tokens[i + 1]) {
                    path.move(to: CGPoint(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY))
                    i += 2
                    currentCmd = "L"
                } else {
                    i += 1
                }
            case "L":
                if i + 1 < tokens.count, let x = Double(tokens[i]), let y = Double(tokens[i + 1]) {
                    path.addLine(to: CGPoint(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY))
                    i += 2
                } else {
                    i += 1
                }
            case "Q":
                if i + 3 < tokens.count,
                   let cx = Double(tokens[i]), let cy = Double(tokens[i + 1]),
                   let x = Double(tokens[i + 2]), let y = Double(tokens[i + 3]) {
                    path.addQuadCurve(
                        to: CGPoint(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY),
                        control: CGPoint(x: CGFloat(cx) * scaleX, y: CGFloat(cy) * scaleY)
                    )
                    i += 4
                } else {
                    i += 1
                }
            case "C":
                if i + 5 < tokens.count,
                   let c1x = Double(tokens[i]), let c1y = Double(tokens[i + 1]),
                   let c2x = Double(tokens[i + 2]), let c2y = Double(tokens[i + 3]),
                   let x = Double(tokens[i + 4]), let y = Double(tokens[i + 5]) {
                    path.addCurve(
                        to: CGPoint(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY),
                        control1: CGPoint(x: CGFloat(c1x) * scaleX, y: CGFloat(c1y) * scaleY),
                        control2: CGPoint(x: CGFloat(c2x) * scaleX, y: CGFloat(c2y) * scaleY)
                    )
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

    private func tokenize(_ d: String) -> [String] {
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
