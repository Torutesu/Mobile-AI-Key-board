import SwiftUI
import MobileAIKeyboardCore

struct TeamPolicyView: View {
    @EnvironmentObject private var store: AccountActivityStore
    private let metadata = CommunitySkillCatalogFixture.metadata
    private var upgradeMetadata: CommunitySkillMetadata {
        let draft = CommunitySkillMetadata(id: metadata.id, publisher: metadata.publisher, requestedOperations: metadata.requestedOperations, requestedConnectorsScopes: metadata.requestedConnectorsScopes, dataInputs: metadata.dataInputs, riskClass: metadata.riskClass, confirmationPolicy: metadata.confirmationPolicy, version: "2.0.0", lastReviewDate: metadata.lastReviewDate, installs: metadata.installs, completionCompleted: metadata.completionCompleted, completionAttempted: metadata.completionAttempted, reportedIssueCounts: metadata.reportedIssueCounts, provenance: metadata.provenance)
        return draft.withDeclaredDigest(draft.computedMetadataDigest)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Team policyはprivate fixtureです。owner・team・Skill version・digestを束ね、install/upgradeは毎回明示確認します。revocation後のbindingは無効です。")
                    .font(.body)
                policyCard
                if store.state.account.canUseAuthenticatedFeatures {
                    Button("policy preview") {
                        store.send(.preview(ownerSubject: "fixture-user:Fixture User"))
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    Button("private Skillを明示install") {
                        store.send(.install(metadata: metadata, policy: store.teamPolicy.rules, ownerSubject: "fixture-user:Fixture User", explicitConfirm: true))
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    Button("v2へ明示upgrade") {
                        store.send(.upgrade(metadata: upgradeMetadata, policy: store.teamPolicy.rules, ownerSubject: "fixture-user:Fixture User", explicitConfirm: true))
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    Button("bindingをrevoke") { store.send(.revoke) }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                } else {
                    Text("team policyのinstallにはactive signed-in sessionが必要です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Team policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var policyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("policy \(store.teamPolicy.policyVersion) / team \(store.teamPolicy.teamID)")
                .font(.headline)
            Text("epoch: \(store.teamPolicy.policyEpoch) / canonical digest: \(store.teamPolicy.policyCanonicalDigest)")
            Text("allowed operations: \(store.teamPolicy.allowedOperations.joined(separator: ", "))")
            Text("allowed scopes: \(store.teamPolicy.allowedScopes.joined(separator: ", "))")
            Text("risk ceiling: \(store.teamPolicy.riskCeiling) / confirmation floor: \(store.teamPolicy.confirmationFloor)")
            Text("decision: \(String(describing: store.teamPolicy.decision))")
            if let binding = store.teamPolicy.binding {
                Text("owner: \(binding.ownerSubject)")
                Text("Skill: \(binding.skillID) v\(binding.version)")
                Text("digest: \(binding.digest)")
                    .textSelection(.enabled)
            } else {
                Text("installed binding: none")
                    .foregroundStyle(.secondary)
            }
            Text("public sharing / verified publisher / runtime sync: disabled or not_proven")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
