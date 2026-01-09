// Onboarding carousel logic
let currentPanel = 1;
const totalPanels = 4;
// Expose currentPanel to Swift
window.currentPanel = currentPanel;
let permissionsGranted = {
    accessibility: false,
    screenRecording: false
};

let termsAccepted = false;
let emailValid = false;
let userEmail = '';

// Double control detection
let lastControlPressTime = 0;
const DOUBLE_CONTROL_THRESHOLD = 500; // milliseconds

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    // Set up keyboard navigation
    document.addEventListener('keydown', handleKeyboard);

    // Set up double control detection
    setupDoubleControlDetection();

    // Set up send button handler
    setupSendButton();

    // Update UI
    updateUI();
});

// Navigate to permissions page with error message
window.navigateToPermissionsWithError = function(errorMessage) {
    // Navigate to permissions page (panel 4)
    currentPanel = 4;
    updateUI();

    // Add error message to permissions page
    setTimeout(() => {
        const permissionsPanel = document.querySelector('.panel[data-panel="4"] .panel-content');
        if (permissionsPanel) {
            // Check if error message already exists
            let errorDiv = permissionsPanel.querySelector('.permissions-error');
            if (!errorDiv) {
                errorDiv = document.createElement('div');
                errorDiv.className = 'permissions-error';
                // Insert after the h1
                const h1 = permissionsPanel.querySelector('h1');
                if (h1 && h1.nextSibling) {
                    permissionsPanel.insertBefore(errorDiv, h1.nextSibling);
                } else {
                    permissionsPanel.insertBefore(errorDiv, permissionsPanel.firstChild);
                }
            }
            errorDiv.textContent = errorMessage;
        }
    }, 100);
};

// Navigation functions
function navigateNext() {
    if (currentPanel < totalPanels) {
        currentPanel++;
        updateUI();
        sendMessage('track', { event: 'panel_view', props: { panel: currentPanel } });
    } else if (currentPanel === totalPanels) {
        // Last panel - check if permissions are granted, terms accepted, and email provided
        if (permissionsGranted.accessibility && permissionsGranted.screenRecording && termsAccepted && emailValid) {
            completeOnboarding();
        }
    }
}

function navigateBack() {
    if (currentPanel > 1) {
        currentPanel--;
        updateUI();
        sendMessage('track', { event: 'panel_back', props: { panel: currentPanel } });
    }
}

function updateUI() {
    // Update exposed currentPanel for Swift
    window.currentPanel = currentPanel;

    // Update carousel position
    const carousel = document.getElementById('carousel');
    const offset = -(currentPanel - 1) * 100;
    carousel.style.transform = `translateX(${offset}%)`;

    // Update active panel
    document.querySelectorAll('.panel').forEach((panel, index) => {
        panel.classList.toggle('active', index + 1 === currentPanel);
    });

    // Update progress dots
    document.querySelectorAll('.dot').forEach((dot, index) => {
        dot.classList.toggle('active', index + 1 === currentPanel);
    });

    // Update navigation buttons
    const backButton = document.querySelector('.back-button');
    const continueButton = document.querySelector('.continue-button');

    // Show/hide back button
    backButton.style.display = currentPanel === 1 ? 'none' : 'block';

    // Update continue button
    if (currentPanel === 2) {
        // focus reply field
        // for some reason it messed up the UI if I do focus instantly
        setTimeout(function () {
                    document.getElementById('reply-field').focus();
        }, 1000)
    }
    if (currentPanel === totalPanels) {
        continueButton.textContent = 'Finish';
        continueButton.disabled = !(permissionsGranted.accessibility && permissionsGranted.screenRecording && termsAccepted && emailValid);
        // Update permission buttons when we arrive at permissions page
        updatePermissionButtons();
        // Notify Swift to start monitoring permissions
        sendMessage('startPermissionMonitoring', {});
    } else {
        continueButton.textContent = 'Continue';
        continueButton.disabled = false;
    }
}

// Double control detection
function setupDoubleControlDetection() {
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Control') {
            const now = Date.now();

            if (lastControlPressTime && (now - lastControlPressTime) <= DOUBLE_CONTROL_THRESHOLD) {
                // Double control detected!
                handleDoubleControl();
                lastControlPressTime = 0; // Reset
            } else {
                lastControlPressTime = now;
            }
        }
    });
}

function handleDoubleControl() {
    // Only handle on demo pages (2 and 3)
    if (currentPanel === 2) {
        // Support page - check if reply field is focused
        const replyField = document.getElementById('reply-field');
        if (document.activeElement === replyField) {
            console.log('Double control on support page with reply field focused');
            sendMessage('activateHUD', {
                mode: 'respond',
                demoPageContext: 'support'
            });
        }
    } else if (currentPanel === 3) {
        // Logo page - always activate in Ask mode
        console.log('Double control on logo page');
        sendMessage('activateHUD', {
            mode: 'ask',
            demoPageContext: 'logo'
        });
    }
}

// Keyboard navigation
function handleKeyboard(event) {
    switch (event.key) {
        case 'ArrowRight':
            navigateNext();
            break;
        case 'ArrowLeft':
            navigateBack();
            break;
    }

    // Handle Cmd+Arrow
    if (event.metaKey) {
        if (event.key === 'ArrowRight') {
            navigateNext();
        } else if (event.key === 'ArrowLeft') {
            navigateBack();
        }
    }
}

// Permission handling
function grantPermission(type) {
    sendMessage('requestPermissions', { type });
}

// Update permission status from Swift
window.updatePermissionStatus = function(status) {
    console.log('Received permission status:', status);
    permissionsGranted.accessibility = status.accessibility;
    permissionsGranted.screenRecording = status.screenRecording;

    // Update button states
    updatePermissionButtons();

    // Check if we can enable the continue button
    if (currentPanel === totalPanels) {
        const continueButton = document.querySelector('.continue-button');
        continueButton.disabled = !(permissionsGranted.accessibility && permissionsGranted.screenRecording && termsAccepted && emailValid);
    }
};

// Update permission button states
function updatePermissionButtons() {
    console.log('Updating permission buttons - permissions:', permissionsGranted);

    // Update accessibility button
    const accessibilityButton = document.querySelector('[onclick="grantPermission(\'accessibility\')"]');
    if (accessibilityButton) {
        console.log('Found accessibility button');
        if (permissionsGranted.accessibility) {
            accessibilityButton.textContent = '✓ Granted';
            accessibilityButton.classList.add('granted');
            accessibilityButton.disabled = true;
        } else {
            accessibilityButton.textContent = 'Grant';
            accessibilityButton.classList.remove('granted');
            accessibilityButton.disabled = false;
        }
    } else {
        console.log('Accessibility button not found');
    }

    // Update screen recording button
    const screenRecordingButton = document.querySelector('[onclick="grantPermission(\'screenRecording\')"]');
    if (screenRecordingButton) {
        console.log('Found screen recording button');
        if (permissionsGranted.screenRecording) {
            screenRecordingButton.textContent = '✓ Granted';
            screenRecordingButton.classList.add('granted');
            screenRecordingButton.disabled = true;
        } else {
            screenRecordingButton.textContent = 'Grant';
            screenRecordingButton.classList.remove('granted');
            screenRecordingButton.disabled = false;
        }
    } else {
        console.log('Screen recording button not found');
    }
}

// Email validation
function updateEmailValidity() {
    const emailField = document.getElementById('email-field');
    userEmail = emailField.value.trim();
    // Basic email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    emailValid = emailRegex.test(userEmail);

    // Update continue button if we're on the permissions panel
    if (currentPanel === totalPanels) {
        const continueButton = document.querySelector('.continue-button');
        continueButton.disabled = !(permissionsGranted.accessibility && permissionsGranted.screenRecording && termsAccepted && emailValid);
    }
}

// Terms acceptance
function updateTermsAcceptance() {
    const checkbox = document.getElementById('terms-checkbox');
    termsAccepted = checkbox.checked;

    // Update continue button if we're on the permissions panel
    if (currentPanel === totalPanels) {
        const continueButton = document.querySelector('.continue-button');
        continueButton.disabled = !(permissionsGranted.accessibility && permissionsGranted.screenRecording && termsAccepted && emailValid);
    }

    // Track the acceptance
    if (termsAccepted) {
        sendMessage('track', { event: 'terms_accepted', props: { timestamp: new Date().toISOString() } });
    }
}

// External links
function openTermsOfService(event) {
    event.preventDefault();
    sendMessage('openLink', { url: 'https://www.thequickfox.ai/terms.html' });
}

function openPrivacyPolicy(event) {
    event.preventDefault();
    sendMessage('openLink', { url: 'https://www.thequickfox.ai/privacy.html' });
}


// Complete onboarding
function completeOnboarding() {
    localStorage.setItem('onboardingCompleted', 'true');
    sendMessage('completeOnboarding', { email: userEmail });
}

// WebKit message bridge
function sendMessage(action, data = {}) {
    if (window.webkit && window.webkit.messageHandlers.onboarding) {
        window.webkit.messageHandlers.onboarding.postMessage({
            action,
            ...data
        });
    }
}

// Set up send button handler
function setupSendButton() {
    const sendButton = document.querySelector('.submit-arrow');
    if (sendButton) {
        sendButton.addEventListener('click', handleSendMessage);
    }

    // Also handle Enter key in textarea
    const replyField = document.getElementById('reply-field');
    if (replyField) {
        replyField.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                handleSendMessage();
            }
        });
    }
}

// Handle sending a message
function handleSendMessage() {
    const replyField = document.getElementById('reply-field');
    const message = replyField.value.trim();

    if (!message) return;

    // Create sent message element
    const supportTicket = document.querySelector('.support-ticket');
    const sentMessage = document.createElement('div');
    sentMessage.className = 'ticket-message sent-message';
    sentMessage.innerHTML = `
        <div class="message-author">Support Agent (You)</div>
        <div class="message-content">${escapeHtml(message)}</div>
    `;

    // Insert before reply section
    const replySection = document.querySelector('.reply-section');
    supportTicket.insertBefore(sentMessage, replySection);

    // Clear the textarea
    replyField.value = '';

    // Add animation class
    sentMessage.classList.add('message-sent-animation');

    // Show success feedback
    const sendButton = document.querySelector('.submit-arrow');
    const originalHTML = sendButton.innerHTML;
    sendButton.innerHTML = '✓';
    sendButton.style.color = '#34c759';

    // Reset button after animation
    setTimeout(() => {
        sendButton.innerHTML = originalHTML;
        sendButton.style.color = '';
    }, 1000);

    // Simulate customer response after a delay
    setTimeout(() => {
        const customerResponse = document.createElement('div');
        customerResponse.className = 'ticket-message';
        customerResponse.innerHTML = `
            <div class="message-author">buzz@killington.com</div>
            <div class="message-content">Thanks for the help and sorry to be a buzzkill</div>
        `;
        supportTicket.insertBefore(customerResponse, replySection);
        customerResponse.classList.add('message-received-animation');
    }, 2000);
}

// Helper to escape HTML
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// System appearance support
window.setSystemAppearance = function(mode) {
    document.body.classList.toggle('dark-mode', mode === 'dark');
};
