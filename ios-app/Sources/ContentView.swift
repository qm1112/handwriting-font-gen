import SwiftUI
import PencilKit

struct ContentView: View {
    @StateObject private var apiClient = APIClient()

    @State private var selectedCategory: CharsetCategory = .basic50
    @State private var allCharacters: [CharItem] = []
    @State private var groupProgress: [String: GroupProgress] = [:]
    @State private var currentIndex: Int = 0

    @State private var drawing = PKDrawing()
    @State private var canvasSize: CGSize = CGSize(width: 600, height: 600)

    @State private var pencilOnly: Bool = true
    @State private var referenceOpacity: Double = 0.16
    @State private var showSettings: Bool = false

    @State private var isLoading: Bool = false
    @State private var isSaving: Bool = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

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

            HStack(spacing: 16) {
                leftActionRail
                Spacer(minLength: 0)

                PencilCanvasView(
                    drawing: $drawing,
                    pencilOnly: $pencilOnly,
                    referenceChar: currentChar?.char ?? "",
                    referenceOpacity: referenceOpacity,
                    canvasSize: $canvasSize
                )
                .frame(maxWidth: 680, maxHeight: 680)
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
                        Text("参考字透明度")
                        Spacer()
                        Text("\(Int(referenceOpacity * 100))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $referenceOpacity, in: 0...0.6, step: 0.02)
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
}
