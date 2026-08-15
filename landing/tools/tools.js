function finiteNumber(value, label, { min = 0, positive = false } = {}) {
  const number = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(number) || number < min || (positive && number <= 0)) {
    throw new TypeError(positive
      ? `A positive ${label.toLowerCase()} is required.`
      : `${label} must be at least ${min}.`);
  }
  return number;
}

function money(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

export function calculateCardComparison({ amount, cards }) {
  const purchaseAmount = finiteNumber(amount, 'Purchase amount', { positive: true });
  if (!Array.isArray(cards) || cards.length < 2) {
    throw new TypeError('Add at least two cards to compare.');
  }

  const comparisons = cards.map((card, index) => {
    const name = String(card?.name ?? '').trim();
    if (!name) throw new TypeError(`Card ${index + 1} needs a name.`);
    const ratePercent = finiteNumber(card.ratePercent, `${name} rate`, { min: 0 });
    const grossValue = money(purchaseAmount * ratePercent / 100);
    const capRemaining = card.capRemaining === '' || card.capRemaining == null
      ? Number.POSITIVE_INFINITY
      : finiteNumber(card.capRemaining, `${name} remaining cap`, { min: 0 });
    const estimatedValue = money(Math.min(grossValue, capRemaining));
    return {
      name,
      grossValue,
      estimatedValue,
      capApplied: estimatedValue < grossValue,
    };
  });

  const winner = comparisons.reduce((best, current) => (
    current.estimatedValue > best.estimatedValue ? current : best
  ));

  return { amount: purchaseAmount, winner: winner.name, comparisons };
}

export function calculateMilestone({ target, currentSpend, plannedSpend = 0, daysRemaining }) {
  const targetAmount = finiteNumber(target, 'Milestone target', { positive: true });
  const current = finiteNumber(currentSpend, 'Current spend', { min: 0 });
  const planned = finiteNumber(plannedSpend, 'Planned spend', { min: 0 });
  const days = finiteNumber(daysRemaining, 'Days remaining', { min: 0 });
  const remainingNow = money(Math.max(targetAmount - current, 0));
  const projectedSpend = money(current + planned);
  const projectedGap = money(Math.max(targetAmount - projectedSpend, 0));
  const dailyPace = remainingNow === 0 ? 0 : (days === 0 ? null : money(remainingNow / days));
  const status = current >= targetAmount
    ? 'reached'
    : projectedSpend >= targetAmount ? 'on_track' : 'shortfall';

  return {
    target: targetAmount,
    remainingNow,
    projectedSpend,
    projectedGap,
    dailyPace,
    status,
  };
}

export function calculateMovieOffer({
  ticketPrice,
  ticketCount,
  offerType,
  offerValue = 0,
  savingsCap,
  convenienceFeePerTicket = 0,
  remainingUses = 1,
}) {
  const price = finiteNumber(ticketPrice, 'Ticket price', { positive: true });
  const count = finiteNumber(ticketCount, 'Ticket count', { positive: true });
  if (!Number.isInteger(count)) throw new TypeError('Ticket count must be a whole number.');
  const fee = finiteNumber(convenienceFeePerTicket, 'Convenience fee', { min: 0 });
  const uses = finiteNumber(remainingUses, 'Remaining uses', { min: 0 });
  const cap = savingsCap === '' || savingsCap == null
    ? Number.POSITIVE_INFINITY
    : finiteNumber(savingsCap, 'Savings cap', { min: 0 });
  const value = finiteNumber(offerValue, 'Offer value', { min: 0 });
  const ticketSubtotal = money(price * count);
  const fees = money(fee * count);

  let rawSavings;
  if (offerType === 'bogo') rawSavings = Math.floor(count / 2) * price;
  else if (offerType === 'percent') rawSavings = ticketSubtotal * value / 100;
  else if (offerType === 'fixed') rawSavings = value;
  else throw new TypeError('Choose BOGO, percentage, or fixed savings.');

  const available = uses > 0;
  const estimatedSavings = available ? money(Math.min(rawSavings, cap, ticketSubtotal)) : 0;
  const total = ticketSubtotal + fees;
  return {
    ticketSubtotal,
    fees,
    estimatedSavings,
    estimatedPayable: money(total - estimatedSavings),
    effectiveSavingsPercent: total === 0 ? 0 : money(estimatedSavings / total * 100),
    available,
  };
}

function formNumber(form, name) {
  return form.elements.namedItem(name)?.value ?? '';
}

function formatInr(value) {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency', currency: 'INR', maximumFractionDigits: 2,
  }).format(value);
}

function renderError(output, error) {
  output.hidden = false;
  output.classList.add('tool-output-error');
  output.innerHTML = `<p><strong>Check the inputs.</strong> ${error.message}</p>`;
}

function setupBestCard(form) {
  const output = document.getElementById(form.dataset.output);
  output.hidden = false;
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    try {
      const result = calculateCardComparison({
        amount: formNumber(form, 'amount'),
        cards: [1, 2, 3].map((index) => ({
          name: form.elements.namedItem(`card_${index}_name`).value,
          ratePercent: formNumber(form, `card_${index}_rate`),
          capRemaining: formNumber(form, `card_${index}_cap`),
        })),
      });
      output.hidden = false;
      output.classList.remove('tool-output-error');
      output.innerHTML = `<p class="mono-label">Illustrative result</p><h2>${result.winner} leads for this purchase</h2><div class="result-grid">${result.comparisons.map((card) => `<article><span>${card.name}</span><strong>${formatInr(card.estimatedValue)}</strong><small>${card.capApplied ? `Limited from ${formatInr(card.grossValue)} by the cap entered` : `Gross estimate ${formatInr(card.grossValue)}`}</small></article>`).join('')}</div><p class="result-note">This is arithmetic based on your inputs, not a live card recommendation. Check issuer eligibility and terms.</p>`;
    } catch (error) { renderError(output, error); }
  });
}

function setupMilestone(form) {
  const output = document.getElementById(form.dataset.output);
  output.hidden = false;
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    try {
      const result = calculateMilestone({
        target: formNumber(form, 'target'),
        currentSpend: formNumber(form, 'current_spend'),
        plannedSpend: formNumber(form, 'planned_spend'),
        daysRemaining: formNumber(form, 'days_remaining'),
      });
      const heading = result.status === 'reached'
        ? 'Target reached in this estimate'
        : result.status === 'on_track' ? 'Your plan reaches the target' : 'Your plan leaves a gap';
      output.hidden = false;
      output.classList.remove('tool-output-error');
      output.innerHTML = `<p class="mono-label">Illustrative result</p><h2>${heading}</h2><div class="result-grid"><article><span>Remaining now</span><strong>${formatInr(result.remainingNow)}</strong></article><article><span>Projected gap</span><strong>${formatInr(result.projectedGap)}</strong></article><article><span>Daily pace needed</span><strong>${result.dailyPace == null ? 'No days left' : formatInr(result.dailyPace)}</strong></article></div><p class="result-note">Only eligible posted spend may count. Refunds and issuer posting dates can change progress.</p>`;
    } catch (error) { renderError(output, error); }
  });
}

function setupMovieOffer(form) {
  const output = document.getElementById(form.dataset.output);
  output.hidden = false;
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    try {
      const result = calculateMovieOffer({
        ticketPrice: formNumber(form, 'ticket_price'),
        ticketCount: formNumber(form, 'ticket_count'),
        offerType: form.elements.namedItem('offer_type').value,
        offerValue: formNumber(form, 'offer_value'),
        savingsCap: formNumber(form, 'savings_cap'),
        convenienceFeePerTicket: formNumber(form, 'convenience_fee'),
        remainingUses: formNumber(form, 'remaining_uses'),
      });
      output.hidden = false;
      output.classList.remove('tool-output-error');
      output.innerHTML = `<p class="mono-label">Illustrative result</p><h2>${result.available ? `${formatInr(result.estimatedSavings)} estimated ticket savings` : 'No remaining use entered'}</h2><div class="result-grid"><article><span>Tickets</span><strong>${formatInr(result.ticketSubtotal)}</strong></article><article><span>Fees entered</span><strong>${formatInr(result.fees)}</strong></article><article><span>Estimated payable</span><strong>${formatInr(result.estimatedPayable)}</strong><small>${result.effectiveSavingsPercent}% off total including entered fees</small></article></div><p class="result-note">Actual checkout eligibility, inventory, taxes, fees, card network, showtime and quota rules can differ.</p>`;
    } catch (error) { renderError(output, error); }
  });
}

if (typeof document !== 'undefined') {
  document.querySelectorAll('[data-tool-form]').forEach((form) => {
    if (form.dataset.toolForm === 'best-card') setupBestCard(form);
    if (form.dataset.toolForm === 'milestone') setupMilestone(form);
    if (form.dataset.toolForm === 'movie-offer') setupMovieOffer(form);
  });
}
