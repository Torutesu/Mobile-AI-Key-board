import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import test from 'node:test';

const archiveScript = fs.readFileSync('apps/ios/scripts/archive-testflight.sh', 'utf8');
const project = fs.readFileSync('apps/ios/project.yml', 'utf8');
const workflow = fs.readFileSync('.github/workflows/ios-testflight.yml', 'utf8');
const profileValidator = fs.readFileSync('apps/ios/scripts/validate-provisioning-profile.sh', 'utf8');

test('TestFlight candidate binds source, signed products, and evidence artifact', () => {
  assert.match(project, /MIKSourceCommit: \$\(MIK_SOURCE_COMMIT\)/);
  assert.match(archiveScript, /MIK_SOURCE_COMMIT="\$source_commit"/);
  assert.match(archiveScript, /Print :MIKSourceCommit/);
  assert.match(archiveScript, /com\.apple\.security\.application-groups:0/);
  assert.match(archiveScript, /candidate-evidence\.json/);
  assert.match(archiveScript, /archive_digest/);
  assert.match(archiveScript, /ipa_digest/);
  assert.match(archiveScript, /codesign --verify --deep --strict/);
  assert.match(archiveScript, /host_profile_uuid/);
  assert.match(archiveScript, /extension_profile_uuid/);
  assert.match(archiveScript, /team_id\.\$expected_bundle_id/);
  assert.match(archiveScript, /processing_status_digest/);
  assert.match(archiveScript, /not_proven_until_physical_device/);
  assert.match(archiveScript, /source_commit.*head_commit/s);
  assert.match(workflow, /IOS_SOURCE_COMMIT: \$\{\{ github\.sha \}\}/);
  assert.match(workflow, /candidate-evidence\.json/);
  assert.match(workflow, /processing-status\.json/);
});

test('upload fails closed without complete App Store Connect authentication', () => {
  assert.match(archiveScript, /UPLOAD_TO_TESTFLIGHT:-0.*ASC_KEY_PATH/s);
  assert.match(archiveScript, /ASC_KEY_ID/);
  assert.match(archiveScript, /ASC_ISSUER_ID/);
  assert.match(archiveScript, /Refusing to archive a dirty worktree/);
  assert.match(archiveScript, /Refusing TestFlight upload with ALLOW_DIRTY_ARCHIVE=1/);
  assert.match(archiveScript, /ASC_APPLE_ID/);
  assert.match(archiveScript, /altool --build-status/);
  assert.match(archiveScript, /--wait/);
});

test('workflow uses unique build and candidate paths and validates both profiles', () => {
  assert.match(workflow, /IOS_BUILD_NUMBER=\$\{GITHUB_RUN_ID\}\$\{GITHUB_RUN_ATTEMPT\}/);
  assert.match(workflow, /IOS_CANDIDATE_ROOT=/);
  assert.match(workflow, /environment: testflight-production/);
  assert.match(workflow, /Restrict uploads to main/);
  assert.doesNotMatch(workflow, /refs\/tags\/release-/);
  assert.match(workflow, /if-no-files-found: error/);
  assert.match(workflow, /TestFlight\/\*\.ipa/);
  assert.match(workflow, /validate-provisioning-profile\.sh.*com\.torutesu\.mobileaikeyboard /);
  assert.match(workflow, /validate-provisioning-profile\.sh.*com\.torutesu\.mobileaikeyboard\.keyboard /);
  assert.match(profileValidator, /application-identifier/);
  assert.match(profileValidator, /com\.apple\.security\.application-groups/);
  assert.match(profileValidator, /ExpirationDate/);
  assert.match(profileValidator, /length == 1 and \.\[0\] == \$group/);
});

test('archive script rejects a source SHA that is not the checked-out HEAD before building', () => {
  const result = spawnSync('zsh', ['apps/ios/scripts/archive-testflight.sh'], {
    cwd: process.cwd(),
    encoding: 'utf8',
    env: {
      ...process.env,
      IOS_DEVELOPMENT_TEAM: 'ABCDE12345',
      IOS_SOURCE_COMMIT: '0000000000000000000000000000000000000000',
    },
  });

  assert.equal(result.status, 65);
  assert.match(result.stderr, /does not match the checked-out HEAD/);
});

test('archive script refuses dirty overrides for a TestFlight upload', () => {
  const head = spawnSync('git', ['rev-parse', 'HEAD'], {
    cwd: process.cwd(),
    encoding: 'utf8',
  }).stdout.trim();
  const result = spawnSync('zsh', ['apps/ios/scripts/archive-testflight.sh'], {
    cwd: process.cwd(),
    encoding: 'utf8',
    env: {
      ...process.env,
      IOS_DEVELOPMENT_TEAM: 'ABCDE12345',
      IOS_SOURCE_COMMIT: head,
      UPLOAD_TO_TESTFLIGHT: '1',
      ALLOW_DIRTY_ARCHIVE: '1',
    },
  });

  assert.equal(result.status, 65);
  assert.match(result.stderr, /Dirty archives are diagnostics-only/);
});
