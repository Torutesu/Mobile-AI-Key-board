#!/usr/bin/env node

/**
 * Source/integration contract for the Builder -> keyboard Skill Key journey.
 *
 * This is deliberately a source gate, not a runtime or device test.  It proves
 * that the two native implementations expose the required authority and
 * safety seams, and reports missing UI/runtime wiring as `not_proven` rather
 * than silently treating a fixture as a product capability.  `--strict` is
 * intended for a release lane and fails until every seam is present.
 */
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIGEST = 'sha256:';

const platformContracts = {
  ios: [
    {
      id: 'builder_immutable_skill_identity',
      purpose: 'Builder creates a version carrying stable Skill identity and digest.',
      required: [
        ['apps/ios/Sources/MobileAIKeyboardCore/SkillBuilderModels.swift', ['PrivateSkillVersion', 'versionNumber', 'digest', 'SkillBuilderReducer']],
        ['apps/ios/Sources/MobileAIKeyboardCore/SkillBuilderModels.swift', ['skillID', 'confirmDeploy', 'pendingDeploymentDigest']],
      ],
      ordered: [['case .deployPrivateV1', 'case .confirmDeploy', 'let version = PrivateSkillVersion']],
    },
    {
      id: 'builder_deploy_requires_exact_confirmation',
      purpose: 'Deploy cannot be confirmed with a changed digest or stale draft.',
      required: [
        ['apps/ios/Sources/MobileAIKeyboardCore/SkillBuilderModels.swift', ['case confirmDeploy(digest:', 'pendingDigest == digest', 'status = .deployed']],
        ['apps/ios/MobileAIKeyboardHost/SkillBuilderView.swift', ['private v1 deploy review', 'confirmDeploy(digest: digest']],
      ],
    },
    {
      id: 'explicit_add_separates_deploy_and_assignment',
      purpose: 'Successful deploy offers a separately confirmed Add To My Keyboard action.',
      required: [
        // The Builder owns the explicit install affordance, while the host
        // registry and Skill Keys screen own candidate admission and A-Z
        // assignment.  Keeping these as separate source requirements avoids
        // mistaking a Builder deploy/pin for keyboard installation.
        ['apps/ios/MobileAIKeyboardHost/SkillBuilderView.swift', ['Button("Add To My Keyboard")', 'shortcutRegistry.addPrivateSkill(version)', 'selectedSkill = createdSkill']],
        ['apps/ios/MobileAIKeyboardHost/ShortcutRegistryStore.swift', ['func addPrivateSkill(_ version:', 'route: .keyboardLocal', 'A–Zキーを割り当ててください']],
        ['apps/ios/MobileAIKeyboardHost/SkillKeysView.swift', ['registry.assign(skillID: skill.id, key: selectedKey)', 'registry.reassign']],
      ],
    },
    {
      id: 'az_assignment_publishes_snapshot',
      purpose: 'Host owns A-Z assignment and publishes one validated snapshot.',
      required: [
        ['apps/ios/Sources/MobileAIKeyboardCore/ShortcutModels.swift', ['ShortcutKeyCode', 'keyA', 'keyZ']],
        ['apps/ios/MobileAIKeyboardHost/ShortcutRegistryStore.swift', ['func assign', 'ShortcutRegistryMutation.assign', 'try publish(', 'revision: snapshot.layout.revision + 1']],
      ],
    },
    {
      id: 'closed_local_executor_binds_exact_identity',
      purpose: 'IME executes only keyboard-local Skills after exact identity checks and review.',
      required: [
        ['apps/ios/MobileAIKeyboardExtension/KeyboardViewController.swift', ['executionRoute == .keyboardLocal', 'snapshot.generation == shortcutSnapshot?.generation', '$0.id == binding.id && $0.skillID == binding.skillID && $0.versionID == binding.versionID', '$0.skillDigest == binding.skillDigest', '$0.id == skill.id && $0.versionID == skill.versionID && $0.skillDigest == skill.skillDigest', 'showCaptureReview']],
        ['apps/ios/Sources/MobileAIKeyboardCore/ShortcutModels.swift', ['skill.skillDigest == binding.skillDigest, skill.skillVersion == binding.skillVersion']],
      ],
    },
    {
      id: 'restart_persistence_has_last_known_good',
      purpose: 'Host and extension read a validated last-known-good snapshot after restart.',
      required: [
        ['apps/ios/Sources/MobileAIKeyboardCore/ShortcutModels.swift', ['class AppGroupShortcutSnapshotStore', 'loadLastKnownGood', 'func publish(']],
        ['apps/ios/MobileAIKeyboardExtension/KeyboardViewController.swift', ['refreshShortcutSnapshot', 'loadLastKnownGood']],
        ['apps/ios/MobileAIKeyboardHost/ShortcutRegistryStore.swift', ['init(storage:', 'loadLastKnownGood']],
      ],
    },
    {
      id: 'accessible_non_hold_palette',
      purpose: 'Every assigned Skill has a visible non-hold action that enters the exact reviewed activation path.',
      required: [
        ['apps/ios/MobileAIKeyboardExtension/KeyboardViewController.swift', ['accessibilityIdentifier = "skill-palette"', '@objc private func showSkillPalette()', 'self?.invokeShortcut(skill, binding: binding)', 'UIAccessibility.post(notification: .screenChanged']],
      ],
    },
  ],
  android: [
    {
      id: 'builder_immutable_skill_identity',
      purpose: 'Builder creates a version carrying stable Skill identity and digest.',
      required: [
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/core/SkillBuilderModels.kt', ['data class PrivateSkillVersion', 'version: Int', 'digest: String', 'skillId: String']],
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/core/SkillBuilderModels.kt', ['ConfirmDeploy', 'confirmedDigest', 'published']],
      ],
    },
    {
      id: 'builder_deploy_requires_exact_confirmation',
      purpose: 'Deploy cannot be confirmed with a changed digest or stale draft.',
      required: [
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/core/SkillBuilderModels.kt', ['is SkillBuilderEvent.ConfirmDeploy', 'event.digest == version.digest', 'phase = SkillBuilderPhase.DEPLOYED']],
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/ui/SkillBuilderScreen.kt', ['DEPLOY_REVIEW', 'ConfirmDeploy(builder.version!!.digest)']],
      ],
    },
    {
      id: 'explicit_add_separates_deploy_and_assignment',
      purpose: 'Successful deploy offers a separately confirmed Add To My Keyboard action.',
      required: [
        // Android deliberately routes the Builder callback through the
        // persistent installed-skill catalog; ShortcutKeys publishes the
        // separate physical-key snapshot.  These are independent seams.
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/ui/SkillBuilderScreen.kt', ['Text("Add To My Keyboard")', 'onAddToMyKeyboard', 'UpgradeBinding']],
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/ui/MainActivity.kt', ['InstalledSkillStore', 'installedSkillStore.install(version)', 'onAddToMyKeyboard =']],
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/core/LocalSkillCatalog.kt', ['class InstalledSkillStore', 'fun install(version: PrivateSkillVersion)', 'LocalSkillRegistry.install']],
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/ui/ShortcutKeysScreen.kt', ['ShortcutRegistry.add', 'ShortcutRegistry.reassign', 'onPublish']],
      ],
    },
    {
      id: 'az_assignment_publishes_snapshot',
      purpose: 'Host owns A-Z assignment and publishes one validated snapshot.',
      required: [
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/core/ShortcutModels.kt', ['enum class ShortcutKeyCode', 'A("KeyA")', 'Z("KeyZ")']],
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/ui/ShortcutKeysScreen.kt', ['ShortcutRegistry.add', 'ShortcutRegistry.reassign', 'onPublish']],
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/core/ShortcutModels.kt', ['class ShortcutSnapshotStore', 'fun publish(candidate:', 'ShortcutSnapshotValidator.validate']],
      ],
    },
    {
      id: 'closed_local_executor_binds_exact_identity',
      purpose: 'IME executes only closed local Skills after exact identity checks and review.',
      required: [
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/ime/KeyboardImeService.kt', ['ExecutableLocalSkills.isExecutable(binding)', 'it.bindingId == binding.bindingId && it.keyCode == binding.keyCode && it.skillDigest == binding.skillDigest', 'skillVersion = exact.skillVersion', 'Capture Review']],
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/core/ShortcutModels.kt', ['object ExecutableLocalSkills', 'fun isExecutable(binding:', 'skill_not_executable_on_ime']],
      ],
    },
    {
      id: 'restart_persistence_has_local_snapshot',
      purpose: 'Host and IME read a validated local snapshot after process restart.',
      required: [
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/core/ShortcutModels.kt', ['class ShortcutSnapshotStore', 'getSharedPreferences', 'fun read(): ShortcutSnapshot', 'fun publish(candidate:']],
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/ime/KeyboardImeService.kt', ['override fun onCreate()', 'shortcutStore.read()', 'override fun onStartInput']],
      ],
    },
    {
      id: 'accessible_non_hold_palette',
      purpose: 'Every assigned Skill has a visible non-hold action that enters the exact reviewed activation path.',
      required: [
        ['apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/ime/KeyboardSurface.kt', ['"Skill一覧を開く、${activeBindings.size}件"', 'private fun renderSkillPalette', 'callbacks.onShortcut(binding)', 'announceStatus("Skill一覧。']],
        ['apps/android/app/src/androidTest/java/com/torutesu/mobileaikeyboard/VerticalSliceUiTest.kt', ['physicalTapAccessibleLongClickAndVisiblePaletteRemainDistinctActions', 'Skill一覧を開く、1件']],
      ],
    },
  ],
};

const disclosureContracts = [
  ['docs/08-implementation-status.md', ['native_consumption_status', 'native_unit_consumers', 'runtime interoperability', 'remain `not_proven`']],
  ['docs/20-shortcut-runtime-architecture.md', ['custom keyboard shortcuts', 'host-to-keyboard sync', 'persistence across restart', 'must remain `not_proven`']],
];

function read(relativePath) {
  const file = path.resolve(ROOT, relativePath);
  if (!fs.existsSync(file)) return { file, text: null };
  return { file, text: fs.readFileSync(file, 'utf8') };
}

function lineFor(text, needle) {
  if (!text) return null;
  const lines = text.split('\n');
  const index = lines.findIndex((line) => line.includes(needle));
  return index < 0 ? null : index + 1;
}

function inspectRequirement(requirement) {
  const [relativePath, needles] = requirement;
  const { file, text } = read(relativePath);
  const missing = needles.filter((needle) => !text?.includes(needle));
  return {
    path: path.relative(ROOT, file),
    present: missing.length === 0,
    missing,
    anchors: needles.filter((needle) => text?.includes(needle)).map((needle) => ({ needle, line: lineFor(text, needle) })),
  };
}

function inspectContract(contract) {
  const requirements = contract.required.map(inspectRequirement);
  const ordered = (contract.ordered ?? []).map((needles) => {
    const [relativePath] = contract.required.find(([candidatePath]) => candidatePath) ?? [];
    const { text } = read(relativePath);
    const positions = needles.map((needle) => text?.indexOf(needle) ?? -1);
    return { path: relativePath, present: positions.every((position) => position >= 0) && positions.every((position, index) => index === 0 || position > positions[index - 1]), needles, positions };
  });
  const missing = requirements.flatMap((result) => result.missing.map((needle) => `${result.path}: ${needle}`));
  const orderFailures = ordered.filter((result) => !result.present).map((result) => `${result.path}: required source order ${result.needles.join(' -> ')}`);
  const complete = missing.length === 0 && orderFailures.length === 0;
  return {
    id: contract.id,
    purpose: contract.purpose,
    status: complete ? 'passed' : (contract.missingIsNotProven ? 'not_proven' : 'not_proven'),
    missing: [...missing, ...orderFailures],
    requirements,
    ordered,
  };
}

function inspectDisclosures() {
  return disclosureContracts.map(([relativePath, needles]) => {
    const { file, text } = read(relativePath);
    const missing = needles.filter((needle) => !text?.includes(needle));
    return {
      id: `disclosure.${path.basename(relativePath, path.extname(relativePath))}`,
      path: path.relative(ROOT, file),
      status: missing.length === 0 ? 'passed' : 'fail',
      missing,
      anchors: needles.filter((needle) => text?.includes(needle)).map((needle) => ({ needle, line: lineFor(text, needle) })),
    };
  });
}

export function inspectVerticalSlice(root = ROOT) {
  // Keep the exported function root-aware for adversarial tests.  The source
  // reader is intentionally scoped to the repository root, never to arbitrary
  // caller-provided content.
  if (root !== ROOT) throw new Error('vertical-slice inspection must run against the repository root');
  const platforms = Object.fromEntries(Object.entries(platformContracts).map(([platform, contracts]) => [platform, contracts.map(inspectContract)]));
  const disclosures = inspectDisclosures();
  const checks = [...Object.values(platforms).flat(), ...disclosures];
  const hasFailure = checks.some((check) => check.status === 'fail');
  const hasNotProven = checks.some((check) => check.status === 'not_proven');
  return {
    schema_version: 'mobile-ai-keyboard.shortcut-vertical-slice.v1',
    evidence_class: 'static_source_contract',
    digest_binding: DIGEST,
    status: hasFailure ? 'fail' : (hasNotProven ? 'not_proven' : 'passed'),
    qualification_status: 'not_proven',
    claim_boundary: 'Source seams only. This report never proves device, process-restart, keyboard registration, third-party app, or runtime execution behavior.',
    journey: ['builder_deploy', 'explicit_add_to_my_keyboard', 'az_assign', 'native_snapshot_store', 'closed_ime_execution', 'restart_reload'],
    platforms,
    disclosures,
  };
}

function main() {
  const strict = process.argv.includes('--strict');
  const report = inspectVerticalSlice();
  const output = `${JSON.stringify(report, null, 2)}\n`;
  const reportIndex = process.argv.indexOf('--report');
  if (reportIndex >= 0 && process.argv[reportIndex + 1]) {
    const target = path.resolve(process.argv[reportIndex + 1]);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, output);
  }
  console.log(output.trimEnd());
  if (report.status === 'fail' || (strict && report.status !== 'passed')) process.exitCode = 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
