// Records the 10-second "How to report an issue" clip from the running prototype.
// Own work: a screen recording of our own app with a test account (no real personal data).
// Run: start server.py, then  node media_src/record_howto.js
// Output: media_src/howto_frames/ (PNG frames + frames.txt), turned into video by build_media.sh
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const FRAMES = path.join(__dirname, "howto_frames");

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: { width: 360, height: 640 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
  });
  const page = await context.newPage();
  const pause = (ms) => page.waitForTimeout(ms);
  await page.goto("http://127.0.0.1:8000/");

  // take screenshots (720 x 1280 on a 2x phone screen) again and again while the steps run
  fs.rmSync(FRAMES, { recursive: true, force: true });
  fs.mkdirSync(FRAMES);
  const frames = [];
  let recording = true;
  const recorder = (async () => {
    while (recording) {
      const name = "f" + String(frames.length).padStart(4, "0") + ".png";
      const time = Date.now() / 1000;
      await page.screenshot({ path: path.join(FRAMES, name), animations: "allow", caret: "initial" });
      frames.push({ name, time });
    }
  })();
  await pause(400);
  await page.fill("#authEmail", "user2@example.kz");
  await page.type("#authPassword", "Pass1234!", { delay: 40 });
  await page.click("#authSubmit");
  await pause(500);
  await page.evaluate(() => window.scrollTo({ top: 60, behavior: "smooth" }));
  await pause(300);
  // find a free spot on the map (not on a marker) and tap it
  const spot = await page.evaluate(() => {
    const box = document.querySelector("#map").getBoundingClientRect();
    for (let fy = 0.35; fy < 0.9; fy += 0.03) {
      for (let fx = 0.3; fx < 0.8; fx += 0.03) {
        const x = box.left + box.width * fx, y = box.top + box.height * fy;
        if (document.elementFromPoint(x, y) === document.querySelector("#map > img")) return { x, y };
      }
    }
  });
  await page.mouse.click(spot.x, spot.y);
  await pause(800);
  await page.evaluate(() => document.querySelector("#cat").scrollIntoView({ behavior: "smooth", block: "center" }));
  await pause(500);
  await page.selectOption("#cat", "2");
  await pause(300);
  await page.type("#desc", "Streetlight is off near the bus stop", { delay: 45 });
  await pause(300);
  await page.evaluate(() => document.querySelector("#send").scrollIntoView({ behavior: "smooth", block: "center" }));
  await pause(300);
  await page.click("#send");
  await pause(1800);
  recording = false;
  await recorder;
  const end = Date.now() / 1000;
  // list for ffmpeg: each frame stays on screen until the next one arrives
  let list = "";
  frames.forEach((f, i) => {
    const next = i + 1 < frames.length ? frames[i + 1].time : end;
    list += `file '${f.name}'\nduration ${(next - f.time).toFixed(3)}\n`;
  });
  list += `file '${frames[frames.length - 1].name}'\n`;
  fs.writeFileSync(path.join(FRAMES, "frames.txt"), list);
  console.log(frames.length + " frames, " + (end - frames[0].time).toFixed(1) + " s");
  await browser.close();
})();
