// Serves a built Flutter web app on this computer only.
//   node flutter/tools/serve_web.js                             -> patient app, sample data, http://localhost:5180
//   node flutter/tools/serve_web.js patient 5181 web_firebase   -> patient app on the Firebase emulators
//   node flutter/tools/serve_web.js admin 5182                  -> admin website (emulators unless built with BACKEND=live)
// Build first, inside the app's folder:
//   flutter build web                                            (sample data -> build/web)
//   flutter build web --dart-define=BACKEND=emulator -o build/web_firebase
const http = require('http'), fs = require('fs'), path = require('path');

const app = process.argv[2] || 'patient';
const port = Number(process.argv[3] || 5180);
const folder = process.argv[4] || 'web';
// patient -> patient_app, admin -> admin_web
const project = ['_app', '_web'].map((s) => `${app}${s}`).find((p) => fs.existsSync(path.join(__dirname, '..', p))) || `${app}_app`;
const root = path.join(__dirname, '..', project, 'build', folder);
const types = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf', '.ico': 'image/x-icon',
};

if (!fs.existsSync(path.join(root, 'index.html'))) {
  console.error(`No build found at ${root}. Run "flutter build web" in flutter/${project} first.`);
  process.exit(1);
}

http
  .createServer((req, res) => {
    let url = decodeURIComponent(req.url.split('?')[0]);
    // app paths like a clinic's booking link (/c/mg) load the app, as on Firebase Hosting
    if (url === '/' || !path.extname(url)) url = '/index.html';
    const file = path.join(root, url);
    if (!file.startsWith(root)) return res.writeHead(403).end();
    fs.readFile(file, (err, data) => {
      if (err) return res.writeHead(404).end('not found');
      res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      res.end(data);
    });
  })
  .listen(port, '127.0.0.1', () => console.log(`ClinicFlow ${app} app: http://localhost:${port}   (Ctrl+C to stop)`));
