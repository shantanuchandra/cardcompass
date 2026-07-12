// This content script runs on the pages defined in manifest.json (Amazon, Flipkart, Swiggy, etc)

let currentMerchant = null;
let cartAmount = 0;

// Determine merchant based on domain
const hostname = window.location.hostname;
if (hostname.includes('amazon.in')) currentMerchant = 'Amazon';
else if (hostname.includes('flipkart.com')) currentMerchant = 'Flipkart';
else if (hostname.includes('swiggy.com')) currentMerchant = 'Swiggy';
else if (hostname.includes('zomato.com')) currentMerchant = 'Zomato';
else if (hostname.includes('bookmyshow.com')) currentMerchant = 'BookMyShow';

// Listen for messages from popup.js
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'getMerchantContext') {
    // Attempt to scrape amount based on merchant
    scrapeAmount();
    sendResponse({
      merchant: currentMerchant,
      amount: cartAmount
    });
  }
});

function scrapeAmount() {
  try {
    if (currentMerchant === 'Amazon') {
      const el = document.querySelector('.sc-price'); // cart price
      if (el) cartAmount = parseFloat(el.innerText.replace(/[^0-9.]/g, ''));
    } else if (currentMerchant === 'Swiggy') {
      const el = document.querySelector('._3L1X9'); // total to pay
      if (el) cartAmount = parseFloat(el.innerText.replace(/[^0-9.]/g, ''));
    }
  } catch(e) {
    console.error('Error scraping amount', e);
  }
}

// Inject tooltip if we are on a checkout/cart page
function injectTooltipIfCheckout() {
  if (!currentMerchant) return;

  // Basic heuristic: check if URL contains 'cart' or 'checkout' or 'payment'
  const url = window.location.href.toLowerCase();
  if (url.includes('cart') || url.includes('checkout') || url.includes('payment') || url.includes('buy')) {

    // Ask background for recommendation
    scrapeAmount();
    chrome.runtime.sendMessage({
      action: 'getRecommendation',
      merchant: currentMerchant,
      amount: cartAmount > 0 ? cartAmount : 1000
    }, (response) => {
      if (response && response.success && response.data) {
        showTooltip(response.data);
      }
    });
  }
}

function showTooltip(data) {
  // Prevent multiple injections
  if (document.getElementById('cardcompass-tooltip')) return;

  const tooltip = document.createElement('div');
  tooltip.id = 'cardcompass-tooltip';
  tooltip.className = 'cc-tooltip-container';

  tooltip.innerHTML = `
    <div class="cc-header">
      <span class="cc-logo">🧭 CardCompass</span>
      <span class="cc-close" id="cc-close-btn">×</span>
    </div>
    <div class="cc-body">
      <div class="cc-label">Use this card for ₹${data.savings} savings:</div>
      <div class="cc-card-name">${data.cardName}</div>
      <div class="cc-reason">${data.reasoning}</div>
    </div>
  `;

  document.body.appendChild(tooltip);

  document.getElementById('cc-close-btn').addEventListener('click', () => {
    tooltip.remove();
  });
}

// Run injection logic after a short delay to allow SPAs to load
setTimeout(injectTooltipIfCheckout, 2000);
