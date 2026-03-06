// Fetchora - Background Script (Manifest V2)

const interceptionConfig = {
    urlRules: [],
};

function normalizeDomain(rule) {
    return String(rule || '')
        .trim()
        .toLowerCase()
        .replace(/^https?:\/\//, '')
        .replace(/^www\./, '')
        .replace(/\/+$/, '');
}

function isBrowserManagedURL(url) {
    return typeof url === 'string' && (url.startsWith('blob:') || url.startsWith('data:'));
}

function refreshInterceptionConfig(callback) {
    browser.runtime.sendNativeMessage(
        'application.id',
        { action: 'getInterceptionConfig' },
        (response) => {
            if (response && response.status === 'ok' && Array.isArray(response.urlRules)) {
                interceptionConfig.urlRules = response.urlRules.map(normalizeDomain).filter(Boolean);
            }

            if (callback) {
                callback(interceptionConfig);
            }
        }
    );
}

refreshInterceptionConfig();
setInterval(refreshInterceptionConfig, 30000);

// ── Context Menu: "Download with Fetchora" on links ──
try {
    browser.contextMenus.create({
        id: 'fetchora-download-link',
        title: 'Download with Fetchora',
        contexts: ['link']
    });
} catch (e) {
    console.log('[Fetchora] contextMenus not available:', e);
}

try {
    browser.contextMenus.onClicked.addListener((info, tab) => {
        if (info.menuItemId === 'fetchora-download-link' && info.linkUrl) {
            const url = info.linkUrl;
            if (isBrowserManagedURL(url)) {
                // Ask the content script to fetch the blob data
                if (tab && tab.id) {
                    let fileName = 'download';
                    browser.tabs.sendMessage(tab.id, {
                        action: 'fetchBlobForContextMenu',
                        blobUrl: url,
                        fileName: fileName
                    });
                }
                return;
            }

            let fileName = 'download';
            try {
                const pathname = new URL(url).pathname;
                const parts = pathname.split('/');
                fileName = decodeURIComponent(parts[parts.length - 1]) || 'download';
            } catch (e) {}

            browser.runtime.sendNativeMessage(
                'application.id',
                {
                    action: 'newDownload',
                    url: url,
                    fileName: fileName,
                    pageUrl: (tab && tab.url) || '',
                    pageTitle: (tab && tab.title) || ''
                },
                (response) => {
                    console.log('[Fetchora] Context menu download response:', response);
                }
            );

            // Show notification in the active tab
            if (tab && tab.id) {
                browser.tabs.sendMessage(tab.id, {
                    action: 'showNotification',
                    fileName: fileName
                });
            }
        }
    });
} catch (e) {
    console.log('[Fetchora] contextMenus.onClicked not available:', e);
}

// ── Intercept downloads started by Safari ──
try {
    browser.downloads.onCreated.addListener((downloadItem) => {
        if (downloadItem && downloadItem.url) {
            // Check if interception is enabled
            browser.storage.local.get('interceptEnabled', (result) => {
                if (result.interceptEnabled === false) return;

                const url = downloadItem.url;
                if (isBrowserManagedURL(url)) return;

                const fileName = downloadItem.filename
                    ? downloadItem.filename.split('/').pop()
                    : 'download';

                // Cancel Safari's own download
                try {
                    browser.downloads.cancel(downloadItem.id);
                    browser.downloads.erase({ id: downloadItem.id });
                } catch (e) {
                    console.log('[Fetchora] Could not cancel native download:', e);
                }

                // Send to Fetchora
                browser.runtime.sendNativeMessage(
                    'application.id',
                    {
                        action: 'newDownload',
                        url: url,
                        fileName: fileName,
                        pageUrl: downloadItem.referrer || '',
                        pageTitle: ''
                    },
                    (response) => {
                        console.log('[Fetchora] Download intercept response:', response);
                    }
                );

                // Show notification in the active tab
                browser.tabs.query({ active: true, currentWindow: true }, (tabs) => {
                    if (tabs && tabs[0] && tabs[0].id) {
                        browser.tabs.sendMessage(tabs[0].id, {
                            action: 'showNotification',
                            fileName: fileName
                        });
                    }
                });
            });
        }
    });
} catch (e) {
    console.log('[Fetchora] downloads API not available:', e);
}

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action === 'interceptDownload') {
        if (isBrowserManagedURL(message.url)) {
            console.log('[Fetchora] Skipping browser-managed URL intercept:', message.url);
            return;
        }

        browser.runtime.sendNativeMessage(
            'application.id',
            {
                action: 'newDownload',
                url: message.url,
                fileName: message.fileName,
                pageUrl: message.pageUrl || '',
                pageTitle: message.pageTitle || ''
            },
            (response) => {
                console.log('[Fetchora] Response:', response);
            }
        );
        return true;
    }

    if (message.action === 'interceptBlobDownload') {
        browser.runtime.sendNativeMessage(
            'application.id',
            {
                action: 'blobDownload',
                fileName: message.fileName || 'download',
                mimeType: message.mimeType || 'application/octet-stream',
                base64Data: message.base64Data,
                pageUrl: message.pageUrl || '',
                pageTitle: message.pageTitle || ''
            },
            (response) => {
                console.log('[Fetchora] Blob download response:', response);
            }
        );
        return true;
    }

    if (message.action === 'ping') {
        browser.runtime.sendNativeMessage(
            'application.id',
            { action: 'ping' },
            (response) => {
                sendResponse(response || { status: 'error' });
            }
        );
        return true;
    }

    if (message.action === 'getInterceptionConfig') {
        refreshInterceptionConfig((config) => {
            sendResponse({
                status: 'ok',
                urlRules: config.urlRules,
            });
        });
        return true;
    }

    if (message.action === 'openApp') {
        browser.runtime.sendNativeMessage(
            'application.id',
            { action: 'openApp' },
            (response) => {
                sendResponse(response || { status: 'ok' });
            }
        );
        return true;
    }
});
