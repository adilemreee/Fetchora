// Fetchora - Content Script
// Intercepts download link clicks and sends them to the native app

(function () {
  "use strict";

  // Downloadable file extensions — ONLY these trigger interception on click
  const DOWNLOAD_EXTENSIONS = new Set([
    // Archives
    "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "zst",
    // Disk images & installers
    "dmg", "pkg", "iso", "img", "exe", "msi", "deb", "rpm", "app", "appimage",
    // Documents
    "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtf", "csv", "epub",
    // Video
    "mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "ts",
    // Audio
    "mp3", "wav", "flac", "aac", "ogg", "wma", "m4a", "opus", "aiff",
    // Images (large/downloadable types)
    "psd", "ai", "sketch", "fig", "raw", "cr2", "nef", "tiff",
    // Fonts
    "ttf", "otf", "woff", "woff2",
    // Torrents
    "torrent", "magnet",
    // Data
    "sql", "db", "sqlite", "bak",
  ]);

  function getExtension(url) {
    try {
      const pathname = new URL(url).pathname;
      const lastSegment = pathname.split("/").pop();
      if (!lastSegment || !lastSegment.includes(".")) return "";
      return lastSegment.split(".").pop().toLowerCase().split("?")[0];
    } catch (e) {
      return "";
    }
  }

  function isDownloadableFile(url) {
    return DOWNLOAD_EXTENSIONS.has(getExtension(url));
  }

  function getFileName(url) {
    try {
      const pathname = new URL(url).pathname;
      const parts = pathname.split("/");
      return decodeURIComponent(parts[parts.length - 1]) || "download";
    } catch (e) {
      return "download";
    }
  }

  function interceptLink(url, fileName) {
    browser.runtime.sendMessage({
      action: "interceptDownload",
      url: url,
      fileName: fileName,
      pageUrl: window.location.href,
      pageTitle: document.title,
    });
    showInterceptNotification(fileName);
  }

  // Cache interception state for synchronous access in click handler
  let interceptEnabled = true;
  browser.storage.local.get("interceptEnabled", (result) => {
    interceptEnabled = result.interceptEnabled !== false;
  });
  browser.storage.onChanged.addListener((changes) => {
    if (changes.interceptEnabled) {
      interceptEnabled = changes.interceptEnabled.newValue !== false;
    }
  });

  // Listen for clicks on links
  document.addEventListener(
    "click",
    function (event) {
      if (!interceptEnabled) return;

      const link = event.target.closest("a[href]");
      if (!link) return;

      const url = link.href;
      if (!url || url.startsWith("javascript:") || url.startsWith("#") || url.startsWith("mailto:")) return;

      const hasDownloadAttr = link.hasAttribute("download");
      const isDownloadable = isDownloadableFile(url);

      // Only intercept: explicit download attribute OR known downloadable extension
      if (!hasDownloadAttr && !isDownloadable) return;

      event.preventDefault();
      event.stopPropagation();

      const fileName = link.download || getFileName(url);
      interceptLink(url, fileName);
    },
    true,
  );

  // Listen for messages from background script (context menu / downloads API)
  browser.runtime.onMessage.addListener((message) => {
    if (message.action === "showNotification" && message.fileName) {
      showInterceptNotification(message.fileName);
    }
  });

  // Inject animation style once
  let styleInjected = false;
  function ensureStyle() {
    if (styleInjected) return;
    styleInjected = true;
    const style = document.createElement("style");
    style.textContent = `
      @keyframes fetchora-slideIn {
        from { transform: translateX(100%); opacity: 0; }
        to { transform: translateX(0); opacity: 1; }
      }
      @keyframes fetchora-slideOut {
        from { transform: translateX(0); opacity: 1; }
        to { transform: translateX(100%); opacity: 0; }
      }
    `;
    document.head.appendChild(style);
  }

  function showInterceptNotification(fileName) {
    ensureStyle();

    // Sanitize fileName to prevent XSS
    const safeName = document.createElement("span");
    safeName.textContent = fileName;

    const notification = document.createElement("div");
    notification.style.cssText = `
      position: fixed;
      bottom: 20px;
      right: 20px;
      background: linear-gradient(135deg, #1A1B2E, #222339);
      color: #fff;
      padding: 14px 20px;
      border-radius: 12px;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 13px;
      z-index: 999999;
      box-shadow: 0 8px 32px rgba(0,0,0,0.4);
      display: flex;
      align-items: center;
      gap: 10px;
      border: 1px solid rgba(79, 142, 247, 0.3);
      animation: fetchora-slideIn 0.3s ease-out;
    `;

    // Build DOM safely (no innerHTML with user data)
    const iconWrap = document.createElement("div");
    iconWrap.style.cssText = "width:32px;height:32px;background:rgba(79,142,247,0.15);border-radius:8px;display:flex;align-items:center;justify-content:center;flex-shrink:0;";
    iconWrap.innerHTML = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none"><path d="M8 2v8m0 0l3-3m-3 3L5 7M3 13h10" stroke="#4F8EF7" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';

    const textWrap = document.createElement("div");
    const titleEl = document.createElement("div");
    titleEl.style.cssText = "font-weight:600;margin-bottom:2px;";
    titleEl.textContent = "Fetchora";
    const nameEl = document.createElement("div");
    nameEl.style.cssText = "opacity:0.7;font-size:11px;max-width:250px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;";
    nameEl.textContent = fileName;
    textWrap.appendChild(titleEl);
    textWrap.appendChild(nameEl);

    notification.appendChild(iconWrap);
    notification.appendChild(textWrap);
    document.body.appendChild(notification);

    setTimeout(() => {
      notification.style.animation = "fetchora-slideOut 0.3s ease-in forwards";
      setTimeout(() => notification.remove(), 300);
    }, 3000);
  }
})();
