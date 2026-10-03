'use strict';

const fs = require('node:fs');
const path = require('node:path');

const relativeDirectories = Object.freeze({
  src: 'src',
  dist: 'dist',
  examples: 'examples',
  tests: 'tests'
});

function walkFiles(root, current = root) {
  return fs.readdirSync(current, { withFileTypes: true })
    .sort((left, right) => left.name.localeCompare(right.name))
    .flatMap((entry) => {
      const absolutePath = path.join(current, entry.name);
      return entry.isDirectory() ? walkFiles(root, absolutePath) : [absolutePath];
    });
}

function indexDirectory(relativePath) {
  const root = path.join(__dirname, relativePath);
  const files = walkFiles(root);
  return Object.freeze({
    relative: relativePath,
    root,
    files: Object.freeze(files),
    relativeFiles: Object.freeze(
      files.map((file) => path.relative(root, file).split(path.sep).join('/'))
    )
  });
}

const directories = Object.freeze(
  Object.fromEntries(
    Object.entries(relativeDirectories).map(([name, relativePath]) => [
      name,
      indexDirectory(relativePath)
    ])
  )
);

function resolve(directoryName, ...segments) {
  const directory = directories[directoryName];
  if (!directory) {
    throw new RangeError(`unknown prolog-polycall directory: ${directoryName}`);
  }

  const resolved = path.resolve(directory.root, ...segments);
  const prefix = `${directory.root}${path.sep}`;
  if (resolved !== directory.root && !resolved.startsWith(prefix)) {
    throw new RangeError(`path escapes prolog-polycall ${directoryName} directory`);
  }
  return resolved;
}

module.exports = Object.freeze({
  packageName: 'prolog-polycall',
  projectRoot: __dirname,
  directories,
  resolve,
  prologModule: path.join(__dirname, 'src', 'prolog_polycall.pl'),
  foreignSource: path.join(__dirname, 'src', 'prolog_polycall.c'),
  config: path.join(__dirname, 'prolog-polycallrc'),
  manifest: path.join(__dirname, 'polycall-binding.json'),
  makefile: path.join(__dirname, 'Makefile')
});
