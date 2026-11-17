// Run with Playwright Core on NODE_PATH. Arguments: app-managed extension folder, browser executable(s).
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {chromium} = require(process.env.VIDISTUDIO_PLAYWRIGHT_CORE || "playwright-core");
const [payload, ...browsers] = process.argv.slice(2);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function check(browser) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "vidi-extension-update-"));
  const folder = path.join(root, "BrowserExtension");
  fs.cpSync(payload, folder, {recursive: true});
  const file = path.join(folder, "manifest.json");
  const current = JSON.parse(fs.readFileSync(file));
  const previous = "0.0.1";
  fs.writeFileSync(file, JSON.stringify({...current, version: previous}));
  let context;
  try {
    context = await chromium.launchPersistentContext(path.join(root, "profile"), {
      executablePath: browser, headless: false, ignoreDefaultArgs: ["--disable-extensions"],
      args: ["--enable-unsafe-extension-debugging", "--no-first-run"]
    });
    // CDP can bootstrap an unpacked extension without Developer mode. A normal
    // local installation enables it first, and Chrome enforces it on reload.
    const manager = context.pages()[0];
    const edge = /edge/i.test(path.basename(browser));
    await manager.goto(edge ? "edge://extensions/" : "chrome://extensions/");
    if (!edge) {
      const toggle = manager.locator("#devMode");
      if (!await toggle.isChecked()) await toggle.click();
      assert.ok(await toggle.isChecked());
    }
    const session = await context.browser().newBrowserCDPSession();
    const {id} = await session.send("Extensions.loadUnpacked", {path: folder});
    const installed = async () => (await session.send("Extensions.getExtensions")).extensions.find(e => e.id === id);
    assert.equal((await installed()).version, previous);
    const worker = context.serviceWorkers().find(w => w.url().endsWith("/local-worker.js"))
      || await context.waitForEvent("serviceworker", {timeout: 15000});
    const status = await worker.evaluate(async () => ({
      version: chrome.runtime.getManifest().version, alarms: await chrome.alarms.getAll()
    }));
    console.log(path.basename(browser), "initial worker", status);
    const page = context.pages()[0];
    // Leave the original worker idle long enough for MV3 to suspend it.
    await sleep(35000);
    fs.copyFileSync(path.join(payload, "manifest.json"), file + ".new");
    fs.renameSync(file + ".new", file);
    const deadline = Date.now() + 100000;
    while ((await installed())?.version !== current.version && Date.now() < deadline) await sleep(1000);
    assert.equal((await installed()).version, current.version);
    assert.equal(page.isClosed(), false);
    console.log(path.basename(browser), "automatically loaded", current.version, "with the same ID and the original tab open");
  } finally {
    if (context) await context.close();
    fs.rmSync(root, {recursive: true, force: true, maxRetries: 5, retryDelay: 200});
  }
}
if (!payload || !browsers.length) throw new Error("Supply the app-managed folder and at least one browser executable");
Promise.allSettled(browsers.map(check)).then(results => {
  for (const r of results) if (r.status === "rejected") {console.error(r.reason); process.exitCode = 1;}
});
