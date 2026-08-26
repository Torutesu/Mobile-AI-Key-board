import { SkillDefinition, SkillDraft, SkillBinding, SkillQuota, SkillReservation, SkillVersion, PrivateSkillShare, SkillTestRun, skillDefinitionDigest, skillTestFixtureDigest } from "@mobile-ai-keyboard/contracts";
import type { SkillDefinition as SkillDefinitionData, SkillDraft as SkillDraftData, SkillBinding as SkillBindingData, SkillQuota as SkillQuotaData, SkillReservation as SkillReservationData, SkillVersion as SkillVersionData, PrivateSkillShare as PrivateSkillShareData, SkillTestRun as SkillTestRunData, UserId, DeviceId } from "@mobile-ai-keyboard/contracts";
import { PolicyViolation } from "./index.js";

const allowedToolScopes: Record<string, readonly string[]> = {
  "calendar.availability.read": ["calendar.availability.read"],
  "notion.pages.search": ["notion.pages.search"],
  "maps.places.search": ["maps.places.search"],
  "calendar.event.create_private": ["calendar.events.create_private"]
};
const allowedToolEffects: Record<string, SkillToolEffect> = {
  "calendar.availability.read": "none",
  "notion.pages.search": "none",
  "maps.places.search": "none",
  "calendar.event.create_private": "creates_private_event"
};
type SkillToolEffect = "none" | "creates_private_event";
const toolRisk: Record<string, "R0" | "R2" | "R3"> = { "calendar.availability.read": "R2", "notion.pages.search": "R2", "maps.places.search": "R2", "calendar.event.create_private": "R3" };
const rank = { R0: 0, R1: 1, R2: 2, R3: 3 } as const;
const injectionPattern = /(ignore\s+(?:all\s+)?(?:previous|prior|system)|system\s+prompt|developer\s+message|exfiltrat|send\s+.*(?:secret|token|password)|reveal\s+.*(?:secret|prompt)|disable\s+safety|bypass\s+(?:policy|approval)|(?:以前|前の|システム)の?(?:指示|命令).*(?:無視|忘れ)|システムプロンプト|秘密|トークン.*送信|安全策.*無効)/iu;

function scanString(value: string, path: string): void { if (injectionPattern.test(value)) throw new PolicyViolation("Skill contains a prompt-injection marker", { code: "STATIC_INJECTION", path }); }
function scanUnknown(value: unknown, path: string): void { if (typeof value === "string") scanString(value, path); else if (Array.isArray(value)) value.forEach((item, index) => scanUnknown(item, `${path}[${index}]`)); else if (value && typeof value === "object") Object.entries(value).forEach(([key, child]) => scanUnknown(child, `${path}.${key}`)); }

export function validateSkillDefinition(value: unknown): SkillDefinitionData {
  const parsed = SkillDefinition.safeParse(value); if (!parsed.success) throw new PolicyViolation("Skill definition contract is invalid", { code: "INVALID_SKILL_SCHEMA" });
  if (parsed.data.tests.length < 1) throw new PolicyViolation("Skill requires at least one user-visible test example", { code: "MISSING_SKILL_TEST" });
  const inputNames = new Set<string>(); for (const input of parsed.data.inputs) { if (inputNames.has(input.name)) throw new PolicyViolation("Skill input names must be unique", { code: "INVALID_SKILL_SCHEMA" }); inputNames.add(input.name); const sources = new Set(input.sources); if (sources.size !== input.sources.length) throw new PolicyViolation("Skill input sources must be unique", { code: "INVALID_SKILL_SCHEMA" }); }
  const testNames = new Set<string>(); for (const fixture of parsed.data.tests) { if (testNames.has(fixture.name)) throw new PolicyViolation("Skill fixture test names must be unique", { code: "INVALID_SKILL_SCHEMA" }); testNames.add(fixture.name); }
  let highest: keyof typeof rank = "R0";
  for (const [index, tool] of parsed.data.tools.entries()) {
    const required = allowedToolScopes[tool.operation]; if (!required || tool.required_scopes.length !== required.length || tool.required_scopes.some((scope) => !required.includes(scope)) || allowedToolEffects[tool.operation] !== tool.side_effect) throw new PolicyViolation("Skill tool is outside the fixed operation-to-scope/effect allowlist", { code: "TOOL_SCOPE_MISMATCH", path: `tools[${index}]` });
    const expectedRisk = toolRisk[tool.operation]; if (expectedRisk === undefined) throw new PolicyViolation("Skill tool has no fixed risk authority", { code: "PROHIBITED_SKILL_TOOL", operation: tool.operation }); if (rank[expectedRisk] > rank[highest]) highest = expectedRisk;
  }
  if (rank[parsed.data.risk_ceiling] < rank[highest]) throw new PolicyViolation("Skill risk ceiling is below its tool authority", { code: "RISK_CEILING_MISMATCH" });
  if (highest !== "R0" && parsed.data.confirmation !== "policy_required") throw new PolicyViolation("External read/write Skills require policy confirmation", { code: "CONFIRMATION_REQUIRED" });
  scanString(parsed.data.name, "name"); scanString(parsed.data.description, "description"); scanString(parsed.data.instruction, "instruction"); scanUnknown(parsed.data.trigger, "trigger"); scanUnknown(parsed.data.output, "output"); parsed.data.tests.forEach((example, index) => scanUnknown(example, `tests[${index}]`));
  return parsed.data;
}

export function validateSkillDraft(value: unknown, expectedOwner?: { user_id: UserId; device_id: DeviceId }): SkillDraftData {
  const parsed = SkillDraft.safeParse(value); if (!parsed.success) throw new PolicyViolation("Skill draft contract is invalid", { code: "INVALID_SKILL_DRAFT" });
  if (expectedOwner && (parsed.data.owner_user_id !== expectedOwner.user_id || parsed.data.owner_device_id !== expectedOwner.device_id)) throw new PolicyViolation("Skill draft is not owned by the authenticated device", { code: "SKILL_OWNER_MISMATCH" });
  if (skillDefinitionDigest(parsed.data.definition) !== parsed.data.contract_digest) throw new PolicyViolation("Skill draft digest does not match its immutable definition", { code: "SKILL_DIGEST_MISMATCH" });
  validateSkillDefinition(parsed.data.definition); return parsed.data;
}

export function validateSkillTestRun(value: unknown, draft: SkillDraftData, now = new Date()): SkillTestRunData {
  const parsed = SkillTestRun.safeParse(value); if (!parsed.success) throw new PolicyViolation("Skill test run contract is invalid", { code: "INVALID_SKILL_TEST_RUN" });
  if (parsed.data.draft_id !== draft.draft_id || parsed.data.draft_revision !== draft.revision || parsed.data.contract_digest !== draft.contract_digest || parsed.data.all_pass !== true) throw new PolicyViolation("Skill test run is stale or not bound to the current draft", { code: "SKILL_TEST_BINDING_MISMATCH" });
  if (Date.parse(parsed.data.completed_at) > now.getTime()) throw new PolicyViolation("Skill test run cannot be from the future", { code: "INVALID_SKILL_TEST_RUN" });
  const expected = new Map(draft.definition.tests.map((test) => [test.name, test])); const seen = new Set<string>();
  if (parsed.data.results.length !== expected.size) throw new PolicyViolation("Skill test run must cover every expected fixture exactly once", { code: "SKILL_TEST_COVERAGE" });
  for (const result of parsed.data.results) { const fixture = expected.get(result.test_name); if (!fixture || seen.has(result.test_name) || result.fixture_digest !== skillTestFixtureDigest(fixture) || result.user_visible_result.trim().length === 0) throw new PolicyViolation("Skill test result is missing, stale, or not user-visible", { code: "SKILL_TEST_RESULT_INVALID" }); for (const [key, expectedValue] of Object.entries(fixture.expected)) { if (!(key in result.actual) || JSON.stringify(result.actual[key as keyof typeof result.actual]) !== JSON.stringify(expectedValue)) throw new PolicyViolation("Skill test actual does not match its expected typed fixture", { code: "SKILL_TEST_EXPECTATION_MISMATCH", test_name: result.test_name, field: key }); } seen.add(result.test_name); }
  return parsed.data;
}

export function assertSkillVersionImmutable(previous: SkillVersionData | undefined, next: SkillVersionData): SkillVersionData {
  if (previous && JSON.stringify(previous) !== JSON.stringify(next)) throw new PolicyViolation("Published Skill versions are immutable", { code: "IMMUTABLE_VERSION_CONFLICT" });
  const parsed = SkillVersion.parse(next); validateSkillDefinition(parsed.definition); if (skillDefinitionDigest(parsed.definition) !== parsed.contract_digest) throw new PolicyViolation("Skill version digest mismatch", { code: "SKILL_DIGEST_MISMATCH" }); if (parsed.visibility !== "private") throw new PolicyViolation("Public Skill publishing is disabled", { code: "PUBLIC_PUBLISH_DISABLED" }); return parsed;
}
export function validateSkillVersion(value: unknown): SkillVersionData {
  const parsed = SkillVersion.safeParse(value); if (!parsed.success) throw new PolicyViolation("Skill version contract is invalid", { code: "INVALID_SKILL_VERSION" });
  validateSkillDefinition(parsed.data.definition); if (skillDefinitionDigest(parsed.data.definition) !== parsed.data.contract_digest) throw new PolicyViolation("Skill version digest mismatch", { code: "SKILL_DIGEST_MISMATCH" }); if (parsed.data.visibility !== "private") throw new PolicyViolation("Public Skill publishing is disabled", { code: "PUBLIC_PUBLISH_DISABLED" }); return parsed.data;
}

export function validatePrivateSkillShare(value: unknown, owner: UserId, version: SkillVersionData, now = new Date()): PrivateSkillShareData {
  const parsed = PrivateSkillShare.safeParse(value); if (!parsed.success) throw new PolicyViolation("Private Skill share contract is invalid", { code: "INVALID_PRIVATE_SHARE" });
  if (parsed.data.owner_user_id !== owner || version.owner_user_id !== owner || parsed.data.skill_id !== version.skill_id || parsed.data.version_id !== version.version_id || parsed.data.skill_digest !== version.contract_digest || parsed.data.visibility !== "private" || parsed.data.public_publish !== false || (parsed.data.expires_at !== undefined && Date.parse(parsed.data.expires_at) <= now.getTime())) throw new PolicyViolation("Private share is not bound to a live immutable version", { code: "SHARE_BINDING_MISMATCH" });
  if (parsed.data.recipient_user_ids.includes(owner)) throw new PolicyViolation("Skill owner cannot be a private-share recipient", { code: "SHARE_RECIPIENT_INVALID" });
  return parsed.data;
}

export function validateSkillBinding(value: unknown, version: SkillVersionData, owner: { user_id: UserId; device_id: DeviceId }): SkillBindingData {
  const parsed = SkillBinding.safeParse(value); if (!parsed.success) throw new PolicyViolation("Skill binding contract is invalid", { code: "INVALID_SKILL_BINDING" });
  if (parsed.data.user_id !== owner.user_id || parsed.data.device_id !== owner.device_id || version.owner_user_id !== owner.user_id || parsed.data.skill_id !== version.skill_id || parsed.data.version_id !== version.version_id || parsed.data.skill_version !== version.version || parsed.data.skill_digest !== version.contract_digest) throw new PolicyViolation("Skill binding does not match the immutable installed version", { code: "BINDING_VERSION_MISMATCH" });
  return parsed.data;
}

export function validateQuotaReservation(value: unknown, quota: SkillQuotaData, usage: { user_id: UserId; period_start: string; runs: number; input_characters: number; output_characters: number; cost_micros: number }, now = new Date()): SkillReservationData {
  const parsed = SkillReservation.safeParse(value); if (!parsed.success) throw new PolicyViolation("Quota reservation contract is invalid", { code: "INVALID_QUOTA_RESERVATION" });
  if (parsed.data.user_id !== quota.user_id || parsed.data.period_start !== quota.period_start || usage.user_id !== quota.user_id || usage.period_start !== quota.period_start || parsed.data.status !== "reserved" || Date.parse(quota.period_start) > now.getTime() || Date.parse(quota.period_end) <= now.getTime() || Date.parse(parsed.data.reserved_at) < Date.parse(quota.period_start) || Date.parse(parsed.data.reserved_at) > now.getTime()) throw new PolicyViolation("Quota period or reservation owner is invalid", { code: "QUOTA_PERIOD_INVALID" });
  if (usage.runs + 1 > quota.max_runs || usage.input_characters + parsed.data.input_characters > quota.max_input_characters || usage.output_characters + parsed.data.estimated_output_characters > quota.max_output_characters || usage.cost_micros + parsed.data.estimated_cost_micros > quota.max_cost_micros) throw new PolicyViolation("Skill usage or cost quota would be exceeded", { code: "QUOTA_EXCEEDED" });
  return parsed.data;
}

export function assertPublicSkillPublishingDisabled(): never { throw new PolicyViolation("Public Skill publishing is disabled until moderation, reporting, signatures, and rollback exist", { code: "PUBLIC_PUBLISH_DISABLED" }); }
