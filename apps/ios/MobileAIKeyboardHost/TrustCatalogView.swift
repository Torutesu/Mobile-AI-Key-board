import SwiftUI
import MobileAIKeyboardCore

struct TrustCatalogView: View {
    @EnvironmentObject private var store: AccountActivityStore
    @State private var selectedSkillID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                catalogBoundary
                ForEach(store.trustCatalog) { metadata in
                    catalogCard(metadata)
                    if selectedSkillID == metadata.id {
                        trustPreview(metadata)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Trust Preview / Skill catalog")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var catalogBoundary: some View {
        Text("Community catalogはlocal fixtureです。SK-006のpublisher・operations/scopes・data inputs・risk class・version・last review timestamp・installs・completed/attempted rate・typed issue countsを表示します。Trust Previewはfixture metadataの整合性だけを確認し、publisher/package/署名を検証しません。public marketplaceは未実装です。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
    }

    private func catalogCard(_ metadata: CommunitySkillMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(metadata.id, systemImage: "shippingbox")
                .font(.headline)
            metadataRow("Publisher", metadata.publisher)
            metadataRow("Requested operations", metadata.requestedOperations.joined(separator: ", "))
            metadataRow("Requested connectors/scopes", metadata.requestedConnectorsScopes.joined(separator: ", "))
            metadataRow("Data inputs", metadata.dataInputs.joined(separator: ", "))
            metadataRow("Risk class", metadata.riskClass)
            metadataRow("Version", metadata.version)
            metadataRow("Last review", metadata.lastReviewDate)
            metadataRow("Installs", "\(metadata.installs)")
            metadataRow("Completion rate", metadata.completionRateDisplay)
            Text("rate is derived from integer completed/attempted counts; fewer than \(CommunitySkillMetadata.lowConfidenceAttemptThreshold) attempts stays not_proven")
                .font(.caption)
                .foregroundStyle(.secondary)
            metadataRow("Issue counts", "correctness \(metadata.reportedIssueCounts.correctness), safety \(metadata.reportedIssueCounts.safety), privacy \(metadata.reportedIssueCounts.privacy), availability \(metadata.reportedIssueCounts.availability), other \(metadata.reportedIssueCounts.other)")
            metadataRow("Provenance", "\(metadata.provenance.source) / \(metadata.provenance.publisher.rawValue)")
            Button(selectedSkillID == metadata.id ? "Trust Previewを閉じる" : "Trust Previewを開く") {
                selectedSkillID = selectedSkillID == metadata.id ? nil : metadata.id
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func trustPreview(_ metadata: CommunitySkillMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("実行前Trust Preview", systemImage: "eye")
                .font(.headline)
            Text("入力: \(metadata.dataInputs.joined(separator: ", "))")
            Text("tools/scopes: \(metadata.requestedConnectorsScopes.joined(separator: ", "))")
            Text("side effect: none (catalog fixture)")
            Text("publisher: \(metadata.provenance.publisher.rawValue) / package: \(metadata.provenance.package.rawValue)")
            Text("runtime sync: \(metadata.provenance.runtimeSync)")
            Text("digest: \(metadata.declaredMetadataDigest)")
                .textSelection(.enabled)
            Text(TrustPreviewValidator().validate(metadata).allowed ? "fixture metadata consistency: pass (publisher/package/signature verification: not_proven)" : "fixture metadata consistency: denied")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).fontWeight(.semibold)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }
}
