// Checks the staff website's French: every tr('...') / trn(n, '...', '...') text in
// admin_web/lib must have a French entry in admin_web/lib/l10n/fr_*.dart, with the same
// {placeholders}. Also lists French entries nothing uses any more.
//   node flutter/tools/check_fr.js
const fs = require('fs'), path = require('path');
const lib = path.join(__dirname, '..', 'admin_web', 'lib');

const files = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? files(path.join(dir, e.name)) : e.name.endsWith('.dart') ? [path.join(dir, e.name)] : []));
// a Dart single-quoted string literal, with \' escapes
const lit = String.raw`'((?:[^'\\]|\\.)*)'`;
const unescape = (s) => s.replace(/\\(.)/g, '$1');

// one or more adjacent literals ('a ' 'b'), which Dart joins into one string
const lits = String.raw`((?:'(?:[^'\\]|\\.)*'\s*)+)`;
const join = (s) => [...s.matchAll(new RegExp(lit, 'g'))].map((m) => unescape(m[1])).join('');

const fr = new Map(), from = new Map();
for (const f of fs.readdirSync(path.join(lib, 'l10n'))) {
  const src = fs.readFileSync(path.join(lib, 'l10n', f), 'utf8');
  for (const m of src.matchAll(new RegExp(String.raw`^\s*${lits}:\s*${lits},?\s*$`, 'gm'))) {
    const en = join(m[1]), value = join(m[2]);
    // the same English with different French: the later map wins, so flag it
    if (fr.has(en) && fr.get(en) !== value) console.log(`CONFLICT ${en}  =>  ${from.get(en)}: ${fr.get(en)}  |  ${f}: ${value}`);
    fr.set(en, value);
    from.set(en, f);
  }
}

const used = new Set(), missing = [], badHoles = [];
const holes = (s) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort().join(',');
for (const f of files(lib).filter((f) => !f.includes(`${path.sep}l10n${path.sep}`))) {
  const src = fs.readFileSync(f, 'utf8');
  // skip comments, so examples in doc comments don't count
  const code = src.replace(/^\s*\/\/.*$/gm, '');
  const texts = [
    ...[...code.matchAll(new RegExp(String.raw`\btr\(\s*${lits}`, 'g'))].map((m) => join(m[1])),
    ...[...code.matchAll(new RegExp(String.raw`\btrn\([^,]+,\s*${lits},\s*${lits}`, 'g'))].flatMap((m) => [join(m[1]), join(m[2])]),
  ];
  for (const en of texts) {
    used.add(en);
    if (/\$/.test(en)) badHoles.push(`${path.basename(f)}: Dart interpolation inside tr(): ${en}`);
    if (!fr.has(en)) missing.push(`${path.basename(f)}: ${en}`);
    else if (holes(en) !== holes(fr.get(en))) badHoles.push(`${path.basename(f)}: placeholders differ: ${en}  =>  ${fr.get(en)}`);
  }
}
const unused = [...fr.keys()].filter((k) => !used.has(k));
for (const m of missing) console.log('MISSING  ' + m);
for (const b of badHoles) console.log('PROBLEM  ' + b);
for (const u of unused) console.log('UNUSED   ' + u);
console.log(`\n${used.size} texts translated through tr(); ${fr.size} French entries; ${missing.length} missing, ${badHoles.length} problems, ${unused.length} unused.`);
process.exit(missing.length || badHoles.length ? 1 : 0);
