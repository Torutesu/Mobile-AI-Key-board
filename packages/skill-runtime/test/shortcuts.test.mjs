import test from 'node:test';
import assert from 'node:assert/strict';
import { LongPressStateMachine, idleLongPressState, reduceLongPress } from '../dist/index.js';

test('release before threshold commits the ordinary character exactly once', () => {
  let state = idleLongPressState();
  state = reduceLongPress(state, { type: 'down', at: 0, point: { x: 0, y: 0 } }).state;
  const result = reduceLongPress(state, { type: 'up', at: 449, point: { x: 0, y: 0 } });
  assert.equal(result.effect, 'commit_character');
  assert.equal(result.state.character_committed, true);
  assert.equal(reduceLongPress(result.state, { type: 'up', at: 500 }).effect, 'none');
});
test('threshold crossing activates once and suppresses character commit', () => {
  const down = reduceLongPress(idleLongPressState(), { type: 'down', at: 100, point: { x: 4, y: 4 } });
  const armed = reduceLongPress(down.state, { type: 'tick', at: 550 });
  assert.equal(armed.effect, 'activate');
  assert.equal(armed.state.activation_fired, true);
  assert.equal(reduceLongPress(armed.state, { type: 'tick', at: 600 }).effect, 'none');
  assert.equal(reduceLongPress(armed.state, { type: 'up', at: 610 }).effect, 'none');
});

test('movement, editor changes, multi-touch, and cancellation all fail closed', () => {
  const down = reduceLongPress(idleLongPressState(), { type: 'down', at: 0, point: { x: 0, y: 0 } });
  assert.equal(reduceLongPress(down.state, { type: 'move', at: 300, point: { x: 11, y: 0 } }).effect, 'cancel');
  assert.equal(reduceLongPress(down.state, { type: 'editor_changed', at: 100 }).effect, 'cancel');
  assert.equal(reduceLongPress(down.state, { type: 'multitouch', at: 100 }).effect, 'cancel');
});

test('wrapper exposes immutable state and permits a new pointer sequence after reset', () => {
  const machine = new LongPressStateMachine({ duration_ms: 450, cancellation_distance: 12 });
  machine.dispatch({ type: 'down', at: 0, point: { x: 1, y: 1 } });
  assert.equal(machine.dispatch({ type: 'up', at: 10 }).effect, 'commit_character');
  assert.equal(machine.reset().phase, 'idle');
  assert.equal(machine.dispatch({ type: 'down', at: 20, point: { x: 1, y: 1 } }).state.phase, 'pressing');
});
