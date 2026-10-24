// Starts the local Firebase emulators (Auth, Firestore, dashboard on http://localhost:4000).
// Project "demo-clinicflow" is local-only: nothing reaches Google's servers.
//   node flutter/tools/start_emulators.js        (Ctrl+C to stop)
const { spawn, execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// the emulators need Java; use the installed JDK 21 even if this shell started before it was installed
const env = { ...process.env };
const base = 'C:\\Program Files\\Microsoft';
const jdk = fs.existsSync(base) && fs.readdirSync(base).find((d) => d.startsWith('jdk-21'));
if (jdk) {
  env.JAVA_HOME = path.join(base, jdk);
  env.PATH = `${path.join(base, jdk, 'bin')};${env.PATH}`;
}

// ask npm where global packages live rather than guessing from the environment
let globalRoot = '';
try {
  globalRoot = execSync('npm root -g', { encoding: 'utf8' }).trim();
} catch {}
const cli = path.join(globalRoot, 'firebase-tools', 'lib', 'bin', 'firebase.js');
if (!fs.existsSync(cli)) {
  console.error('Firebase CLI not found. Install it with: npm install -g firebase-tools');
  process.exit(1);
}
spawn(process.execPath, [cli, 'emulators:start', '--project', 'demo-clinicflow'], { cwd: path.join(__dirname, '..'), env, stdio: 'inherit' })
  .on('exit', (code) => process.exit(code ?? 0));
