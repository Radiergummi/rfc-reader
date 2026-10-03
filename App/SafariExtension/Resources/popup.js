import { redirects, resolve, setRedirects, siteOf } from "./shared.js";

const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
const { link } = await resolve(tab?.url);

// "Open in RFC Reader", at the page's section.
const openButton = document.getElementById("open");
openButton.disabled = !link;
openButton.addEventListener("click", async () => {
  await browser.tabs.update(tab.id, { url: link });
  window.close();
});

// The per-site opt-in, offered on the sites the extension reads.
const site = tab?.url ? siteOf(tab.url) : null;
if (site) {
  const toggle = document.getElementById("redirect");
  document.getElementById("site").textContent = site;
  document.getElementById("redirect-row").hidden = false;
  toggle.checked = await redirects(site);
  toggle.addEventListener("change", () => setRedirects(site, toggle.checked));
}
