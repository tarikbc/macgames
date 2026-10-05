// Points every Download button at the newest release's disk image and shows its version.
// Without the GitHub API, the buttons keep linking to the release page.
(async () => {
  try {
    const response = await fetch("https://api.github.com/repos/tarikbc/macgames/releases/latest",
                                 { headers: { Accept: "application/vnd.github+json" } });
    if (!response.ok) return;
    const release = await response.json();
    const dmg = (release.assets || []).find((asset) => asset.name.endsWith(".dmg"));
    if (dmg) document.querySelectorAll("[data-download]").forEach((link) => { link.href = dmg.browser_download_url; });
    const version = (release.tag_name || "").replace(/^v/, "");
    if (version) document.querySelectorAll("[data-version]").forEach((el) => { el.textContent = `Version ${version}.`; });
  } catch (_) {
    // The release page link stays.
  }
})();
