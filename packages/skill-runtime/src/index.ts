import { createHash, randomUUID } from "node:crypto";
import type { ActionPlan, Disclosure, RunStatus } from "@mobile-ai-keyboard/contracts";
import { ActionPlan as ActionPlanSchema, canonicalJson, planDigest } from "@mobile-ai-keyboard/contracts";
import { assertPlanPolicy, PolicyViolation } from "@mobile-ai-keyboard/policy";

export class RuntimeError extends Error { constructor(readonly code: "INVALID_TRANSITION" | "DIGEST_MISMATCH" | "EXPIRED" | "OWNERSHIP_REQUIRED" | "VALIDATION_FAILED", message: string) { super(message); this.name = "RuntimeError"; } }
export const terminalStatuses = new Set<RunStatus>(["succeeded", "partial", "failed", "unknown", "cancelled", "expired"]);
const transitions: Record<RunStatus, readonly RunStatus[]> = {
  awaiting_input_disclosure: ["awaiting_input", "cancelled", "expired"], awaiting_input: ["planning", "cancelled", "expired"], planning: ["awaiting_review", "failed", "cancelled", "expired"],
  awaiting_review: ["awaiting_confirmation", "queued", "cancelled", "expired"], awaiting_confirmation: ["queued", "cancelled", "expired"], queued: ["executing", "cancelled", "expired"], executing: ["succeeded", "partial", "failed", "unknown"],
  succeeded: ["awaiting_review"], partial: ["awaiting_review"], failed: ["awaiting_review"], unknown: ["awaiting_review"], cancelled: [], expired: []
};

export class RunStateMachine {
  constructor(public status: RunStatus = "awaiting_input_disclosure") {}
  transition(next: RunStatus): void {
    if (!transitions[this.status].includes(next)) throw new RuntimeError("INVALID_TRANSITION", `Cannot transition ${this.status} to ${next}`);
    this.status = next;
  }
  cancel(): void { if (!terminalStatuses.has(this.status)) this.transition("cancelled"); }
}

export type JapaneseDateResolution = { start: string; end?: string; timezone: string; source: string; requiresConfirmation: boolean };
const weekdays: Record<string, number> = { 日: 0, 月: 1, 火: 2, 水: 3, 木: 4, 金: 5, 土: 6 };

/** Resolve only unambiguous Japanese relative dates against an explicit local clock. */
export function parseJapaneseRelativeDate(input: string, now: Date, timezone: string): JapaneseDateResolution | null {
  const match = input.match(/(今日|明日|明後日|来週)?\s*(月|火|水|木|金|土|日)?曜?(?:日)?\s*(\d{1,2})時(?:から(\d{1,3})分)?/u);
  if (!match) return null;
  const [, relative, weekdayText, hourText, durationText] = match;
  if (hourText === undefined) return null;
  const localParts = new Intl.DateTimeFormat("en-CA", { timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(now);
  const part = (name: string): number => Number(localParts.find((entry) => entry.type === name)?.value ?? NaN);
  const year = part("year"); const month = part("month"); const day = part("day"); const hour = part("hour");
  const current = new Date(Date.UTC(year, month - 1, day, hour, part("minute")));
  const currentDay = current.getUTCDay();
  const targetDay = weekdayText ? weekdays[weekdayText] : undefined;
  const mondayIndex = (currentDay + 6) % 7;
  const targetMondayIndex = targetDay === undefined ? mondayIndex : (targetDay + 6) % 7;
  const relativeDelta = relative === "今日" ? 0 : relative === "明日" ? 1 : relative === "明後日" ? 2 : undefined;
  const delta = relativeDelta ?? (relative === "来週" && targetDay !== undefined ? (7 - mondayIndex) + targetMondayIndex : targetDay === undefined ? 0 : (targetDay - currentDay + 7) % 7);
  if (!relative && delta === 0 && hour >= Number(hourText)) return null;
  const date = new Date(Date.UTC(year, month - 1, day + delta, Number(hourText), 0));
  const duration = durationText ? Number(durationText) : 30;
  const end = new Date(date.getTime() + duration * 60_000);
  const offsetParts = new Intl.DateTimeFormat("en-US", { timeZone: timezone, timeZoneName: "longOffset" }).formatToParts(now);
  const offset = offsetParts.find((entry) => entry.type === "timeZoneName")?.value?.replace("GMT", "") || "+00:00";
  const withOffset = (value: Date): string => `${value.toISOString().slice(0, 19)}${offset}`;
  return { start: withOffset(date), end: withOffset(end), timezone, source: input, requiresConfirmation: true };
}

export function createDisclosure(available: Disclosure["accepted_sources"], destinations: string[]): Disclosure {
  const all = ["command", "selection", "surrounding_text", "clipboard", "current_datetime", "locale", "location"] as const;
  const accepted = all.filter((source) => available.includes(source));
  return { accepted_sources: accepted, rejected_sources: all.filter((source) => !accepted.includes(source)), max_characters: { command: 500, selection: 4000, surrounding_text: 1500, clipboard: 4000 }, destinations, retention_class: "transient_content", external_access: [] };
}

export function disclosureDigest(disclosure: Disclosure): string { return `sha256:${createHash("sha256").update(canonicalJson(disclosure)).digest("hex")}`; }

export function validateAndBindPlan(plan: ActionPlan, riskCeiling = "R3" as const): ActionPlan {
  const parsed = ActionPlanSchema.parse(plan);
  const withoutDigest = { ...parsed } as Omit<ActionPlan, "canonical_digest">;
  delete (withoutDigest as Partial<ActionPlan>).canonical_digest;
  if (planDigest(withoutDigest) !== parsed.canonical_digest) throw new RuntimeError("DIGEST_MISMATCH", "Action plan digest does not match canonical representation");
  try { assertPlanPolicy(parsed, riskCeiling); } catch (error) { if (error instanceof PolicyViolation) throw new RuntimeError("VALIDATION_FAILED", error.message); throw error; }
  return parsed;
}

export function newId(prefix: string): string { return `${prefix}_${randomUUID()}`; }
