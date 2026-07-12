document.addEventListener('DOMContentLoaded', async () => {
  const loading = document.getElementById('loading');
  const content = document.getElementById('content');
  const merchantNameEl = document.getElementById('merchant-name');
  const recommendationBox = document.getElementById('recommendation-box');
  const authBox = document.getElementById('auth-box');
  const cardNameEl = document.getElementById('card-name');
  const savingsAmountEl = document.getElementById('savings-amount');
  const logicReasoningEl = document.getElementById('logic-reasoning');

  try {
    // Check if we have an active tab
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab) return;

    // Ask the content script on the active tab what merchant it is
    chrome.tabs.sendMessage(tab.id, { action: 'getMerchantContext' }, async (response) => {
      loading.classList.add('hidden');
      content.classList.remove('hidden');

      if (chrome.runtime.lastError || !response || !response.merchant) {
        merchantNameEl.innerText = "No merchant detected or unsupported site";
        return;
      }

      merchantNameEl.innerText = `Shopping at ${response.merchant.toUpperCase()}`;

      // Ask the background script to fetch the recommendation from Supabase
      chrome.runtime.sendMessage({
        action: 'getRecommendation',
        merchant: response.merchant,
        amount: response.amount || 1000 // default dummy amount if not parsed
      }, (recommendationResponse) => {

        if (recommendationResponse.error === 'unauthenticated') {
          authBox.classList.remove('hidden');
        } else if (recommendationResponse.success && recommendationResponse.data) {
          const data = recommendationResponse.data;
          cardNameEl.innerText = data.cardName;
          savingsAmountEl.innerText = `Save ₹${data.savings}`;
          logicReasoningEl.innerText = data.reasoning;
          recommendationBox.classList.remove('hidden');
        } else {
          logicReasoningEl.innerText = "No specific offers found. Use your default 1% cashback card.";
          cardNameEl.innerText = "Default Card";
          recommendationBox.classList.remove('hidden');
        }
      });
    });
  } catch (err) {
    loading.innerText = 'Error loading extension';
    console.error(err);
  }
});
