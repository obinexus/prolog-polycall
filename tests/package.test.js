'use strict';

// Package-metadata test (no Prolog needed): npm and binding manifest are
// consistent and every exported path exists. The binding itself is tested
// against the real core by tests/run-real-core.sh.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const binding = require('..');
const metadata = require('../package.json');
const manifest = require('../polycall-binding.json');

const repo = 'https://github.com/obinexus/prolog-polycall';

assert.equal(metadata.name, 'prolog-polycall');
assert.equal(metadata.license, 'MIT');
assert.equal(metadata.publishConfig.access, 'public');
assert.equal(metadata.repository.url, `git+${repo}.git`);
assert.equal(metadata.bugs.url, `${repo}/issues`);
assert.equal(metadata.homepage, `${repo}#readme`);
assert.equal(manifest.version, metadata.version);
assert.equal(manifest.core, 'polycall >= 1.1.0 (binding ABI 1)');
assert.equal(manifest.core_repository, 'https://github.com/obinexus/polycall');
for (const key of ['native_extension', 'module', 'config']) {
  assert.ok(fs.existsSync(path.join(__dirname, '..', manifest[key])), `manifest ${key} exists`);
}

const author = typeof metadata.author === 'string'
  ? metadata.author
  : `${metadata.author?.name} <${metadata.author?.email}>`;
assert.equal(author, 'Nnamdi Michael Okpala <okpalan@protonmail.com>');

const source = fs.readFileSync(binding.foreignSource, 'utf8');
const prolog = fs.readFileSync(binding.prologModule, 'utf8');
const makefile = fs.readFileSync(binding.makefile, 'utf8');
assert.match(source, /#include <polycall\.h>/);
assert.match(prolog, /run_config\(Path, Status\) :-\n\s+run_config\(Path, true, Status\)\./,
  'run_config/2 keeps polycall_ffi_run_config(Path, 1)');
assert.match(makefile, new RegExp(`^VERSION := ${metadata.version}$`, 'm'));
assert.match(makefile, /\$\(PKG_CONFIG\) --cflags polycall/);

const metadataKeys = { src: 'src', dist: 'dist', examples: 'example', tests: 'test' };
for (const [name, directory] of Object.entries(binding.directories)) {
  const metadataKey = metadataKeys[name];
  assert.equal(metadata.directories[metadataKey], directory.relative);
  assert.equal(path.isAbsolute(metadata.directories[metadataKey]), false);
  assert.equal(fs.statSync(directory.root).isDirectory(), true);
  assert.ok(directory.files.length > 0, `${name} directory index is empty`);
  assert.ok(directory.files.every((file) => file.startsWith(`${directory.root}${path.sep}`)));
}

assert.ok(binding.directories.src.relativeFiles.includes('prolog_polycall.pl'));
assert.ok(binding.directories.src.relativeFiles.includes('prolog_polycall.c'));
assert.ok(binding.directories.examples.relativeFiles.includes('basic.pl'));
assert.ok(binding.directories.tests.relativeFiles.includes('prolog_polycall_tests.pl'));
assert.throws(() => binding.resolve('src', '..', 'package.json'), RangeError);

for (const file of [
  binding.prologModule,
  binding.foreignSource,
  binding.config,
  binding.manifest,
  binding.makefile
]) {
  assert.equal(path.isAbsolute(file), true, `path is not absolute: ${file}`);
  assert.equal(fs.existsSync(file), true, `missing project file: ${file}`);
}

console.log('prolog-polycall package metadata test: PASS');
