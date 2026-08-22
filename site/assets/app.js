// LibraScan site — language toggle + a few config-driven slots. No framework, no tracking.
(function () {
  const CONFIG = {
    // Fill in once the app is live on the App Store, e.g. "https://apps.apple.com/app/id0000000000".
    appStoreURL: "",
    macVersion: "1.0",
    macDownloadURL: "/dl/LibraScan-1.0.dmg?b=3", // new path/query per Mac build: the zone edge-caches by full URL
    macSHA256: "2248be12c450768789bef037acd34b47e88646e81e03aa063958b8c5bc407f05",
    supportEmail: "me@libra.wiki",
  };

  const SUPPORTED = ["zh-Hans", "en"];
  const KEY = "librascan.lang";

  function detect() {
    const q = new URLSearchParams(location.search).get("lang");
    if (q && SUPPORTED.includes(q)) return q;
    const saved = localStorage.getItem(KEY);
    if (saved && SUPPORTED.includes(saved)) return saved;
    const langs = navigator.languages || [navigator.language || "en"];
    return langs.some((l) => /^zh\b/i.test(l)) ? "zh-Hans" : "en";
  }

  function apply(lang) {
    document.documentElement.lang = lang;
    document.querySelectorAll(".l10n").forEach((el) => {
      el.hidden = el.getAttribute("lang") !== lang;
    });
    const title = document.querySelector(`.l10n[lang="${lang}"]`)?.dataset.title;
    if (title) document.title = title;
  }

  function fill() {
    document.querySelectorAll("[data-mail]").forEach((a) => {
      a.href = "mailto:" + CONFIG.supportEmail;
      if (!a.textContent.trim()) a.textContent = CONFIG.supportEmail;
    });
    document.querySelectorAll("[data-mac-version]").forEach((el) => (el.textContent = CONFIG.macVersion));
    document.querySelectorAll("[data-mac-sha]").forEach((el) => (el.textContent = CONFIG.macSHA256));
    document.querySelectorAll("[data-mac-download]").forEach((a) => (a.href = CONFIG.macDownloadURL));
    // Apple's badge may only appear linked to the product page, so it stays
    // hidden until appStoreURL is filled in; a plain "coming soon" pill shows meanwhile.
    document.querySelectorAll("[data-app-store]").forEach((a) => {
      if (CONFIG.appStoreURL) {
        a.href = CONFIG.appStoreURL;
        a.hidden = false;
      } else {
        a.removeAttribute("href");
        a.hidden = true;
      }
    });
    document.querySelectorAll("[data-app-store-soon]").forEach((el) => {
      el.hidden = Boolean(CONFIG.appStoreURL);
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    fill();
    apply(detect());
    document.querySelectorAll("[data-set-lang]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const lang = btn.dataset.setLang;
        localStorage.setItem(KEY, lang);
        apply(lang);
        history.replaceState(null, "", location.pathname);
      });
    });
  });
})();
