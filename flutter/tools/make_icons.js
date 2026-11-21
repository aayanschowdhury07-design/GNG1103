// Draws the ClinicFlow icon (an open ring and a dot on the app's blue) as PNGs for the web
// apps: favicon, home-screen icons and Android's maskable icons. No image library needed.
//   node flutter/tools/make_icons.js
const fs = require('fs'), path = require('path'), zlib = require('zlib');

const BLUE = [0x3c, 0x64, 0x9f], WHITE = [0xff, 0xff, 0xff];

// coverage of the white mark at (x, y), in a 0..1 square
function mark(x, y, scale) {
  const cx = 0.5, cy = 0.5, dx = x - cx, dy = y - cy;
  const r = Math.hypot(dx, dy), angle = Math.atan2(dy, dx) * 180 / Math.PI;
  const outer = 0.29 * scale, width = 0.085 * scale;
  // the ring, open on the right (the way in)
  if (r <= outer && r >= outer - width && Math.abs(angle) > 42) return true;
  // the dot waiting in the opening
  const dot = Math.hypot(x - (cx + (outer - width / 2) * 0.62), y - cy);
  return dot <= width * 0.78;
}

// rounded square for the favicon; full bleed for home-screen icons
function inside(x, y, radius) {
  if (!radius) return true;
  const qx = Math.max(Math.abs(x - 0.5) - (0.5 - radius), 0), qy = Math.max(Math.abs(y - 0.5) - (0.5 - radius), 0);
  return Math.hypot(qx, qy) <= radius;
}

function draw(size, { radius = 0, scale = 1 } = {}) {
  const ss = 4, px = Buffer.alloc(size * size * 4);
  for (let j = 0; j < size; j++) {
    for (let i = 0; i < size; i++) {
      let bg = 0, fg = 0;
      for (let sj = 0; sj < ss; sj++) {
        for (let si = 0; si < ss; si++) {
          const x = (i + (si + 0.5) / ss) / size, y = (j + (sj + 0.5) / ss) / size;
          if (!inside(x, y, radius)) continue;
          bg++;
          if (mark(x, y, scale)) fg++;
        }
      }
      const n = ss * ss, a = bg / n, t = bg ? fg / bg : 0, o = (j * size + i) * 4;
      for (let k = 0; k < 3; k++) px[o + k] = Math.round(BLUE[k] + (WHITE[k] - BLUE[k]) * t);
      px[o + 3] = Math.round(a * 255);
    }
  }
  return png(size, px);
}

function png(size, px) {
  const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (buf) => {
    let c = 0xffffffff;
    for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4), sum = Buffer.alloc(4), td = Buffer.concat([Buffer.from(type), data]);
    len.writeUInt32BE(data.length);
    sum.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, sum]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header.set([8, 6, 0, 0, 0], 8); // 8-bit RGBA
  const rows = Buffer.alloc(size * (size * 4 + 1));
  for (let j = 0; j < size; j++) px.copy(rows, j * (size * 4 + 1) + 1, j * size * 4, (j + 1) * size * 4);
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(rows, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

for (const app of ['patient_app', 'admin_web']) {
  const web = path.join(__dirname, '..', app, 'web');
  fs.writeFileSync(path.join(web, 'favicon.png'), draw(32, { radius: 0.22, scale: 1.25 }));
  fs.writeFileSync(path.join(web, 'icons', 'Icon-192.png'), draw(192, { scale: 1.1 }));
  fs.writeFileSync(path.join(web, 'icons', 'Icon-512.png'), draw(512, { scale: 1.1 }));
  // maskable: launchers crop to a circle or squircle, so the mark stays in the middle 80%
  fs.writeFileSync(path.join(web, 'icons', 'Icon-maskable-192.png'), draw(192, { scale: 0.9 }));
  fs.writeFileSync(path.join(web, 'icons', 'Icon-maskable-512.png'), draw(512, { scale: 0.9 }));
}
console.log('Icons written for patient_app and admin_web.');
