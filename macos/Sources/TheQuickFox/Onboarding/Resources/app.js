// ============================================
// Onboarding State Management
// ============================================

let currentPanel = 1;
const totalPanels = 5;
window.currentPanel = currentPanel;

// Permission states
let permissionsGranted = {
    accessibility: false,
    screenRecording: false
};

// User input states
let termsAccepted = false;
let emailValid = false;
let userEmail = '';
let selectedTone = 'professional';
let hasTransformed = false;  // Track if user has tried the transform


// ============================================
// Initialization
// ============================================

document.addEventListener('DOMContentLoaded', () => {
    setupKeyboardNavigation();
    setupToneChips();
    updateUI();
});


// ============================================
// Panel 2: Interactive Transform
// ============================================

function setupToneChips() {
    document.querySelectorAll('.tone-chip').forEach(chip => {
        chip.addEventListener('click', () => {
            document.querySelectorAll('.tone-chip').forEach(c => c.classList.remove('active'));
            chip.classList.add('active');
            selectedTone = chip.dataset.tone;
        });
    });
}

async function transformText() {
    const input = document.getElementById('user-input').value.trim();
    if (!input) {
        document.getElementById('user-input').focus();
        return;
    }

    const btn = document.getElementById('transform-btn');
    const btnText = btn.querySelector('.btn-text');
    const btnLoader = btn.querySelector('.btn-loader');
    const outputSection = document.getElementById('output-section');
    const outputText = document.getElementById('output-text');
    const winText = document.getElementById('win-text');

    // Show loading state
    btn.disabled = true;
    btnText.style.display = 'none';
    btnLoader.style.display = 'block';

    try {
        // Call the compose API via Swift bridge
        const result = await callComposeAPI(input, selectedTone);

        // Show output
        outputText.textContent = result;
        outputSection.style.display = 'block';
        winText.style.display = 'block';
        hasTransformed = true;

        // Update button to show "Continue" instead of "Skip"
        updateContinueButton();

        // Track the win
        sendMessage('track', { event: 'onboarding_transform_success', props: { tone: selectedTone } });

    } catch (error) {
        console.error('Transform failed:', error);
        // Show a fallback response
        const fallbackResponses = {
            professional: `Thank you for your message. I wanted to follow up regarding: "${input}". Please let me know if you need any additional information.`,
            friendly: `Hey there! Thanks for reaching out about "${input}". Happy to help with anything else!`,
            formal: `Dear Sir/Madam, I am writing in reference to your inquiry: "${input}". Please do not hesitate to contact me should you require further assistance.`
        };
        outputText.textContent = fallbackResponses[selectedTone];
        outputSection.style.display = 'block';
        winText.style.display = 'block';
        hasTransformed = true;

        // Update button to show "Continue" instead of "Skip"
        updateContinueButton();
    } finally {
        btn.disabled = false;
        btnText.style.display = 'inline';
        btnLoader.style.display = 'none';
    }
}

function callComposeAPI(input, tone) {
    return new Promise((resolve, reject) => {
        // Send to Swift to call the actual API
        sendMessage('composeDemo', {
            input: input,
            tone: tone,
            callback: 'handleComposeResult'
        });

        // Set up a listener for the response
        window.handleComposeResult = function(result) {
            if (result.success) {
                resolve(result.text);
            } else {
                reject(new Error(result.error || 'API call failed'));
            }
            delete window.handleComposeResult;
        };

        // Timeout fallback
        setTimeout(() => {
            if (window.handleComposeResult) {
                reject(new Error('Timeout'));
                delete window.handleComposeResult;
            }
        }, 15000);
    });
}

function copyResult() {
    const outputText = document.getElementById('output-text').textContent;
    navigator.clipboard.writeText(outputText).then(() => {
        const copyBtn = document.querySelector('.copy-btn');
        const originalText = copyBtn.textContent;
        copyBtn.textContent = 'Copied!';
        setTimeout(() => {
            copyBtn.textContent = originalText;
        }, 1500);
    });
}

// ============================================
// Permission Handling
// ============================================

function grantPermission(type) {
    sendMessage('requestPermissions', { type });
}

window.updatePermissionStatus = function(status) {
    console.log('Permission status update:', status);
    permissionsGranted.accessibility = status.accessibility;
    permissionsGranted.screenRecording = status.screenRecording;

    // Update accessibility button/card (panel 3)
    const accessibilityCard = document.getElementById('accessibility-card');
    const accessibilityBtn = document.getElementById('accessibility-btn');
    if (accessibilityCard && accessibilityBtn) {
        if (permissionsGranted.accessibility) {
            accessibilityCard.classList.add('granted');
            accessibilityBtn.textContent = 'Enabled';
            accessibilityBtn.classList.add('granted');
            accessibilityBtn.disabled = true;
        } else {
            accessibilityCard.classList.remove('granted');
            accessibilityBtn.textContent = 'Enable';
            accessibilityBtn.classList.remove('granted');
            accessibilityBtn.disabled = false;
        }
    }

    // Update screen access button/card (panel 5)
    const screenCard = document.getElementById('screen-card');
    const screenBtn = document.getElementById('screen-btn');
    const screenStatusText = document.getElementById('screen-status-text');
    if (screenCard && screenBtn) {
        if (permissionsGranted.screenRecording) {
            screenCard.classList.add('granted');
            screenBtn.textContent = 'Enabled';
            screenBtn.classList.add('granted');
            screenBtn.disabled = true;
            if (screenStatusText) screenStatusText.textContent = 'Access granted!';
        } else {
            screenCard.classList.remove('granted');
            screenBtn.textContent = 'Enable';
            screenBtn.classList.remove('granted');
            screenBtn.disabled = false;
            if (screenStatusText) screenStatusText.textContent = 'Click Enable, then toggle on TheQuickFox';
        }
    }

    // If screen recording granted while on panel 5, auto-complete
    if (currentPanel === 5 && permissionsGranted.screenRecording) {
        // Small delay to let user see the "granted" state
        setTimeout(() => {
            completeOnboarding();
        }, 500);
    }

    updateContinueButton();
};

function skipToPermissions() {
    currentPanel = 3;
    updateUI();
    sendMessage('track', { event: 'skipped_to_permissions' });
}


// ============================================
// Email & Terms Validation
// ============================================

function updateEmailValidity() {
    const emailField = document.getElementById('email-field');
    userEmail = emailField.value.trim();
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    emailValid = emailRegex.test(userEmail);
    updateContinueButton();
}

function updateTermsAcceptance() {
    const checkbox = document.getElementById('terms-checkbox');
    termsAccepted = checkbox.checked;
    updateContinueButton();

    if (termsAccepted) {
        sendMessage('track', { event: 'terms_accepted' });
    }
}

function openTermsOfService(event) {
    event.preventDefault();
    sendMessage('openLink', { url: 'https://www.thequickfox.ai/terms' });
}

function openPrivacyPolicy(event) {
    event.preventDefault();
    sendMessage('openLink', { url: 'https://www.thequickfox.ai/privacy/' });
}

// ============================================
// Navigation
// ============================================

function navigateNext() {
    if (currentPanel < totalPanels) {
        // When leaving Panel 4 (email/TOS), save onboarding progress early
        // This ensures the flag is set before screen recording (which may restart the app)
        if (currentPanel === 4 && termsAccepted && emailValid) {
            sendMessage('saveOnboardingProgress', { email: userEmail });
        }

        currentPanel++;
        updateUI();
        sendMessage('track', { event: 'panel_view', props: { panel: currentPanel } });
    } else if (currentPanel === totalPanels) {
        if (canComplete()) {
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

function canProceed() {
    switch (currentPanel) {
        case 1:
            return true;  // Always can proceed from demo
        case 2:
            return true;  // Can proceed even without trying (but encourage trying)
        case 3:
            return permissionsGranted.accessibility;  // Must grant accessibility
        case 4:
            return termsAccepted && emailValid;  // Must accept terms and enter email
        case 5:
            return permissionsGranted.screenRecording;  // Must grant screen recording
        default:
            return true;
    }
}

function canComplete() {
    return permissionsGranted.accessibility && permissionsGranted.screenRecording && termsAccepted && emailValid;
}

function updateUI() {
    window.currentPanel = currentPanel;

    // Update carousel position
    const carousel = document.getElementById('carousel');
    const offset = -(currentPanel - 1) * 100;
    carousel.style.transform = `translateX(${offset}%)`;

    // Update active panel class
    document.querySelectorAll('.panel').forEach((panel, index) => {
        panel.classList.toggle('active', index + 1 === currentPanel);
    });

    // Update progress dots
    document.querySelectorAll('.dot').forEach((dot, index) => {
        dot.classList.toggle('active', index + 1 === currentPanel);
    });

    // Update navigation buttons
    const backButton = document.querySelector('.back-button');
    const continueButton = document.getElementById('continue-btn');

    // Show/hide back button
    backButton.style.visibility = currentPanel === 1 ? 'hidden' : 'visible';

    // Show skip button only on panels 1 and 2 (before permission screens)
    const skipButton = document.getElementById('skip-btn');
    if (skipButton) {
        skipButton.style.display = (currentPanel === 1 || currentPanel === 2) ? 'inline-block' : 'none';
    }

    // Show navigation on all panels
    const navigation = document.querySelector('.navigation');
    if (navigation) {
        navigation.style.display = 'flex';
    }

    updateContinueButton();

    // Handle panel-specific logic
    if (currentPanel === 2) {
        // Focus input after transition
        setTimeout(() => {
            const input = document.getElementById('user-input');
            if (input) input.focus();
        }, 500);
    }

    if (currentPanel === 4) {
        // Focus email input after transition
        setTimeout(() => {
            const emailField = document.getElementById('email-field');
            if (emailField) emailField.focus();
        }, 500);
    }

    if (currentPanel === 3 || currentPanel === 5) {
        // Start permission monitoring for permission panels
        sendMessage('startPermissionMonitoring', {});
    }
}

function updateContinueButton() {
    const continueButton = document.getElementById('continue-btn');

    switch (currentPanel) {
        case 1:
            continueButton.textContent = 'Continue';
            continueButton.disabled = false;
            break;
        case 2:
            continueButton.textContent = 'Continue';
            continueButton.disabled = false;
            break;
        case 3:
            continueButton.textContent = 'Continue';
            continueButton.disabled = !permissionsGranted.accessibility;
            break;
        case 4:
            continueButton.textContent = 'Continue';
            continueButton.disabled = !(termsAccepted && emailValid);  // Must accept terms and email
            break;
        case 5:
            continueButton.textContent = 'Finish';
            continueButton.disabled = !permissionsGranted.screenRecording;  // Must grant screen recording
            break;
        default:
            continueButton.textContent = 'Continue';
            continueButton.disabled = false;
    }
}

// ============================================
// Keyboard Navigation
// ============================================

function setupKeyboardNavigation() {
    // Disabled - arrow keys were accidentally advancing panels
}

// ============================================
// Completion
// ============================================

function completeOnboarding() {
    sendMessage('completeOnboarding', { email: userEmail });

    // Fire confetti!
    fireConfetti();

    sendMessage('track', { event: 'onboarding_completed', props: {
        has_screen_recording: permissionsGranted.screenRecording,
        tried_transform: hasTransformed
    }});
}

function closeOnboarding() {
    sendMessage('closeWindow', {});
}

// ============================================
// Confetti Animation
// ============================================

function fireConfetti() {
    const canvas = document.getElementById('confetti-canvas');
    const ctx = canvas.getContext('2d');

    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;

    const particles = [];
    const particleCount = 150;
    const colors = ['#007aff', '#0055d4', '#ff9500', '#34c759', '#5ac8fa', '#ff3b30'];

    class Particle {
        constructor() {
            this.x = Math.random() * canvas.width;
            this.y = -10;
            this.size = Math.random() * 8 + 4;
            this.speedY = Math.random() * 3 + 2;
            this.speedX = Math.random() * 4 - 2;
            this.color = colors[Math.floor(Math.random() * colors.length)];
            this.rotation = Math.random() * 360;
            this.rotationSpeed = Math.random() * 10 - 5;
            this.opacity = 1;
        }

        update() {
            this.y += this.speedY;
            this.x += this.speedX;
            this.rotation += this.rotationSpeed;
            this.speedY += 0.1;  // Gravity

            if (this.y > canvas.height - 100) {
                this.opacity -= 0.02;
            }
        }

        draw() {
            ctx.save();
            ctx.translate(this.x, this.y);
            ctx.rotate(this.rotation * Math.PI / 180);
            ctx.fillStyle = this.color;
            ctx.globalAlpha = this.opacity;
            ctx.fillRect(-this.size / 2, -this.size / 2, this.size, this.size / 2);
            ctx.restore();
        }
    }

    // Create particles
    for (let i = 0; i < particleCount; i++) {
        setTimeout(() => {
            particles.push(new Particle());
        }, i * 20);
    }

    function animate() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        particles.forEach((particle, index) => {
            particle.update();
            particle.draw();

            if (particle.opacity <= 0) {
                particles.splice(index, 1);
            }
        });

        if (particles.length > 0) {
            requestAnimationFrame(animate);
        }
    }

    animate();
}

// ============================================
// Error Handling
// ============================================

window.navigateToPermissionsWithError = function(errorMessage) {
    // Navigate to accessibility panel (panel 3)
    currentPanel = 3;
    updateUI();

    setTimeout(() => {
        const panelContent = document.querySelector('.panel[data-panel="3"] .panel-content');
        if (panelContent) {
            let errorDiv = panelContent.querySelector('.permissions-error');
            if (!errorDiv) {
                errorDiv = document.createElement('div');
                errorDiv.className = 'permissions-error';
                panelContent.insertBefore(errorDiv, panelContent.firstChild);
            }
            errorDiv.textContent = errorMessage;
        }
    }, 100);
};

// ============================================
// Swift Communication
// ============================================

function sendMessage(action, data = {}) {
    if (window.webkit && window.webkit.messageHandlers.onboarding) {
        window.webkit.messageHandlers.onboarding.postMessage({
            action,
            ...data
        });
    } else {
        console.log('Swift bridge not available:', action, data);
    }
}

// ============================================
// System Appearance
// ============================================

window.setSystemAppearance = function(mode) {
    document.body.classList.toggle('dark-mode', mode === 'dark');
};
