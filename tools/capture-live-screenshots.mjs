import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const outputDir = resolve(projectRoot, 'docs', 'images');
const chromePath = process.env.CHROME_PATH || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const storeUrl = process.env.STORE_URL;
const panelUrl = process.env.PANEL_URL;
const debugPort = Number(process.env.CHROME_DEBUG_PORT || 9333);
const profileDir = resolve(projectRoot, '.screenshot-chrome-profile');

if (!storeUrl || !panelUrl) {
  throw new Error('Set STORE_URL and PANEL_URL before capturing screenshots');
}

class CdpClient {
  constructor(url) {
    this.url = url;
    this.id = 0;
    this.pending = new Map();
  }

  async open() {
    this.socket = new WebSocket(this.url);
    await new Promise((resolveOpen, reject) => {
      this.socket.addEventListener('open', resolveOpen, { once: true });
      this.socket.addEventListener('error', reject, { once: true });
    });
    this.socket.addEventListener('message', (event) => {
      const message = JSON.parse(String(event.data));
      if (!message.id || !this.pending.has(message.id)) return;
      const { resolve: resolveCall, reject } = this.pending.get(message.id);
      this.pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolveCall(message.result || {});
    });
    return this;
  }

  send(method, params = {}) {
    const id = ++this.id;
    return new Promise((resolveCall, reject) => {
      this.pending.set(id, { resolve: resolveCall, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    this.socket?.close();
  }
}

const sleep = (milliseconds) => new Promise((resolveSleep) => setTimeout(resolveSleep, milliseconds));

async function waitForJson(path, attempts = 60) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const response = await fetch(`http://127.0.0.1:${debugPort}${path}`);
      if (response.ok) return response.json();
    } catch {}
    await sleep(250);
  }
  throw new Error('Chrome DevTools did not become ready');
}

async function createPage() {
  const version = await waitForJson('/json/version');
  const browser = await new CdpClient(version.webSocketDebuggerUrl).open();
  const { targetId } = await browser.send('Target.createTarget', { url: 'about:blank' });
  const targets = await waitForJson('/json/list');
  const target = targets.find((item) => item.id === targetId);
  if (!target?.webSocketDebuggerUrl) throw new Error('Page target was not found');
  const page = await new CdpClient(target.webSocketDebuggerUrl).open();
  await page.send('Page.enable');
  await page.send('Runtime.enable');
  return { browser, page, targetId };
}

async function screenshot({ url, file, width, height, mobile = false, prepare, selector }) {
  const { browser, page, targetId } = await createPage();
  try {
    await page.send('Emulation.setDeviceMetricsOverride', {
      width,
      height,
      deviceScaleFactor: mobile ? 2 : 1,
      mobile,
      screenWidth: width,
      screenHeight: height,
    });
    await page.send('Page.navigate', { url });
    await sleep(6000);
    if (prepare) {
      await page.send('Runtime.evaluate', { expression: `(${prepare.toString()})()`, awaitPromise: true });
      await sleep(2500);
      await page.send('Runtime.evaluate', {
        expression: `(() => {
          const closeButton = Array.from(document.querySelectorAll('button')).find((button) =>
            /我知道了|关闭|close/i.test(button.textContent || button.getAttribute('aria-label') || '')
          );
          if (closeButton) closeButton.click();
        })()`,
      });
      await sleep(1200);
    }
    let clip;
    if (selector) {
      const { result } = await page.send('Runtime.evaluate', {
        expression: `(() => {
          const element = document.querySelector(${JSON.stringify(selector)});
          if (!element) return null;
          const rect = element.getBoundingClientRect();
          return { x: Math.max(0, rect.x - 16), y: Math.max(0, rect.y - 16), width: rect.width + 32, height: rect.height + 32 };
        })()`,
        returnByValue: true,
      });
      if (result.value) clip = { ...result.value, scale: 1 };
    }
    const { data } = await page.send('Page.captureScreenshot', {
      format: 'png',
      fromSurface: true,
      captureBeyondViewport: Boolean(clip),
      ...(clip ? { clip } : {}),
    });
    await writeFile(resolve(outputDir, file), Buffer.from(data, 'base64'));
    process.stdout.write(`captured ${file}\n`);
  } finally {
    await browser.send('Target.closeTarget', { targetId }).catch(() => {});
    page.close();
    browser.close();
  }
}

await mkdir(outputDir, { recursive: true });
const chrome = spawn(chromePath, [
  '--headless=new',
  '--disable-gpu',
  '--no-first-run',
  '--no-default-browser-check',
  '--hide-scrollbars',
  `--remote-debugging-port=${debugPort}`,
  `--user-data-dir=${profileDir}`,
  'about:blank',
], { stdio: 'ignore' });

try {
  await waitForJson('/json/version');
  const enablePanelCard = function () {
    localStorage.setItem('auth_data', 'documentation-preview');
    const old = document.getElementById('xboard-ai-account-store-card');
    if (old) old.remove();
    const card = document.createElement('a');
    card.id = 'xboard-ai-account-store-card';
    card.className = 'xboard-ai-store-card xboard-ai-store-float';
    card.href = '#';
    card.innerHTML = [
      '<span class="xboard-ai-store-icon" aria-hidden="true"><img src="/assets/go-store-logo.png" alt=""></span>',
      '<span class="xboard-ai-store-copy"><span class="xboard-ai-store-kicker">跨境速云精选服务</span><strong>AI工具 / 账号商店</strong><small>GPT · Gemini · Telegram · Google</small></span>',
      '<span class="xboard-ai-store-action">进入商店<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"></path></svg></span>'
    ].join('');
    document.body.appendChild(card);
  };
  await screenshot({ url: storeUrl, file: 'server-dujiao-desktop.png', width: 1440, height: 900 });
  await screenshot({ url: panelUrl, file: 'server-xboard-desktop.png', width: 1440, height: 900, prepare: enablePanelCard, selector: '#xboard-ai-account-store-card' });
  await screenshot({ url: storeUrl, file: 'server-dujiao-mobile.png', width: 390, height: 844, mobile: true });
  await screenshot({ url: panelUrl, file: 'server-xboard-mobile.png', width: 390, height: 844, mobile: true, prepare: enablePanelCard, selector: '#xboard-ai-account-store-card' });
} finally {
  chrome.kill();
}
