// Packages miTasks for macOS, without going through @electron/packager.
//
// Packager re-downloads and unzips the 99 MB Electron archive on every run,
// which on this machine crawls. node_modules/electron/dist already holds that
// same tree unpacked, so we copy it and apply the rename/rebrand ourselves.
//
// Three things this has to get right:
//   1. the Swift EventKit helper ships in Contents/Resources
//   2. Info.plist carries the Calendar usage strings, or macOS silently
//      refuses to show the permission prompt at all
//   3. ElectronAsarIntegrity matches the new asar, or Electron won't load it
const { execFileSync } = require('child_process');
const crypto = require('crypto');
const asar = require('@electron/asar');
const path = require('path');
const fs = require('fs');

const root = path.join(__dirname, '..');
const pkg = require(path.join(root, 'package.json'));
const NAME = pkg.productName;
const BUNDLE_ID = 'rw.azultech.mitasks';

const dist = path.join(root, 'node_modules', 'electron', 'dist', 'Electron.app');
const outDir = path.join(root, 'release', `${NAME}-darwin-arm64`);
const app = path.join(outDir, `${NAME}.app`);
const contents = path.join(app, 'Contents');
const helperSrc = path.join(root, 'native', 'bin', 'mitasks-cal');

// Everything the app needs at runtime.
const SHIPPED = [
  'main.js', 'preload.js', 'server.js', 'calendar.js', 'lockin.js',
  'package.json', 'readme.md', 'renderer', 'mobile',
];

/// Production dependency closure, resolved from npm rather than hand-listed so
/// a new transitive dep can't silently go missing from the bundle. Dev deps
/// (Electron itself, the asar tooling) stay out.
function prodModules() {
  const out = execFileSync(
    'npm', ['ls', '--omit=dev', '--parseable', '--all'],
    { cwd: root, encoding: 'utf8' }
  );
  return out
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.includes('node_modules'))
    .map((abs) => path.relative(root, abs));
}

const HELPERS = [
  { from: 'Electron Helper', to: `${NAME} Helper`, name: NAME },
  { from: 'Electron Helper (GPU)', to: `${NAME} Helper (GPU)`, name: `${NAME} Helper (GPU)` },
  { from: 'Electron Helper (Plugin)', to: `${NAME} Helper (Plugin)`, name: `${NAME} Helper (Plugin)` },
  { from: 'Electron Helper (Renderer)', to: `${NAME} Helper (Renderer)`, name: `${NAME} Helper (Renderer)` },
];

const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit' });

function readPlist(file) {
  return JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', file]).toString());
}

function writePlist(file, data) {
  fs.writeFileSync(file, JSON.stringify(data));
  execFileSync('plutil', ['-convert', 'xml1', file]);
}

function step(msg) {
  process.stdout.write(`  ${msg}\n`);
}

/* ---------- 1. native helper ---------- */
step('compiling EventKit helper');
fs.mkdirSync(path.dirname(helperSrc), { recursive: true });
run('swiftc', ['-O', '-framework', 'EventKit', '-o', helperSrc,
  path.join(root, 'native', 'mitasks-cal.swift')]);

/* ---------- 2. copy the Electron tree ---------- */
step('copying Electron runtime');
fs.rmSync(outDir, { recursive: true, force: true });
fs.mkdirSync(outDir, { recursive: true });
run('ditto', [dist, app]);

/* ---------- 3. rebrand executables ---------- */
step('renaming executables');
fs.renameSync(path.join(contents, 'MacOS', 'Electron'), path.join(contents, 'MacOS', NAME));

for (const helper of HELPERS) {
  const frameworks = path.join(contents, 'Frameworks');
  const src = path.join(frameworks, `${helper.from}.app`);
  const dst = path.join(frameworks, `${helper.to}.app`);
  fs.renameSync(src, dst);
  fs.renameSync(
    path.join(dst, 'Contents', 'MacOS', helper.from),
    path.join(dst, 'Contents', 'MacOS', helper.to)
  );
  const plistPath = path.join(dst, 'Contents', 'Info.plist');
  const plist = readPlist(plistPath);
  plist.CFBundleExecutable = helper.to;
  plist.CFBundleName = helper.name;
  plist.CFBundleDisplayName = helper.name;
  plist.CFBundleIdentifier = `${BUNDLE_ID}.helper`;
  writePlist(plistPath, plist);
}

/* ---------- 4. resources ---------- */
step('staging app.asar');
const resources = path.join(contents, 'Resources');
fs.rmSync(path.join(resources, 'default_app.asar'), { force: true });
fs.copyFileSync(path.join(root, 'build', 'icon.icns'), path.join(resources, 'electron.icns'));
fs.copyFileSync(helperSrc, path.join(resources, 'mitasks-cal'));
fs.chmodSync(path.join(resources, 'mitasks-cal'), 0o755);

const stage = path.join(root, 'release', '.stage');
fs.rmSync(stage, { recursive: true, force: true });
fs.mkdirSync(stage, { recursive: true });
for (const entry of [...SHIPPED, ...prodModules()]) {
  const from = path.join(root, entry);
  if (fs.existsSync(from)) fs.cpSync(from, path.join(stage, entry), { recursive: true });
}

const asarPath = path.join(resources, 'app.asar');
asar.createPackageWithOptions(stage, asarPath, {}).then(finish).catch((err) => {
  console.error(err);
  process.exit(1);
});

function finish() {
  fs.rmSync(stage, { recursive: true, force: true });

  /* ---------- 5. Info.plist ---------- */
  step('writing Info.plist');
  const plistPath = path.join(contents, 'Info.plist');
  const plist = readPlist(plistPath);
  plist.CFBundleExecutable = NAME;
  plist.CFBundleName = NAME;
  plist.CFBundleDisplayName = NAME;
  plist.CFBundleIdentifier = BUNDLE_ID;
  plist.CFBundleVersion = pkg.version;
  plist.CFBundleShortVersionString = pkg.version;
  plist.CFBundleIconFile = 'electron.icns';
  plist.LSApplicationCategoryType = 'public.app-category.productivity';
  // Without these two, macOS never even offers the Calendar prompt.
  plist.NSCalendarsFullAccessUsageDescription =
    'miTasks shows your meetings beside your tasks and can block time on your calendar.';
  plist.NSCalendarsUsageDescription = plist.NSCalendarsFullAccessUsageDescription;

  // Integrity is keyed on the asar *header*, not the whole file.
  const { headerString } = asar.getRawHeader(asarPath);
  plist.ElectronAsarIntegrity = {
    'Resources/app.asar': {
      algorithm: 'SHA256',
      hash: crypto.createHash('sha256').update(headerString).digest('hex'),
    },
  };
  writePlist(plistPath, plist);

  /* ---------- 6. signing ---------- */
  // Deliberately NOT re-signing. Every Mach-O in the Electron dist already
  // carries a valid linker ad-hoc signature, and renaming a binary or editing
  // an unbound Info.plist doesn't invalidate it. Running `codesign --deep` here
  // seals the bundle's resources, and a sealed ad-hoc bundle with no Team ID
  // fails to launch through LaunchServices (`open` silently does nothing) even
  // though `codesign --verify` passes. Leaving it unsealed is what works.
  step('leaving stock ad-hoc signatures in place');

  console.log(`\npackaged → ${path.relative(root, app)}`);
}
