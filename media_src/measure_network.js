// Part B2: loads a page with the cache disabled and "Fast 4G" throttling (the same numbers as
// the Chrome DevTools preset) and prints total transferred size, number of requests and load time.
// Run: start server.py, then  node media_src/measure_network.js /before   and   node media_src/measure_network.js /
const { chromium } = require("playwright");

(async () => {
  const url = "http://127.0.0.1:8000" + (process.argv[2] || "/");
  const mobile = process.argv[3] === "mobile";
  const browser = await chromium.launch();
  const page = await browser.newPage(mobile
    ? { viewport: { width: 360, height: 740 }, deviceScaleFactor: 2 }
    : { viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 });
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Network.enable");
  await cdp.send("Network.setCacheDisabled", { cacheDisabled: true });
  await cdp.send("Network.emulateNetworkConditions", {
    offline: false, latency: 165,
    downloadThroughput: 9 * 1000 * 1000 / 8 * 0.9, uploadThroughput: 1.5 * 1000 * 1000 / 8 * 0.9,
  });
  const urls = {}, sizes = {};
  let last = 0;
  // data: URLs are the browser's own video-control icons, not requests to our server
  cdp.on("Network.requestWillBeSent", (e) => { if (!e.request.url.startsWith("data:")) urls[e.requestId] = e.request.url; });
  cdp.on("Network.loadingFinished", (e) => { sizes[e.requestId] = e.encodedDataLength; last = Date.now(); });
  const start = Date.now();
  await page.goto(url, { waitUntil: "load" });
  const load = Date.now() - start;
  await page.waitForLoadState("networkidle");
  const finish = last - start;
  let total = 0;
  console.log(`${url}  (${mobile ? "phone 360 px, 2x screen" : "laptop 1280 px"}, Fast 4G, cache disabled)`);
  for (const id of Object.keys(urls)) {
    total += sizes[id] || 0;
    console.log(String(Math.round((sizes[id] || 0) / 1024)).padStart(6), "KB ", urls[id].replace("http://127.0.0.1:8000", ""));
  }
  console.log(`requests: ${Object.keys(urls).length}, transferred: ${(total / 1024).toFixed(0)} KB, ` +
              `Load: ${load} ms, Finish: ${finish} ms`);
  await browser.close();
})();
