import { redirects, resolve, setRedirects, siteOf } from "./shared.js";

// The sites the extension reads, as the manifest names them.
const origins = browser.runtime.getManifest().host_permissions;

const grantButton = document.getElementById("grant");
const openButton = document.getElementById("open");
const redirectRow = document.getElementById("redirect-row");
const toggle = document.getElementById("redirect");

// Access to the three sites, asked for here so that the popup, which opens on any
// page, is where it is granted. The request is the click's first call, so Safari
// counts it as the user's gesture.
grantButton.onclick = () => {
  browser.permissions.request({ origins }).then(render);
};

// Drawn once on opening and again after access is granted, when the tab's URL,
// undefined until then, can be read.
async function render() {
  grantButton.hidden = await browser.permissions.contains({ origins });

  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  const { link } = await resolve(tab?.url);

  // "Open in RFC Reader", at the page's section.
  openButton.disabled = !link;
  openButton.onclick = async () => {
    await browser.tabs.update(tab.id, { url: link });
    window.close();
  };

  // The per-site opt-in, offered on the sites the extension reads.
  const site = siteOf(tab?.url);
  redirectRow.hidden = !site;
  if (site) {
    document.getElementById("site").textContent = site;
    toggle.checked = await redirects(site);
    toggle.onchange = () => setRedirects(site, toggle.checked);
  }
}

await render();
