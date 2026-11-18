import SwiftUI
import PencilKit

struct PencilCanvasView: View {
    @Binding var drawing: PKDrawing
    @Binding var pencilOnly: Bool
    let referenceChar: String
    let referenceFont: ReferenceFontOption
    let referenceOpacity: Double
    @Binding var canvasSize: CGSize

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white

                MiZiGeGridView()
                    .stroke(Color.gray.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))

                if !referenceChar.isEmpty && referenceOpacity > 0.001 {
                    Text(referenceChar)
                        .font(referenceFontFont(size: min(geo.size.width, geo.size.height) * 0.72))
                        .foregroundColor(.black.opacity(referenceOpacity))
                        .allowsHitTesting(false)
                }

                PKCanvasRepresentable(
                    drawing: $drawing,
                    pencilOnly: $pencilOnly
                )
                .background(Color.clear)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1.5)
            )
            .onAppear {
                canvasSize = geo.size
            }
            .onChange(of: geo.size) { newSize in
                canvasSize = newSize
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func referenceFontFont(size: CGFloat) -> Font {
        switch referenceFont {
        case .system:
            return .system(size: size, weight: .regular, design: .serif)
        case .kaiti, .songti, .heiti, .pingfang, .maShanZheng, .longCang, .yuanti:
            return .custom(referenceFont.rawValue, size: size)
        }
    }
}

private struct MiZiGeGridView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Center cross
        path.move(to: CGPoint(x: w / 2, y: 0))
        path.addLine(to: CGPoint(x: w / 2, y: h))
        path.move(to: CGPoint(x: 0, y: h / 2))
        path.addLine(to: CGPoint(x: w, y: h / 2))

        // Diagonals
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w, y: h))
        path.move(to: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: 0, y: h))

        return path
    }
}

private struct PKCanvasRepresentable: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var pencilOnly: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 18)
        canvas.delegate = context.coordinator

        let toolPicker = PKToolPicker()
        context.coordinator.toolPicker = toolPicker
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
        }

        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        let targetPolicy: PKCanvasViewDrawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        if uiView.drawingPolicy != targetPolicy {
            uiView.drawingPolicy = targetPolicy
        }
        if uiView.drawing != drawing {
            context.coordinator.isUpdatingFromSwiftUI = true
            uiView.drawing = drawing
            context.coordinator.isUpdatingFromSwiftUI = false
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PKCanvasRepresentable
        var toolPicker: PKToolPicker?
        var isUpdatingFromSwiftUI = false

        init(_ parent: PKCanvasRepresentable) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingFromSwiftUI else { return }
            DispatchQueue.main.async {
                self.parent.drawing = canvasView.drawing
            }
        }
    }
}
