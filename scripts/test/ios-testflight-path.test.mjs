import assert from 'node:assert/strict';
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
  assert.match(archiveScript, /not_proven_until_physical_device/);
  assert.match(workflow, /IOS_SOURCE_COMMIT: \$\{\{ github\.sha \}\}/);
  assert.match(workflow, /candidate-evidence\.json/);
  assert.match(workflow, /processing-status\.json/);
});

test('upload fails closed without complete App Store Connect authentication', () => {
  assert.match(archiveScript, /UPLOAD_TO_TESTFLIGHT:-0.*ASC_KEY_PATH/s);
  assert.match(archiveScript, /ASC_KEY_ID/);
  assert.match(archiveScript, /ASC_ISSUER_ID/);
  assert.match(archiveScript, /Refusing to archive a dirty worktree/);
  assert.match(archiveScript, /ASC_APPLE_ID/);
  assert.match(archiveScript, /altool --build-status/);
  assert.match(archiveScript, /--wait/);
});

test('workflow uses unique build and candidate paths and validates both profiles', () => {
  assert.match(workflow, /IOS_BUILD_NUMBER=\$\{GITHUB_RUN_ID\}\$\{GITHUB_RUN_ATTEMPT\}/);
  assert.match(workflow, /IOS_CANDIDATE_ROOT=/);
  assert.match(workflow, /validate-provisioning-profile\.sh.*com\.torutesu\.mobileaikeyboard /);
  assert.match(workflow, /validate-provisioning-profile\.sh.*com\.torutesu\.mobileaikeyboard\.keyboard /);
  assert.match(profileValidator, /application-identifier/);
  assert.match(profileValidator, /com\.apple\.security\.application-groups/);
  assert.match(profileValidator, /ExpirationDate/);
});
