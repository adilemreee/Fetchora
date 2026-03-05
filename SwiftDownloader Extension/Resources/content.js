// Fetchora - Content Script
// Intercepts download link clicks and sends them to the native app

(function () {
  "use strict";

  // File extensions we want to intercept
  const DOWNLOAD_EXTENSIONS = new Set([
    "zip",
    "rar",
    "7z",
    "tar",
    "gz",
    "bz2",
    "xz",
    "dmg",
    "pkg",
    "iso",
    "img",
    "pdf",
    "doc",
    "docx",
    "xls",
    "xlsx",
    "ppt",
    "pptx",
    "mp4",
    "mkv",
    "avi",
    "mov",
    "wmv",
    "flv",
    "webm",
    "m4v",
    "mp3",
    "wav",
    "flac",
    "aac",
    "ogg",
    "wma",
    "m4a",
    "exe",
    "msi",
    "deb",
    "rpm",
    "torrent",
  ]);

  function getExtension(url) {
    try {
      const pathname = new URL(url).pathname;
      const parts = pathname.split(".");
      if (parts.length > 1) {
        return parts.pop().toLowerCase().split("?")[0];
      }
    } catch (e) {}
    return "";
  }

  function isDownloadLink(url) {
    const ext = getExtension(url);
    return DOWNLOAD_EXTENSIONS.has(ext);
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

  // Listen for clicks on links
  document.addEventListener(
    "click",
    function (event) {
      const link = event.target.closest("a[href]");
      if (!link) return;

      const url = link.href;
      if (!url || !isDownloadLink(url)) return;

      // Check if link has download attribute
      const hasDownloadAttr = link.hasAttribute("download");

      // Intercept the download
      event.preventDefault();
      event.stopPropagation();

      const fileName = link.download || getFileName(url);

      // Send to background script
      browser.runtime.sendMessage({
        action: "interceptDownload",
        url: url,
        fileName: fileName,
        pageUrl: window.location.href,
        pageTitle: document.title,
      });

      // Show notification on page
      showInterceptNotification(fileName);
    },
    true,
  );

  // Also handle download attribute links
  document.addEventListener(
    "click",
    function (event) {
      const link = event.target.closest("a[download]");
      if (!link) return;

      const url = link.href;
      if (!url) return;

      event.preventDefault();
      event.stopPropagation();

      const fileName = link.download || getFileName(url);

      browser.runtime.sendMessage({
        action: "interceptDownload",
        url: url,
        fileName: fileName,
        pageUrl: window.location.href,
        pageTitle: document.title,
      });

      showInterceptNotification(fileName);
    },
    true,
  );

  function showInterceptNotification(fileName) {
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
            animation: slideIn 0.3s ease-out;
        `;
    notification.innerHTML = `
            <div style="width:32px;height:32px;background:rgba(79,142,247,0.15);border-radius:8px;display:flex;align-items:center;justify-content:center;">
                <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M8 2v8m0 0l3-3m-3 3L5 7M3 13h10" stroke="#4F8EF7" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
            </div>
            <div>
                <div style="font-weight:600;margin-bottom:2px;">Fetchora</div>
                <div style="opacity:0.7;font-size:11px;">${fileName}</div>
            </div>
        `;

    const style = document.createElement("style");
    style.textContent = `
            @keyframes slideIn {
                from { transform: translateX(100%); opacity: 0; }
                to { transform: translateX(0); opacity: 1; }
            }
        `;
    document.head.appendChild(style);
    document.body.appendChild(notification);

    setTimeout(() => {
      notification.style.animation = "slideIn 0.3s ease-in reverse";
      setTimeout(() => notification.remove(), 300);
    }, 3000);
  }
})();
