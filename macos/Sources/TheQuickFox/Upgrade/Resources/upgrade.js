// State
let selectedPriceId = null;
let pricingData = null;
let isProcessing = false;

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    loadAppImages();
    fetchPricing();
});

// Load app icon and logo
function loadAppImages() {
    // Request images from native app
    window.webkit.messageHandlers.upgrade.postMessage({
        action: 'getAppImages'
    });
}

// Called by native app to set images
function setAppImages(iconBase64, logoBase64) {
    if (iconBase64) {
        document.getElementById('appIcon').src = 'data:image/png;base64,' + iconBase64;
    }
    if (logoBase64) {
        document.getElementById('appLogo').src = 'data:image/png;base64,' + logoBase64;
    }
}

// Fetch pricing from API
async function fetchPricing() {
    try {
        // Request pricing data from native app
        window.webkit.messageHandlers.upgrade.postMessage({
            action: 'fetchPricing'
        });
    } catch (error) {
        showError('Failed to load pricing options');
    }
}

// Called by native app with pricing data
function setPricingData(data) {
    console.log('Received pricing data:', data);
    pricingData = data;

    // Update trial limit in subtitle if provided
    if (data.trial && data.trial.queries_limit) {
        document.getElementById('trialLimit').textContent = data.trial.queries_limit;
    }

    // Render pricing options
    renderPricing(data.prices);
}

function renderPricing(prices) {
    const container = document.getElementById('pricingContainer');

    if (!prices || prices.length === 0) {
        container.innerHTML = '<p class="error">No pricing options available</p>';
        return;
    }

    console.log('Rendering prices:', prices);

    // Sort prices by amount (lowest first)
    prices.sort((a, b) => a.amount - b.amount);

    // Create pricing cards with inline features and CTAs
    const optionsHtml = prices.map((price, index) => {
        const isMonthly = price.interval === 'month';
        const isYearly = price.interval === 'year';

        let badge = '';
        let cardClass = 'price-card';
        if (isYearly) {
            badge = 'RECOMMENDED';
            cardClass += ' recommended selected';
        }

        // Format price display
        let priceDisplay = `$${(price.amount / 100).toFixed(2)}`;
        let priceInterval = '';
        let savings = '';

        if (isMonthly) {
            priceInterval = '/month';
        } else if (isYearly) {
            priceInterval = '/year';
            const monthlyPrice = prices.find(p => p.interval === 'month');
            if (monthlyPrice) {
                const yearlySavings = (monthlyPrice.amount * 12 - price.amount) / 100;
                savings = `Save $${yearlySavings.toFixed(2)}`;
            }
        }

        return `
            <div class="${cardClass}"
                 data-price-id="${price.price_id}"
                 onclick="selectPrice('${price.price_id}')">
                ${badge ? `<div class="badge">${badge}</div>` : ''}
                <div class="card-content">
                    <h3 class="plan-name">${capitalizeInterval(price.interval)}</h3>
                    <div class="price-section">
                        <span class="price-amount">${priceDisplay}</span>
                        <span class="price-interval">${priceInterval}</span>
                    </div>
                    ${savings ? `<div class="savings">${savings}</div>` : '<div class="savings-spacer"></div>'}

                    <div class="features-list">
                        ${price.features.map(feature =>
                            `<div class="feature-item">✓ ${feature}</div>`
                        ).join('')}
                    </div>

                    <button class="card-cta-btn" data-price-id="${price.price_id}" onclick="event.stopPropagation(); selectAndUpgrade('${price.price_id}')">
                        ${isMonthly ? 'Start Monthly' : 'Get Yearly'}
                    </button>
                </div>
            </div>
        `;
    }).join('');

    container.innerHTML = `<div class="pricing-options">${optionsHtml}</div>`;

    // Select recommended option by default
    const recommended = prices.find(p => p.interval === 'year') || prices[0];
    if (recommended) {
        selectedPriceId = recommended.price_id;
    }
}

function capitalizeInterval(interval) {
    return interval.charAt(0).toUpperCase() + interval.slice(1) + 'ly';
}

function selectAndUpgrade(priceId) {
    if (isProcessing) return;
    
    selectedPriceId = priceId;
    setLoadingState(priceId, true);
    handleUpgrade();
}

function selectPrice(priceId) {
    selectedPriceId = priceId;

    // Update UI - remove selected from all cards first
    document.querySelectorAll('.price-card').forEach(card => {
        card.classList.remove('selected');
    });

    // Add selected to the clicked card
    document.querySelectorAll('.price-card').forEach(card => {
        if (card.dataset.priceId === priceId) {
            card.classList.add('selected');
        }
    });
}

function updateFeaturesList(features) {
    const list = document.getElementById('featuresList');
    list.innerHTML = features.map(feature => `<li>${feature}</li>`).join('');
}

function handleUpgrade() {
    if (!selectedPriceId || isProcessing) return;
    
    isProcessing = true;

    // Send message to native app with just the price ID
    // The API will determine everything based on the price ID
    window.webkit.messageHandlers.upgrade.postMessage({
        action: 'upgrade',
        priceId: selectedPriceId
    });
}

function showError(message) {
    const container = document.getElementById('pricingContainer');
    container.innerHTML = `<p class="error">${message}</p>`;
}

// Handle system appearance changes
function setSystemAppearance(appearance) {
    document.documentElement.dataset.appearance = appearance;
}

// Set loading state on button
function setLoadingState(priceId, isLoading) {
    const button = document.querySelector(`button[data-price-id="${priceId}"]`);
    if (!button) return;
    
    if (isLoading) {
        // Store original text
        if (!button.dataset.originalText) {
            button.dataset.originalText = button.textContent;
        }
        
        button.disabled = true;
        button.textContent = 'Loading...';
        
        // Disable all other buttons too
        document.querySelectorAll('.card-cta-btn').forEach(btn => {
            btn.disabled = true;
        });
    } else {
        // Restore original text
        if (button.dataset.originalText) {
            button.textContent = button.dataset.originalText;
        }
        
        button.disabled = false;
        
        // Re-enable all buttons
        document.querySelectorAll('.card-cta-btn').forEach(btn => {
            btn.disabled = false;
        });
        
        isProcessing = false;
    }
}

// Called by native app when checkout fails
function checkoutFailed(error) {
    isProcessing = false;
    if (selectedPriceId) {
        setLoadingState(selectedPriceId, false);
    }
    showError(error || 'Checkout failed. Please try again.');
}
