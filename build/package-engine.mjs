#!/usr/bin/env node
// Packages one engine build for hosting:
//   node build/package-engine.mjs build/out/<build id> [dist/engine]
// writes dist/engine/<build id>/{soffice.js,soffice.wasm,soffice.data,soffice.data.js.metadata}
// (raw) plus a .br of each (served with Content-Encoding: br), NOTICE.md, and dist/engine/engine.json,
// the manifest the editor loads (`id`, raw `bytes` for download progress, `sha256`).
import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync, statSync, writeFileSync, copyFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { constants, createBrotliCompress } from 'node:zlib';
import { fileURLToPath } from 'node:url';

const ENGINE_FILES = ['soffice.js', 'soffice.wasm', 'soffice.data', 'soffice.data.js.metadata'];
const here = dirname(fileURLToPath(import.meta.url));

const [srcArg, outArg = join(here, '..', 'dist', 'engine')] = process.argv.slice(2);
if (!srcArg) {
	console.error('usage: node build/package-engine.mjs build/out/<build id> [dist/engine]');
	process.exit(2);
}
const src = resolve(srcArg);
const info = JSON.parse(readFileSync(join(src, 'build-info.json'), 'utf8'));
const id = info.id || basename(src);
const dest = join(resolve(outArg), id);
mkdirSync(dest, { recursive: true });

async function sha256(file) {
	const h = createHash('sha256');
	await pipeline(createReadStream(file), h);
	return h.digest('hex');
}

async function brotli(from, to) {
	const size = statSync(from).size;
	await pipeline(createReadStream(from), createBrotliCompress({
		params: {
			[constants.BROTLI_PARAM_QUALITY]: 11,
			[constants.BROTLI_PARAM_LGWIN]: 24,
			[constants.BROTLI_PARAM_SIZE_HINT]: size
		}
	}), createWriteStream(to));
}

const files = {};
for (const name of ENGINE_FILES) {
	const from = join(src, name);
	if (!existsSync(from)) throw new Error(`missing ${name} in ${src}`);
	const raw = join(dest, name);
	copyFileSync(from, raw);
	const t0 = Date.now();
	await brotli(raw, raw + '.br');
	files[name] = { bytes: statSync(raw).size, brBytes: statSync(raw + '.br').size, sha256: await sha256(raw) };
	console.log(`${name}: ${files[name].bytes} raw, ${files[name].brBytes} br (${((Date.now() - t0) / 1000).toFixed(1)} s)`);
}

const notice = join(here, '..', 'docs', 'ENGINE-NOTICE.md');
if (existsSync(notice)) copyFileSync(notice, join(dest, 'NOTICE.md'));

const manifest = {
	id,
	variant: info.variant,
	coreCommit: info.coreCommit,
	patches: info.patches,
	builtAtUTC: info.builtAtUTC,
	files
};
writeFileSync(join(dest, 'engine.json'), JSON.stringify(manifest, null, 2) + '\n');
writeFileSync(join(resolve(outArg), 'engine.json'), JSON.stringify(manifest, null, 2) + '\n');
const total = Object.values(files).reduce((a, f) => ({ raw: a.raw + f.bytes, br: a.br + f.brBytes }), { raw: 0, br: 0 });
console.log(`total: ${total.raw} raw, ${total.br} br -> ${dest}`);
