// Servidor estático local com o rewrite SPA do Firebase Hosting (`**` -> /index.html).
// Uso: node serve_spa.mjs <webDir> <porta>
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';

const [dir = '../../build/web', port = '8790'] = process.argv.slice(2);
const root = path.resolve(dir);
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.otf': 'font/otf',
  '.ttf': 'font/ttf', '.woff2': 'font/woff2', '.map': 'application/json', '.frag': 'text/plain',
};

http.createServer((req, res) => {
  const p = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  let file = path.join(root, p);
  if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    file = path.join(root, 'index.html');
  }
  res.writeHead(200, {
    'content-type': TYPES[path.extname(file)] || 'application/octet-stream',
    'cache-control': 'no-store',
  });
  fs.createReadStream(file).pipe(res);
}).listen(Number(port), '127.0.0.1', () => console.log(`servindo ${root} em http://localhost:${port}`));
