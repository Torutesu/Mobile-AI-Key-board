#!/usr/bin/env node

import fs from 'node:fs';

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) throw new Error(`Invalid argument: ${key ?? 'missing'}`);
    args[key.slice(2)] = value;
  }
  for (const key of ['input', 'apple-id', 'marketing-version', 'build-version']) {
    if (!args[key]) throw new Error(`Missing --${key}`);
  }
  return args;
}

function flatten(value, path = '$', entries = []) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => flatten(item, `${path}[${index}]`, entries));
  } else if (value && typeof value === 'object') {
    for (const [key, item] of Object.entries(value)) flatten(item, `${path}.${key}`, entries);
  } else {
    entries.push({ path, value });
  }
  return entries;
}

export function validateProcessingStatus(value, expected) {
  const entries = flatten(value);
  const serialized = JSON.stringify(value).toLowerCase();
  const errors = [];
  const scalarStrings = entries.map(({ value: item }) => String(item));
  for (const [label, expectedValue] of [
    ['Apple ID', expected.appleId],
    ['marketing version', expected.marketingVersion],
    ['build version', expected.buildVersion],
  ]) {
    if (!scalarStrings.includes(String(expectedValue))) errors.push(`${label} ${expectedValue} is not present in processing evidence`);
  }

  const failurePattern = /(^|[^a-z])(failed|failure|invalid|rejected|error)([^a-z]|$)/i;
  const failure = entries.find(({ path, value: item }) => {
    const key = path.split('.').at(-1) ?? '';
    if (/error|failure|issues?/i.test(key) && item !== null && item !== false && item !== '' && item !== 0) return true;
    return typeof item === 'string' && failurePattern.test(item);
  });
  if (failure) errors.push(`processing evidence contains a failure marker at ${failure.path}`);

  const successState = entries.some(({ path, value: item }) => {
    if (item === true && /success|complete|processed|valid|ready/i.test(path)) return true;
    return typeof item === 'string' && /^(success|succeeded|complete|completed|processed|valid|ready|ready_for_sale)$/i.test(item.trim());
  });
  if (!successState) errors.push('processing evidence has no recognized successful terminal state');
  if (/processing|uploading|pending|waiting/i.test(serialized) && !successState) errors.push('processing evidence is not terminal');
  return errors;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const parsed = JSON.parse(fs.readFileSync(args.input, 'utf8'));
    const errors = validateProcessingStatus(parsed, {
      appleId: args['apple-id'],
      marketingVersion: args['marketing-version'],
      buildVersion: args['build-version'],
    });
    if (errors.length) throw new Error(errors.join('; '));
    console.log(`Verified App Store Connect processing for ${args['apple-id']} ${args['marketing-version']} (${args['build-version']}).`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) main();
