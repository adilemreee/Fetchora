// Fetchora - Background Script (Manifest V2)

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action === 'interceptDownload') {
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
});
