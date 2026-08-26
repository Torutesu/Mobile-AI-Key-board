/** Pure, platform-neutral long-press recognizer. It never reads input, disk, or network. */
export const DEFAULT_LONG_PRESS_DURATION_MS = 450;
export const DEFAULT_CANCELLATION_DISTANCE = 10;

export type LongPressPhase = "idle" | "pressing" | "armed" | "cancelled" | "completed";
export type LongPressEffect = "none" | "commit_character" | "activate" | "cancel";
export type LongPressPoint = { x: number; y: number };
export type LongPressState = {
  phase: LongPressPhase;
  started_at: number | null;
  origin: LongPressPoint | null;
  activation_fired: boolean;
  character_committed: boolean;
};
export type LongPressEvent =
  | { type: "down"; at: number; point: LongPressPoint }
  | { type: "move"; at: number; point: LongPressPoint }
  | { type: "tick"; at: number }
  | { type: "up"; at: number; point?: LongPressPoint }
  | { type: "cancel" | "editor_changed" | "snapshot_changed" | "multitouch"; at: number };
export type LongPressOptions = { duration_ms?: number; cancellation_distance?: number };
export type LongPressTransition = { state: LongPressState; effect: LongPressEffect };

export const idleLongPressState = (): LongPressState => ({ phase: "idle", started_at: null, origin: null, activation_fired: false, character_committed: false });
const distance = (a: LongPressPoint, b: LongPressPoint): number => Math.hypot(a.x - b.x, a.y - b.y);
const terminal = (state: LongPressState, effect: LongPressEffect): LongPressTransition => ({ state, effect });
const cancelled = (): LongPressTransition => terminal({ phase: "cancelled", started_at: null, origin: null, activation_fired: false, character_committed: false }, "cancel");

/**
 * Reduce one pointer event. A threshold crossing emits `activate` exactly once;
 * a release before it emits `commit_character` exactly once. The returned state
 * is a new value and the input state/event are never mutated.
 */
export function reduceLongPress(state: LongPressState, event: LongPressEvent, options: LongPressOptions = {}): LongPressTransition {
  const duration = options.duration_ms ?? DEFAULT_LONG_PRESS_DURATION_MS;
  const cancellationDistance = options.cancellation_distance ?? DEFAULT_CANCELLATION_DISTANCE;
  if (!Number.isFinite(duration) || duration <= 0 || !Number.isFinite(cancellationDistance) || cancellationDistance < 0) throw new RangeError("Long-press thresholds must be finite and positive");
  if (!Number.isFinite(event.at)) throw new RangeError("Long-press event time must be finite");
  const eventPoint = "point" in event ? event.point : undefined;
  if (eventPoint !== undefined && (!Number.isFinite(eventPoint.x) || !Number.isFinite(eventPoint.y))) throw new RangeError("Long-press pointer coordinates must be finite");
  if (event.type === "down") {
    if (state.phase === "pressing" || state.phase === "armed") return cancelled();
    return terminal({ phase: "pressing", started_at: event.at, origin: { ...event.point }, activation_fired: false, character_committed: false }, "none");
  }
  if (state.phase === "idle" || state.phase === "cancelled" || state.phase === "completed") return terminal(state, "none");
  if (event.type === "cancel" || event.type === "editor_changed" || event.type === "snapshot_changed" || event.type === "multitouch") return cancelled();
  if ((event.type === "move" || event.type === "up") && state.origin && event.point && distance(state.origin, event.point) > cancellationDistance) return cancelled();
  const started = state.started_at ?? event.at;
  const crossed = event.at - started >= duration;
  if (state.phase === "pressing" && crossed) {
    const armed: LongPressState = { ...state, phase: "armed", activation_fired: true };
    if (event.type === "up") return terminal({ ...armed, phase: "completed" }, "activate");
    return terminal(armed, "activate");
  }
  if (event.type === "up" && state.phase === "pressing") return terminal({ ...state, phase: "completed", character_committed: true }, "commit_character");
  if (state.phase === "armed" && event.type === "up") return terminal({ ...state, phase: "completed" }, "none");
  return terminal({ ...state }, "none");
}

export const handleLongPressEvent = reduceLongPress;

/** Small convenience wrapper for native adapters; transition logic remains pure above. */
export class LongPressStateMachine {
  private state: LongPressState = idleLongPressState();
  constructor(private readonly options: LongPressOptions = {}) {}
  get current(): LongPressState { return { ...this.state, origin: this.state.origin ? { ...this.state.origin } : null }; }
  dispatch(event: LongPressEvent): LongPressTransition { const transition = reduceLongPress(this.state, event, this.options); this.state = transition.state; return { state: this.current, effect: transition.effect }; }
  reset(): LongPressState { this.state = idleLongPressState(); return this.current; }
}
