import SwiftUI
import MobileAIKeyboardCore

struct ContextualSuggestionsView: View {
    @EnvironmentObject private var store: AccountActivityStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                disclosureCard
                contextCard
                if store.suggestions.suggestions.isEmpty {
                    Button("端末内fixture候補を確認") {
                        store.send(.refresh(ContextualSuggestionContext(editorBoundaryID: "local-editor-boundary", characterCountBucket: "20-49", locale: "ja-JP")))
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                } else {
                    ForEach(store.suggestions.suggestions) { suggestion in
                        suggestionCard(suggestion)
                    }
                    Text("自動適用は常に無効です。候補を確認しても、入力欄へ変更を加えません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Contextual suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if store.state.account.canUseAuthenticatedFeatures == false && store.suggestions.suggestions.isEmpty {
                store.send(.refresh(ContextualSuggestionContext(editorBoundaryID: "local-editor-boundary", characterCountBucket: "20-49", locale: "ja-JP")))
            }
        }
    }

    private var disclosureCard: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("端末内の候補")
                    .font(.headline)
                Text("raw textは保持・送信・telemetry記録しません。候補は手動previewのみで、secure fieldでは無効です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(.green)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Context metadata")
                .font(.headline)
            if let context = store.suggestions.context {
                Text("opaque editor boundary: locally owned / bounded")
                Text("length bucket: \(context.characterCountBucket) / locale: \(context.locale)")
                Text(context.secureField ? "secure field: disabled" : "secure field: false")
            } else {
                Text("まだcontextは生成されていません")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func suggestionCard(_ suggestion: ContextualSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(suggestion.title, systemImage: icon(for: suggestion.kind))
                .font(.headline)
            Text("risk \(suggestion.riskClass)・preview only")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(suggestion.sourceDisclosure)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(store.suggestions.selectedSuggestionID == suggestion.id ? "preview済み" : "候補をpreview") {
                store.send(.preview(id: suggestion.id))
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityLabel("\(suggestion.title)をpreview")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func icon(for kind: ContextualSuggestionKind) -> String {
        switch kind {
        case .politeRewrite: return "text.badge.checkmark"
        case .conciseRewrite: return "text.badge.minus"
        case .keyPoints: return "list.bullet"
        }
    }
}
