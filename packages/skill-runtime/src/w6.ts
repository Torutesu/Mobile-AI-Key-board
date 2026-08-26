import { randomUUID } from "node:crypto";
import { PrivateSkillShare, SkillBinding, SkillDefinition, SkillDraft, SkillReservation, SkillVersion, skillDefinitionDigest, type DeviceId, type UserId } from "@mobile-ai-keyboard/contracts";
import type { PrivateSkillShare as PrivateSkillShareData, SkillBinding as SkillBindingData, SkillDefinition as SkillDefinitionData, SkillDraft as SkillDraftData, SkillQuota as SkillQuotaData, SkillReservation as SkillReservationData, SkillVersion as SkillVersionData } from "@mobile-ai-keyboard/contracts";
import { assertPublicSkillPublishingDisabled, assertSkillVersionImmutable, PolicyViolation, validatePrivateSkillShare, validateQuotaReservation, validateSkillBinding, validateSkillDefinition, validateSkillDraft, validateSkillTestRun, validateSkillVersion } from "@mobile-ai-keyboard/policy";
import type { Clock } from "./w3.js";

export type W6ErrorCode = "INVALID_CONTRACT" | "SKILL_NOT_FOUND" | "DRAFT_NOT_FOUND" | "DRAFT_OWNER_MISMATCH" | "SKILL_VALIDATION_FAILED" | "SKILL_TEST_REQUIRED" | "SKILL_TEST_STALE" | "SKILL_TEST_RESULT_INVALID" | "VERSION_NOT_FOUND" | "IMMUTABLE_VERSION_CONFLICT" | "PUBLIC_PUBLISH_DISABLED" | "BINDING_CONFLICT" | "BINDING_VERSION_MISMATCH" | "TYPING_CONFLICT" | "ACCESSIBILITY_CONFLICT" | "SHARE_BINDING_MISMATCH" | "QUOTA_EXCEEDED" | "QUOTA_IDEMPOTENCY_CONFLICT" | "RESERVATION_NOT_FOUND" | "RESERVATION_OWNER_MISMATCH" | "RESERVATION_STATE_CONFLICT";
export class W6Error extends Error { constructor(readonly code: W6ErrorCode, message: string) { super(message); this.name = "W6Error"; } }
const nowDefault: Clock = () => new Date();
const id = (prefix: string): string => `${prefix}_${randomUUID().replaceAll("-", "")}`;
const clone = <T>(value: T): T => structuredClone(value);
const policyError = (error: unknown, fallback: W6ErrorCode = "SKILL_VALIDATION_FAILED"): W6Error => {
  if (!(error instanceof PolicyViolation)) return new W6Error("INVALID_CONTRACT", error instanceof Error ? error.message : "Skill contract is invalid");
  const code = String(error.details.code ?? "");
  const mapping: Record<string, W6ErrorCode> = { INVALID_SKILL_SCHEMA: "INVALID_CONTRACT", INVALID_SKILL_DRAFT: "INVALID_CONTRACT", STATIC_INJECTION: "SKILL_VALIDATION_FAILED", MISSING_SKILL_TEST: "SKILL_TEST_REQUIRED", TOOL_SCOPE_MISMATCH: "SKILL_VALIDATION_FAILED", PROHIBITED_SKILL_TOOL: "SKILL_VALIDATION_FAILED", RISK_CEILING_MISMATCH: "SKILL_VALIDATION_FAILED", CONFIRMATION_REQUIRED: "SKILL_VALIDATION_FAILED", SKILL_OWNER_MISMATCH: "DRAFT_OWNER_MISMATCH", SKILL_DIGEST_MISMATCH: "SKILL_VALIDATION_FAILED", INVALID_SKILL_TEST_RUN: "SKILL_TEST_RESULT_INVALID", SKILL_TEST_BINDING_MISMATCH: "SKILL_TEST_STALE", SKILL_TEST_COVERAGE: "SKILL_TEST_RESULT_INVALID", SKILL_TEST_RESULT_INVALID: "SKILL_TEST_RESULT_INVALID", SKILL_TEST_EXPECTATION_MISMATCH: "SKILL_TEST_RESULT_INVALID", IMMUTABLE_VERSION_CONFLICT: "IMMUTABLE_VERSION_CONFLICT", PUBLIC_PUBLISH_DISABLED: "PUBLIC_PUBLISH_DISABLED", INVALID_SKILL_BINDING: "INVALID_CONTRACT", BINDING_VERSION_MISMATCH: "BINDING_VERSION_MISMATCH", INVALID_PRIVATE_SHARE: "INVALID_CONTRACT", SHARE_BINDING_MISMATCH: "SHARE_BINDING_MISMATCH", SHARE_RECIPIENT_INVALID: "SHARE_BINDING_MISMATCH", INVALID_QUOTA_RESERVATION: "INVALID_CONTRACT", QUOTA_PERIOD_INVALID: "QUOTA_EXCEEDED", QUOTA_EXCEEDED: "QUOTA_EXCEEDED" };
  return new W6Error(mapping[code] ?? fallback, error.message);
};

export class SkillRegistry {
  private readonly drafts = new Map<string, SkillDraftData>();
  private readonly versions = new Map<string, SkillVersionData>();
  private readonly shares = new Map<string, PrivateSkillShareData>();
  private readonly versionNumbers = new Map<string, number>();
  constructor(private readonly clock: Clock = nowDefault) {}

  createDraft(owner: { user_id: UserId; device_id: DeviceId }, definitionValue: unknown): SkillDraftData {
    let definition: SkillDefinitionData;
    try { definition = validateSkillDefinition(definitionValue); } catch (error) { throw policyError(error); }
    const now = this.clock().toISOString(); const draft = SkillDraft.parse({ draft_id: id("sdraft"), skill_id: id("skill"), owner_user_id: owner.user_id, owner_device_id: owner.device_id, revision: 1, definition, status: "draft", contract_digest: skillDefinitionDigest(definition), created_at: now, updated_at: now });
    this.drafts.set(draft.draft_id, clone(draft)); return clone(draft);
  }
  updateDraft(draftId: string, owner: { user_id: UserId; device_id: DeviceId }, definitionValue: unknown): SkillDraftData {
    const current = this.drafts.get(draftId); if (!current) throw new W6Error("DRAFT_NOT_FOUND", "Skill draft was not found"); if (current.owner_user_id !== owner.user_id || current.owner_device_id !== owner.device_id) throw new W6Error("DRAFT_OWNER_MISMATCH", "Skill draft does not belong to this owner");
    let definition: SkillDefinitionData; try { definition = validateSkillDefinition(definitionValue); } catch (error) { throw policyError(error); }
    const updated = SkillDraft.parse({ ...current, definition, status: "draft", revision: current.revision + 1, contract_digest: skillDefinitionDigest(definition), updated_at: this.clock().toISOString() }); this.drafts.set(draftId, clone(updated)); return clone(updated);
  }
  validateDraft(draftId: string, owner: { user_id: UserId; device_id: DeviceId }): SkillDraftData {
    const current = this.getDraft(draftId, owner); try { validateSkillDraft(current, owner); } catch (error) { throw policyError(error); }
    const updated = SkillDraft.parse({ ...current, status: "validated", updated_at: this.clock().toISOString() }); this.drafts.set(draftId, clone(updated)); return clone(updated);
  }
  markTested(draftId: string, owner: { user_id: UserId; device_id: DeviceId }, testRun: unknown): SkillDraftData {
    const current = this.getDraft(draftId, owner); if (current.status !== "validated") throw new W6Error("SKILL_VALIDATION_FAILED", "Skill draft must pass validation before testing"); try { validateSkillTestRun(testRun, current, this.clock()); } catch (error) { throw policyError(error, "SKILL_TEST_RESULT_INVALID"); }
    const updated = SkillDraft.parse({ ...current, status: "tested", updated_at: this.clock().toISOString() }); this.drafts.set(draftId, clone(updated)); return clone(updated);
  }
  publishPrivate(draftId: string, owner: { user_id: UserId; device_id: DeviceId }): SkillVersionData {
    const current = this.getDraft(draftId, owner); if (current.status !== "tested") throw new W6Error("SKILL_TEST_REQUIRED", "A user-visible fixture must pass before private publish");
    const version = (this.versionNumbers.get(current.skill_id) ?? 0) + 1; const published = SkillVersion.parse({ version_id: id("sv"), skill_id: current.skill_id, version, owner_user_id: current.owner_user_id, definition: current.definition, contract_digest: skillDefinitionDigest(current.definition), visibility: "private", published_at: this.clock().toISOString(), source_draft_id: current.draft_id });
    try { assertSkillVersionImmutable(undefined, published); } catch (error) { throw policyError(error); }
    this.versionNumbers.set(current.skill_id, version); this.versions.set(published.version_id, clone(published)); this.drafts.set(draftId, clone({ ...current, status: "published", updated_at: this.clock().toISOString() })); return clone(published);
  }
  publishPublic(_draftId: string, _owner: { user_id: UserId; device_id: DeviceId }): never { try { assertPublicSkillPublishingDisabled(); } catch (error) { throw policyError(error, "PUBLIC_PUBLISH_DISABLED"); } }
  getDraft(draftId: string, owner?: { user_id: UserId; device_id: DeviceId }): SkillDraftData { const draft = this.drafts.get(draftId); if (!draft) throw new W6Error("DRAFT_NOT_FOUND", "Skill draft was not found"); if (owner && (draft.owner_user_id !== owner.user_id || draft.owner_device_id !== owner.device_id)) throw new W6Error("DRAFT_OWNER_MISMATCH", "Skill draft does not belong to this owner"); return clone(draft); }
  getVersion(versionId: string): SkillVersionData { const version = this.versions.get(versionId); if (!version) throw new W6Error("VERSION_NOT_FOUND", "Skill version was not found"); return clone(version); }
  sharePrivate(value: unknown, owner: UserId): PrivateSkillShareData { const parsed = PrivateSkillShare.safeParse(value); if (!parsed.success) throw new W6Error("INVALID_CONTRACT", "Private Skill share contract is invalid"); const existing = this.shares.get(parsed.data.share_id); if (existing) { if (JSON.stringify(existing) !== JSON.stringify(parsed.data)) throw new W6Error("SHARE_BINDING_MISMATCH", "Private share ID is immutable"); return clone(existing); } const version = this.getVersion(parsed.data.version_id); try { const share = clone(validatePrivateSkillShare(parsed.data, owner, version, this.clock())); this.shares.set(share.share_id, clone(share)); return share; } catch (error) { throw policyError(error, "SHARE_BINDING_MISMATCH"); } }
}

export class SkillBindingRegistry {
  private readonly bindings = new Map<string, SkillBindingData>();
  constructor(private readonly clock: Clock = nowDefault, private readonly reservedShortcuts = new Set(["space", "enter", "tab", "backspace", "shift"])) {}
  bind(value: unknown, version: SkillVersionData, owner: { user_id: UserId; device_id: DeviceId }): SkillBindingData {
    let binding: SkillBindingData; try { validateSkillVersion(version); binding = validateSkillBinding(value, version, owner); } catch (error) { throw policyError(error); }
    if (binding.trigger.kind === "shortcut" && this.reservedShortcuts.has(binding.trigger.value.toLowerCase())) throw new W6Error("TYPING_CONFLICT", "Skill shortcut conflicts with ordinary typing");
    const existingById = this.bindings.get(binding.binding_id); if (existingById) { if (JSON.stringify(existingById) !== JSON.stringify(binding)) throw new W6Error("BINDING_CONFLICT", "Existing Skill binding is immutable"); return clone(existingById); }
    for (const existing of this.bindings.values()) {
      if (existing.user_id === binding.user_id && existing.device_id === binding.device_id && existing.trigger.kind === binding.trigger.kind && existing.trigger.value.toLowerCase() === binding.trigger.value.toLowerCase()) throw new W6Error("BINDING_CONFLICT", "Skill trigger is already bound");
      if (existing.user_id === binding.user_id && existing.device_id === binding.device_id && existing.accessibility_order === binding.accessibility_order) throw new W6Error("ACCESSIBILITY_CONFLICT", "Accessibility order is already occupied");
      if (existing.user_id === binding.user_id && existing.device_id === binding.device_id && existing.accessibility_label === binding.accessibility_label) throw new W6Error("ACCESSIBILITY_CONFLICT", "Accessibility label is already in use");
    }
    const stored = SkillBinding.parse({ ...binding, bound_at: binding.bound_at || this.clock().toISOString() }); this.bindings.set(stored.binding_id, clone(stored)); return clone(stored);
  }
  get(bindingId: string, owner: { user_id: UserId; device_id: DeviceId }): SkillBindingData { const binding = this.bindings.get(bindingId); if (!binding) throw new W6Error("BINDING_CONFLICT", "Skill binding was not found"); if (binding.user_id !== owner.user_id || binding.device_id !== owner.device_id) throw new W6Error("BINDING_CONFLICT", "Skill binding belongs to another owner"); return clone(binding); }
  upgrade(bindingId: string, version: SkillVersionData, owner: { user_id: UserId; device_id: DeviceId }, explicit: boolean): SkillBindingData { if (!explicit) throw new W6Error("BINDING_CONFLICT", "Installed Skill versions cannot be silently upgraded"); const current = this.get(bindingId, owner); if (version.owner_user_id !== owner.user_id || version.skill_id !== current.skill_id) throw new W6Error("BINDING_VERSION_MISMATCH", "Upgrade must remain within the owner's Skill"); const updated = SkillBinding.parse({ ...current, version_id: version.version_id, skill_version: version.version, skill_digest: version.contract_digest, bound_at: this.clock().toISOString() }); try { validateSkillVersion(version); validateSkillBinding(updated, version, owner); } catch (error) { throw policyError(error, "BINDING_VERSION_MISMATCH"); } this.bindings.set(bindingId, clone(updated)); return clone(updated); }
}

export class QuotaLedger {
  private readonly reservations = new Map<string, SkillReservationData>();
  private readonly requestIndex = new Map<string, string>();
  private readonly usage = new Map<string, { user_id: UserId; period_start: string; runs: number; input_characters: number; output_characters: number; cost_micros: number }>();
  reserve(value: unknown, quota: SkillQuotaData, now = new Date()): SkillReservationData {
    const parsed = SkillReservation.safeParse(value); if (!parsed.success) throw new W6Error("INVALID_CONTRACT", "Quota reservation contract is invalid");
    const indexedId = this.requestIndex.get(parsed.data.request_id); const existing = indexedId ? this.reservations.get(indexedId) : undefined; if (existing) { const sameRequest = existing.user_id === parsed.data.user_id && existing.skill_id === parsed.data.skill_id && existing.skill_version === parsed.data.skill_version && existing.input_characters === parsed.data.input_characters && existing.estimated_output_characters === parsed.data.estimated_output_characters && existing.estimated_cost_micros === parsed.data.estimated_cost_micros && existing.period_start === quota.period_start && quota.user_id === parsed.data.user_id; if (!sameRequest) throw new W6Error("QUOTA_IDEMPOTENCY_CONFLICT", "Quota request key was reused with a different reservation"); return clone(existing); }
    if (this.reservations.has(parsed.data.request_id) || this.requestIndex.has(parsed.data.reservation_id)) throw new W6Error("QUOTA_IDEMPOTENCY_CONFLICT", "Reservation and request identifiers occupy separate unique namespaces");
    const key = `${quota.user_id}:${quota.period_start}`; const current: { user_id: UserId; period_start: string; runs: number; input_characters: number; output_characters: number; cost_micros: number } = this.usage.get(key) ?? { user_id: quota.user_id, period_start: quota.period_start, runs: 0, input_characters: 0, output_characters: 0, cost_micros: 0 };
    try { validateQuotaReservation(parsed.data, quota, current, now); } catch (error) { throw policyError(error, "QUOTA_EXCEEDED"); }
    const stored = SkillReservation.parse({ ...parsed.data, period_start: quota.period_start, status: "reserved" }); this.reservations.set(stored.reservation_id, clone(stored)); this.requestIndex.set(stored.request_id, stored.reservation_id); this.usage.set(key, { ...current, runs: current.runs + 1, input_characters: current.input_characters + stored.input_characters, output_characters: current.output_characters + stored.estimated_output_characters, cost_micros: current.cost_micros + stored.estimated_cost_micros }); return clone(stored);
  }
  commit(identifier: string, owner: UserId): SkillReservationData { const [key, reservation] = this.find(identifier); if (reservation.user_id !== owner) throw new W6Error("RESERVATION_OWNER_MISMATCH", "Quota reservation belongs to another user"); if (reservation.status === "committed") return clone(reservation); if (reservation.status !== "reserved") throw new W6Error("RESERVATION_STATE_CONFLICT", "Quota reservation is not committable"); const updated = SkillReservation.parse({ ...reservation, status: "committed" }); this.reservations.set(key, clone(updated)); return clone(updated); }
  release(identifier: string, owner: UserId): SkillReservationData { const [key, reservation] = this.find(identifier); if (reservation.user_id !== owner) throw new W6Error("RESERVATION_OWNER_MISMATCH", "Quota reservation belongs to another user"); if (reservation.status === "released") return clone(reservation); if (reservation.status !== "reserved") throw new W6Error("RESERVATION_STATE_CONFLICT", "Committed quota reservation cannot be released"); const usageKey = `${owner}:${reservation.period_start}`; const current = this.usage.get(usageKey); if (current) this.usage.set(usageKey, { ...current, runs: Math.max(0, current.runs - 1), input_characters: Math.max(0, current.input_characters - reservation.input_characters), output_characters: Math.max(0, current.output_characters - reservation.estimated_output_characters), cost_micros: Math.max(0, current.cost_micros - reservation.estimated_cost_micros) }); const updated = SkillReservation.parse({ ...reservation, status: "released" }); this.reservations.set(key, clone(updated)); return clone(updated); }
  private find(identifier: string): [string, SkillReservationData] { const direct = this.reservations.get(identifier); if (direct) return [identifier, direct]; const indexedId = this.requestIndex.get(identifier); const indexed = indexedId ? this.reservations.get(indexedId) : undefined; if (indexed && indexedId) return [indexedId, indexed]; throw new W6Error("RESERVATION_NOT_FOUND", "Quota reservation was not found"); }
}
