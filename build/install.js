// Replaces /Applications/miTasks.app with the freshly packaged build.
// Quits any running copy first — an app can't be swapped underneath itself.
const { execFileSync, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const root = path.join(__dirname, '..');
const pkg = require(path.join(root, 'package.json'));
const built = path.join(root, 'release', `${pkg.productName}-darwin-arm64`, `${pkg.productName}.app`);
const target = `/Applications/${pkg.productName}.app`;

if (!fs.existsSync(built)) {
  console.error('No build found. Run `npm run pack` first.');
  process.exit(1);
}

try {
  execSync(`pkill -f "${target}/Contents/MacOS/"`, { stdio: 'ignore' });
  console.log('quit the running copy');
} catch {
  console.log('nothing was running');
}

// Give launchd a moment to reap the old process before the swap.
Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1200);
fs.rmSync(target, { recursive: true, force: true });
execFileSync('ditto', [built, target], { stdio: 'inherit' });
console.log('installed →', target);
