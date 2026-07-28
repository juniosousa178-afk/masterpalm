/**
 * Playwright — PackageInfo Web real (build com version.json mesclado).
 * Pré-requisito: build/web servido em R8433_PROBE_URL (default http://127.0.0.1:8770)
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../..');

const BUILD_DIR = process.env.R8433_PROBE_BUILD_DIR || path.join(repoRoot, 'build', 'web-probe');
const PORT = Number(process.env.R8433_PROBE_PORT || 8770);

function serve(rootDir) {
  return http.createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
    const rel = urlPath === '/' ? '/index.html' : urlPath;
    const filePath = path.join(rootDir, rel.replace(/^\//, ''));
    if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
      res.writeHead(404); res.end('nf'); return;
    }
    const ext = path.extname(filePath).toLowerCase();
    const types = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm' };
    res.writeHead(200, { 'Content-Type': types[ext] || 'application/octet-stream' });
    fs.createReadStream(filePath).pipe(res);
  });
}

async function main() {
  if (!fs.existsSync(BUILD_DIR)) {
    console.error('BUILD ausente. Execute scripts/build_web_probe_e2e.ps1');
    process.exit(2);
  }
  const server = serve(BUILD_DIR);
  await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  let probeJson = null;
  page.on('console', (msg) => {
    const t = msg.text();
    if (t.startsWith('R8433_WEB_PROBE_JSON=')) probeJson = t.slice('R8433_WEB_PROBE_JSON='.length);
  });
  await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'load', timeout: 120000 });
  const deadline = Date.now() + 90000;
  while (!probeJson && Date.now() < deadline) await new Promise((r) => setTimeout(r, 500));
  await browser.close();
  server.close();
  if (!probeJson) { console.error('PROBE_FAIL'); process.exit(4); }
  const data = JSON.parse(probeJson);
  console.log('R8433_WEB_PROBE_RESULT=' + JSON.stringify(data, null, 2));
  const ok = data.version === '1.0.80' && String(data.buildNumber) === '285' &&
    data.parsedBuildNumber === 285 && data.source === 'packageInfo' && data.resolved === 285;
  process.exit(ok ? 0 : 5);
}

main().catch((e) => { console.error(e); process.exit(1); });
