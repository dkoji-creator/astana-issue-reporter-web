// R10 (final): node tests/measure_r10.js  -- start server.py first
// R10: time until 100+ markers are on the screen, logged in, phone 360 px, Fast 4G, cache off
const { chromium } = require("playwright");
(async () => {
  const browser = await chromium.launch();
  const runs = [];
  for (let i = 0; i < 3; i++) {
    const ctx = await browser.newContext({ viewport: { width: 360, height: 740 }, deviceScaleFactor: 2 });
    const page = await ctx.newPage();
    await page.goto("http://127.0.0.1:8000");
    await page.fill("#authEmail", "user2@example.kz"); await page.fill("#authPassword", "Pass1234!");
    await page.click("#authSubmit"); await page.waitForSelector(".marker");
    const cdp = await ctx.newCDPSession(page);
    await cdp.send("Network.enable");
    await cdp.send("Network.setCacheDisabled", { cacheDisabled: true });
    await cdp.send("Network.emulateNetworkConditions", { offline: false, latency: 165,
      downloadThroughput: 9e6 / 8 * 0.9, uploadThroughput: 1.5e6 / 8 * 0.9 });
    let bytes = 0;
    cdp.on("Network.loadingFinished", (e) => { bytes += e.encodedDataLength; });
    const t0 = Date.now();
    await page.reload();
    await page.waitForFunction(() => document.querySelectorAll(".marker").length >= 100);
    const t = Date.now() - t0;
    const n = await page.evaluate(() => document.querySelectorAll(".marker").length);
    await page.waitForLoadState("networkidle");
    runs.push(t);
    console.log(`run ${i + 1}: ${n} markers visible after ${(t / 1000).toFixed(2)} s, ${(bytes / 1024).toFixed(0)} KB transferred`);
    await ctx.close();
  }
  console.log(`mean ${(runs.reduce((a, b) => a + b) / runs.length / 1000).toFixed(2)} s`);
  await browser.close();
})();
