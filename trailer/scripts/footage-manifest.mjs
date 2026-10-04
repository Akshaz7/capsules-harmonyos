// Lists public/footage/ and writes src/generated/footage-manifest.json.
// A scene uses a recording if its file exists; otherwise its board or a placeholder.
import {readdirSync, writeFileSync, mkdirSync, existsSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dir = join(root, 'public', 'footage');
const files = existsSync(dir) ? readdirSync(dir).filter((f) => f.toLowerCase().endsWith('.mp4')) : [];
const manifest = Object.fromEntries(files.map((f) => [f.replace(/\.mp4$/i, ''), `footage/${f}`]));
const out = join(root, 'src', 'generated', 'footage-manifest.json');
mkdirSync(dirname(out), {recursive: true});
writeFileSync(out, JSON.stringify(manifest, null, 2) + '\n');

// Music is optional: a track dropped at public/audio/music.mp3 is picked up automatically.
writeFileSync(join(root, 'src', 'generated', 'music.json'), JSON.stringify({exists: existsSync(join(root, 'public', 'audio', 'music.mp3'))}) + '\n');

const required = ['judge', 'widget-pin', 'widget-tap', 'calendar'];
const optional = ['emma', 'tyler', 'friends', 'olivia', 'rose', 'mike'];
for (const k of required) console.log(`${manifest[k] ? 'found  ' : 'MISSING'} ${k}.mp4 (required)`);
for (const k of optional) console.log(`${manifest[k] ? 'found  ' : 'board  '} ${k}.mp4 (optional)`);
