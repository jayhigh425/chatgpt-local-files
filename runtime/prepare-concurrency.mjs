import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.dirname(fileURLToPath(import.meta.url));
const target = path.join(root, 'node_modules/@wonderwhy-er/desktop-commander/dist/config.js');
const original = "const CONFIG_DIR = path.join(USER_HOME, '.claude-server-commander');";
const replacement = "const CONFIG_DIR = process.env.LOCAL_ASSISTANT_CONFIG_DIR || path.join(USER_HOME, '.claude-server-commander');";
const text = await readFile(target, 'utf8');
if (!text.includes(replacement)) {
  if (!text.includes(original)) throw new Error('Unsupported Desktop Commander config module; refuse to apply an unknown patch.');
  await writeFile(target, text.replace(original, replacement));
}
console.log('Per-task configuration hook ready; Windows user profile is preserved.');
