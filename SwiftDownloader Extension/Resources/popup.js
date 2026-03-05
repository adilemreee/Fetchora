// Fetchora - Popup Script

document.addEventListener('DOMContentLoaded', () => {
    const statusEl = document.getElementById('status');
    const statusDot = statusEl.querySelector('.status-dot');
    const statusText = statusEl.querySelector('.status-text');
    const openAppBtn = document.getElementById('openApp');

    // Check native app connection
    browser.runtime.sendMessage({ action: 'ping' }, (response) => {
        if (response && response.status === 'ok') {
            statusText.textContent = 'Connected';
            statusEl.classList.remove('error');
        } else {
            statusText.textContent = 'Not Connected';
            statusEl.classList.add('error');
        }
    });

    // Open app button
    openAppBtn.addEventListener('click', () => {
        browser.runtime.sendNativeMessage(
            'application.id',
            { action: 'ping' },
            () => {
                window.close();
            }
        );
    });
});
