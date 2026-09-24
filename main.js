// Points every download button at the latest release's .dmg, with its version and size.
// The HTML already links a working .dmg, so if this request fails nothing breaks.
(function () {
  var buttons = document.querySelectorAll("[data-download]");
  if (!buttons.length || !window.fetch) return;

  var es = document.documentElement.lang === "es";

  fetch("https://api.github.com/repos/charlysole/video-grabber/releases/latest", {
    headers: { Accept: "application/vnd.github+json" }
  })
    .then(function (r) { return r.ok ? r.json() : null; })
    .then(function (release) {
      if (!release || !release.assets) return;
      var dmg = release.assets.find(function (a) { return /\.dmg$/i.test(a.name); });
      if (!dmg) return;
      var version = String(release.tag_name || "").replace(/^v/, "");
      var mb = Math.round(dmg.size / 1048576);
      var detail = es
        ? "Versión " + version + ", " + mb + " MB"
        : "Version " + version + ", " + mb + " MB";
      buttons.forEach(function (b) {
        b.href = dmg.browser_download_url;
        var small = b.querySelector("span");
        if (small) small.textContent = detail;
      });
    })
    .catch(function () {});
})();
