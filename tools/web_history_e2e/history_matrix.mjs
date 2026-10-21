// Regressão do histórico do browser no Flutter web: deep link direto, refresh, Voltar,
// Avançar e copiar/colar para pedido público, catálogo e retornos de plano.
// Perfil Chrome limpo por caso (sem login); ids de loja/pedido inexistentes, só navegação.
//
// Uso: node history_matrix.mjs <baseUrl> [out.json] [--allow-remote]
//   (padrão: http://localhost:8790, servido por serve_spa.mjs a partir de build/web)
// CHROME_PATH sobrescreve o executável do Chrome.
import fs from 'node:fs';
import puppeteer from 'puppeteer-core';

const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const allowRemote = process.argv.includes('--allow-remote');
const [base = 'http://localhost:8790', out] = args;
if (!/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(base) && !allowRemote) {
  console.error(`base ${base} não é local; use --allow-remote para rodar contra outro host.`);
  process.exit(2);
}
const CHROME = process.env.CHROME_PATH || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const ROUTES = {
  pedido: '/pedido/ZZprobeHistory0000000001?loja=zz-loja-inexistente-smoke',
  loja: '/loja/zz-loja-inexistente-smoke',
  assinatura: '/assinatura/teste/retorno',
  planos: '/planos/retorno?preapproval_id=teste',
  troca: '/assinatura/troca/teste/retorno',
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rel = (u) => {
  try {
    const x = new URL(u);
    return x.origin === new URL(base).origin ? x.pathname + x.search : u;
  } catch {
    return u;
  }
};

/** Espera o Flutter montar e a URL ficar estável. */
async function settle(page, {minMs = 4000, maxMs = 25000} = {}) {
  const t0 = Date.now();
  let last = page.url();
  let stableSince = Date.now();
  while (Date.now() - t0 < maxMs) {
    await sleep(500);
    const cur = page.url();
    const booted = !cur.startsWith(base) || await page
      .evaluate(() => !!document.querySelector('flutter-view, flt-glass-pane'))
      .catch(() => false);
    if (cur !== last) {
      last = cur;
      stableSince = Date.now();
    }
    if (booted && Date.now() - stableSince >= minMs) break;
  }
  return page.url();
}

const back = (page) => page.evaluate(() => history.back()).catch(() => {});
const forward = (page) => page.evaluate(() => history.forward()).catch(() => {});

const browser = await puppeteer.launch({executablePath: CHROME, headless: true, args: ['--no-first-run']});
const results = {};
try {
  for (const [name, path] of Object.entries(ROUTES)) {
    const ctx = await browser.createBrowserContext();
    const page = await ctx.newPage();
    await page.goto('about:blank');
    await page.goto(base + path, {waitUntil: 'domcontentloaded'});
    const boot = rel(await settle(page));
    await page.reload({waitUntil: 'domcontentloaded'});
    const refresh = rel(await settle(page));
    await back(page);
    const afterBack = await settle(page, {minMs: 3000});
    await forward(page);
    const afterForward = rel(await settle(page));
    const pasteTab = await ctx.newPage();
    await pasteTab.goto(base + boot, {waitUntil: 'domcontentloaded'});
    const pasted = rel(await settle(pasteTab));
    results[name] = {
      INITIAL_URL: path, URL_AFTER_BOOT: boot, URL_AFTER_REFRESH: refresh,
      URL_AFTER_BACK: afterBack, URL_AFTER_FORWARD: afterForward, URL_AFTER_COPY_PASTE: pasted,
      pass: boot === path && refresh === path && afterBack === 'about:blank' &&
        afterForward === path && pasted === path,
    };
    await ctx.close();
  }

  // Deep link A -> deep link B na mesma aba -> Voltar -> Avançar.
  const ctx = await browser.createBrowserContext();
  const page = await ctx.newPage();
  await page.goto(base + ROUTES.troca, {waitUntil: 'domcontentloaded'});
  await settle(page);
  await page.goto(base + ROUTES.pedido, {waitUntil: 'domcontentloaded'});
  await settle(page);
  await back(page);
  const chainBack = rel(await settle(page));
  await forward(page);
  const chainForward = rel(await settle(page));
  results.chain = {
    INITIAL_URL: `${ROUTES.troca} -> ${ROUTES.pedido}`,
    URL_AFTER_BACK: chainBack, URL_AFTER_FORWARD: chainForward,
    pass: chainBack === ROUTES.troca && chainForward === ROUTES.pedido,
  };
  await ctx.close();
} finally {
  await browser.close();
}

if (out) fs.writeFileSync(out, JSON.stringify({base, results}, null, 1));
for (const [k, v] of Object.entries(results)) console.log(k.padEnd(11), JSON.stringify(v));
const failed = Object.entries(results).filter(([, v]) => !v.pass).map(([k]) => k);
console.log(failed.length ? `FALHOU: ${failed.join(', ')}` : 'OK: todos os casos passaram');
process.exit(failed.length ? 1 : 0);
