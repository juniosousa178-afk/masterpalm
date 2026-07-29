/** CLI — servir build/web estático (R8.4.43). */
import { serveStatic } from './serve-build.mjs';

const port = Number(process.argv[2] || process.env.R8443_SERVE_PORT || 8811);
const root = process.argv[3] || 'build/web';

await serveStatic(root, port);
console.log(`SERVE_OK port=${port} root=${root}`);
process.stdin.resume();
