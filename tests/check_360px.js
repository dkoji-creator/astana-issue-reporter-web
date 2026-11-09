// Success criterion 2 (works on a 360 px wide screen), checked automatically.
// Needs Node.js with Playwright. Start server.py, then:  node tests/check_360px.js
// It logs in as a resident and as the admin on a 360 x 740 screen and checks that nothing is
// wider than the screen and that every button is at least 44 px high (WCAG 2.5.5 / Stage 1 D).
const { chromium } = require("playwright");
const BASE = process.argv[2] || "http://127.0.0.1:8000";

(async () => {
  const browser = await chromium.launch();
  let failed = 0;
  for (const email of ["user2@example.kz", "user1@example.kz"]) {
    const page = await browser.newPage({ viewport: { width: 360, height: 740 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
    await page.goto(BASE);
    await page.fill("#authEmail", email);
    await page.fill("#authPassword", "Pass1234!");
    await page.click("#authSubmit");
    await page.waitForSelector(".marker");
    const result = await page.evaluate(() => {
      const width = document.documentElement.scrollWidth;
      const small = [...document.querySelectorAll("button, select, .photo-buttons label")]
        .filter((el) => el.offsetParent !== null && !el.classList.contains("marker"))
        .filter((el) => el.getBoundingClientRect().height < 44)
        .map((el) => (el.id || el.textContent.trim()).slice(0, 30));
      return { width, markers: document.querySelectorAll(".marker").length, small };
    });
    const ok = result.width <= 360 && result.small.length === 0;
    if (!ok) failed++;
    console.log(`${email}: page width ${result.width} px, ${result.markers} markers, ` +
      `buttons under 44 px: ${result.small.length ? result.small.join(", ") : "none"} -> ${ok ? "MET" : "NOT MET"}`);
    await page.close();
  }
  await browser.close();
  process.exit(failed ? 1 : 0);
})();
