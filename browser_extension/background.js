// Background Service Worker for CardCompass

// In a full implementation, this would import the Supabase JS client
// and use chrome.storage to manage the user's auth session securely.

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'getRecommendation') {
    handleRecommendation(request, sendResponse);
    return true; // Keep the message channel open for asynchronous response
  }
});

async function handleRecommendation(request, sendResponse) {
  try {
    const merchant = request.merchant;
    const amount = request.amount || 1000;

    // Simulate Supabase edge function / API latency
    await new Promise(r => setTimeout(r, 800));

    // Mock recommendation logic based on merchant
    // In production, this would hit the Supabase backend `benefits` and `movie_rule_engine`
    let recommendation = {
      success: true,
      data: null
    };

    if (merchant === 'Amazon' || merchant === 'Flipkart') {
      recommendation.data = {
        cardName: 'SBI Cashback Card',
        savings: (amount * 0.05).toFixed(0),
        reasoning: '5% cashback on all online spends without merchant restrictions.'
      };
    } else if (merchant === 'Swiggy' || merchant === 'Zomato') {
      recommendation.data = {
        cardName: 'HDFC Swiggy Card',
        savings: (amount * 0.10).toFixed(0),
        reasoning: '10% direct cashback on Swiggy and Zomato dining.'
      };
    } else if (merchant === 'BookMyShow') {
      recommendation.data = {
        cardName: 'ICICI Sapphiro',
        savings: Math.min(amount, 500).toFixed(0), // Buy 1 Get 1 up to 500
        reasoning: 'Buy 1 Get 1 Free on movie tickets (up to ₹500 discount).'
      };
    } else {
      recommendation.success = false;
    }

    sendResponse(recommendation);
  } catch (error) {
    console.error('Error fetching recommendation', error);
    sendResponse({ success: false, error: 'unknown_error' });
  }
}
