// Fetchora - Popup Script

document.addEventListener('DOMContentLoaded', () => {
    const statusEl = document.getElementById('status');
    const statusDot = statusEl.querySelector('.status-dot');
    const statusText = statusEl.querySelector('.status-text');
    const openAppBtn = document.getElementById('openApp');
    const interceptToggle = document.getElementById('interceptToggle');
    const toggleDesc = document.getElementById('toggleDesc');
    const footerText = document.getElementById('footerText');

    // Load saved intercept state (default: enabled)
    browser.storage.local.get('interceptEnabled', (result) => {
        const enabled = result.interceptEnabled !== false;
        interceptToggle.checked = enabled;
        updateToggleUI(enabled);
    });

    // Toggle change handler
    interceptToggle.addEventListener('change', () => {
        const enabled = interceptToggle.checked;
        browser.storage.local.set({ interceptEnabled: enabled });
        updateToggleUI(enabled);
    });

    function updateToggleUI(enabled) {
        if (enabled) {
            toggleDesc.textContent = 'Downloads are intercepted by Fetchora';
            toggleDesc.classList.remove('disabled');
            footerText.textContent = 'v1.0 \u2022 Intercepting downloads';
        } else {
            toggleDesc.textContent = 'Download interception is paused';
            toggleDesc.classList.add('disabled');
            footerText.textContent = 'v1.0 \u2022 Interception paused';
        }
    }

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

    // Open app button — launch the main app via native message
    openAppBtn.addEventListener('click', () => {
        browser.runtime.sendMessage({ action: 'openApp' }, (response) => {
            window.close();
        });
    });
});
