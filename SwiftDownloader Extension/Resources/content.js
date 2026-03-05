// Fetchora - Content Script
// Intercepts download link clicks and sends them to the native app

(function () {
  "use strict";

  function getFileName(url) {
    try {
      const pathname = new URL(url).pathname;
      const parts = pathname.split("/");
      return decodeURIComponent(parts[parts.length - 1]) || "download";
    } catch (e) {
      return "download";
    }
  }

  // Web page extensions that should NOT be intercepted
  const PAGE_EXTENSIONS = new Set([
    "html", "htm", "xhtml", "shtml",
    "php", "asp", "aspx", "jsp", "jspx",
    "cgi", "pl", "py", "rb", "cfm",
    "do", "action", "xsp",
  ]);

  function isDownloadLink(url) {
    try {
      const pathname = new URL(url).pathname;
      const lastSegment = pathname.split("/").pop();
      if (!lastSegment || !lastSegment.includes(".")) return false;
      const ext = lastSegment.split(".").pop().toLowerCase();
      // Exclude web page extensions
      return ext && !PAGE_EXTENSIONS.has(ext);
    } catch (e) {
      return false;
    }
  }

  // Listen for clicks on links with download attribute or file extensions
  document.addEventListener(
    "click",
    function (event) {
      const link = event.target.closest("a[href]");
      if (!link) return;

      const url = link.href;
      if (!url || url.startsWith("javascript:") || url.startsWith("#")) return;

      // Intercept if link has download attribute OR URL points to a downloadable file
      const hasDownloadAttr = link.hasAttribute("download");
      if (!hasDownloadAttr && !isDownloadLink(url)) return;

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

  // Listen for messages from background script (context menu / downloads API)
  browser.runtime.onMessage.addListener((message) => {
    if (message.action === "showNotification" && message.fileName) {
      showInterceptNotification(message.fileName);
    }
  });

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
