import SwiftUI
import MobileAIKeyboardCore

struct SandboxView: View {
    @State private var input = "明日の会議、よろしく"
    @State private var result: RewriteResult?
    private let engine = LocalRewriteEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("端末内サンドボックス", systemImage: "sparkles")
                .font(.headline)
            Text("ネットワークを使わず、短い文章を丁寧に整えます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $input)
                .frame(minHeight: 88)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                .accessibilityLabel("書き換える文章")
            Button("丁寧に整える") {
                result = engine.politeRewrite(input)
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityHint("文章を端末内で整え、結果をプレビューします")
            if let result {
                VStack(alignment: .leading, spacing: 6) {
                    Text("プレビュー").font(.subheadline.bold())
                    Text(result.rewritten)
                    Text("適用前に内容を確認してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("書き換え結果。\(result.rewritten) 適用前に内容を確認してください。")
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
