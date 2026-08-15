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

  const maximum = Math.max(...comparisons.map((card) => card.estimatedValue));
  const winners = comparisons.filter((card) => card.estimatedValue === maximum).map((card) => card.name);

  return { amount: purchaseAmount, winner: winners[0], winners, comparisons };
}

export function calculateMilestone({ target, currentSpend, plannedSpend = 0, daysRemaining }) {
  const targetAmount = finiteNumber(target, 'Milestone target', { positive: true });
  const current = finiteNumber(currentSpend, 'Current spend', { min: 0 });
  const planned = finiteNumber(plannedSpend, 'Planned spend', { min: 0 });
  const days = finiteNumber(daysRemaining, 'Days remaining', { min: 0 });
  const remainingNow = money(Math.max(targetAmount - current, 0));
  const projectedSpend = money(current + planned);
  const projectedGap = money(Math.max(targetAmount - projectedSpend, 0));
  const dailyPace = projectedGap === 0 ? 0 : (days === 0 ? null : money(projectedGap / days));
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
  if (!Number.isInteger(uses)) throw new TypeError('Remaining uses must be a whole number.');
  const cap = savingsCap === '' || savingsCap == null
    ? Number.POSITIVE_INFINITY
    : finiteNumber(savingsCap, 'Savings cap', { min: 0 });
  const value = finiteNumber(offerValue, 'Offer value', { min: 0 });
  const ticketSubtotal = money(price * count);
  const fees = money(fee * count);

  let rawSavings;
  if (offerType === 'bogo') rawSavings = Math.min(Math.floor(count / 2), uses) * price;
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

function textElement(documentRef, tagName, text, className) {
  const element = documentRef.createElement(tagName);
  if (className) element.className = className;
  element.textContent = text;
  return element;
}

function resultArticle(documentRef, label, value, detail) {
  const article = documentRef.createElement('article');
  article.append(
    textElement(documentRef, 'span', label),
    textElement(documentRef, 'strong', value),
  );
  if (detail) article.append(textElement(documentRef, 'small', detail));
  return article;
}

function prepareOutput(output) {
  output.hidden = false;
  output.classList.remove('tool-output-error');
  output.replaceChildren();
}

export function renderToolError(documentRef, output, error) {
  prepareOutput(output);
  output.classList.add('tool-output-error');
  output.append(textElement(
    documentRef,
    'p',
    `Check the inputs. ${String(error?.message ?? 'The calculation could not be completed.')}`,
  ));
}

export function renderBestCardResult(documentRef, output, result) {
  prepareOutput(output);
  const grid = documentRef.createElement('div');
  grid.className = 'result-grid';
  for (const card of result.comparisons) {
    grid.append(resultArticle(
      documentRef,
      card.name,
      formatInr(card.estimatedValue),
      card.capApplied
        ? `Limited from ${formatInr(card.grossValue)} by the cap entered`
        : `Gross estimate ${formatInr(card.grossValue)}`,
    ));
  }
  output.append(
    textElement(documentRef, 'p', 'Illustrative result', 'mono-label'),
    textElement(documentRef, 'h2', result.winners?.length > 1
      ? `${result.winners.join(' and ')} tie for this purchase`
      : `${result.winner} leads for this purchase`),
    grid,
    textElement(
      documentRef,
      'p',
      'This is arithmetic based on your inputs, not a live card recommendation. Check issuer eligibility and terms.',
      'result-note',
    ),
  );
}

function renderMilestoneResult(documentRef, output, result) {
  const heading = result.status === 'reached'
    ? 'Target reached in this estimate'
    : result.status === 'on_track' ? 'Your plan reaches the target' : 'Your plan leaves a gap';
  prepareOutput(output);
  const grid = documentRef.createElement('div');
  grid.className = 'result-grid';
  grid.append(
    resultArticle(documentRef, 'Remaining now', formatInr(result.remainingNow)),
    resultArticle(documentRef, 'Projected gap', formatInr(result.projectedGap)),
    resultArticle(
      documentRef,
      'Daily pace for projected gap',
      result.dailyPace == null ? 'No days left' : formatInr(result.dailyPace),
    ),
  );
  output.append(
    textElement(documentRef, 'p', 'Illustrative result', 'mono-label'),
    textElement(documentRef, 'h2', heading),
    grid,
    textElement(
      documentRef,
      'p',
      'Only eligible posted spend may count. Refunds and issuer posting dates can change progress.',
      'result-note',
    ),
  );
}

function renderMovieOfferResult(documentRef, output, result) {
  prepareOutput(output);
  const grid = documentRef.createElement('div');
  grid.className = 'result-grid';
  grid.append(
    resultArticle(documentRef, 'Tickets', formatInr(result.ticketSubtotal)),
    resultArticle(documentRef, 'Fees entered', formatInr(result.fees)),
    resultArticle(
      documentRef,
      'Estimated payable',
      formatInr(result.estimatedPayable),
      `${result.effectiveSavingsPercent}% off total including entered fees`,
    ),
  );
  output.append(
    textElement(documentRef, 'p', 'Illustrative result', 'mono-label'),
    textElement(
      documentRef,
      'h2',
      result.available
        ? `${formatInr(result.estimatedSavings)} estimated ticket savings`
        : 'No remaining use entered',
    ),
    grid,
    textElement(
      documentRef,
      'p',
      'Actual checkout eligibility, inventory, taxes, fees, card network, showtime and quota rules can differ.',
      'result-note',
    ),
  );
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
        })).filter((card) => card.name.trim()),
      });
      renderBestCardResult(document, output, result);
    } catch (error) { renderToolError(document, output, error); }
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
      renderMilestoneResult(document, output, result);
    } catch (error) { renderToolError(document, output, error); }
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
      renderMovieOfferResult(document, output, result);
    } catch (error) { renderToolError(document, output, error); }
  });
}

if (typeof document !== 'undefined') {
  document.querySelectorAll('[data-tool-form]').forEach((form) => {
    if (form.dataset.toolForm === 'best-card') setupBestCard(form);
    if (form.dataset.toolForm === 'milestone') setupMilestone(form);
    if (form.dataset.toolForm === 'movie-offer') setupMovieOffer(form);
  });
}
