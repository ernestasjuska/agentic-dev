// Drives a real browser through BC web client sign-in and reports whether a
// Role Center rendered. Invoked by bc-webclient-signin.ps1; see that file for
// why each step exists.
import { chromium } from 'playwright-core';

const cfg = JSON.parse(process.argv[2]);
const args = ['--no-sandbox', '--ignore-certificate-errors'];
if (cfg.disableHttp2) args.push('--disable-http2');

const browser = await chromium.launch({ executablePath: cfg.chrome, args });
const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1600, height: 1000 } });
const page = await ctx.newPage();

const failures = [], sockets = [];
page.on('response', r => {
  if (r.status() >= 400) failures.push(`${r.status()} ${r.url().replace(/^https?:\/\/[^/]*/, '').slice(0, 70)}`);
});
page.on('websocket', w => {
  sockets.push('OPEN');
  w.on('socketerror', e => sockets.push('ERROR:' + e));
  w.on('framereceived', () => { if (!sockets.includes('FRAME')) sockets.push('FRAME'); });
});

// Every frame, because the SPA renders in an iframe and the outer document
// only ever shows the chrome.
async function allText() {
  let t = '';
  for (const f of page.frames()) t += ' ' + (await f.locator('body').innerText().catch(() => ''));
  return t.replace(/\s+/g, ' ').trim();
}

const out = { url: cfg.url, verdict: 'UNKNOWN' };
try {
  await page.goto(cfg.url, { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(3000);

  // A devtunnel shows an anti-phishing interstitial to browsers once per
  // tunnel. curl never sees it, so a curl probe looks healthier than this.
  const cont = page.locator('button:has-text("Continue"), a:has-text("Continue"), input[value*="Continue" i]');
  if (await cont.count()) {
    out.interstitial = true;
    await cont.first().click();
    await page.waitForTimeout(5000);
  }

  await page.waitForSelector('input#Password', { timeout: 45000 });
  out.signInUrl = page.url();
  await page.fill('input#UserName', cfg.user);
  await page.fill('input#Password', cfg.password);
  await Promise.all([
    page.waitForLoadState('load').catch(() => {}),
    page.click('input[type="submit"], button[type="submit"]'),
  ]);

  for (let i = 1; i <= cfg.pollCount; i++) {
    await page.waitForTimeout(cfg.pollMs);
    const t = await allText();
    if (/CRONUS|Activities|Sales This Month|Customers|Role Center/i.test(t)) { out.verdict = 'ROLE CENTER OK'; break; }
    if (/trouble completing|Sorry, the page/i.test(t)) { out.verdict = 'ERROR: ' + t.slice(0, 120); break; }
    if (i === cfg.pollCount) out.verdict = 'NO ROLE CENTER: ' + t.slice(0, 120);
  }
  out.finalUrl = page.url();
} catch (e) {
  out.verdict = 'FAILED: ' + e.message.split('\n')[0];
}

out.httpFailures = failures.slice(0, 6);
out.webSocket = sockets.length ? sockets.join(' | ') : 'none';
if (cfg.screenshot) {
  await page.screenshot({ path: cfg.screenshot }).catch(() => {});
  out.screenshot = cfg.screenshot;
}
console.log(JSON.stringify(out, null, 2));
await browser.close();
