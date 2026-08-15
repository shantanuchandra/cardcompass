import test from 'node:test';
import assert from 'node:assert/strict';

import {
  activeOptionForEnter,
  closeComboboxState,
} from '../../landing/combobox.js';

test('closing the combobox clears active descendant and selection so Enter cannot choose stale options', () => {
  const options = [
    { id: 'card-option-1', label: 'HDFC Bank — Infinia' },
    { id: 'card-option-2', label: 'Axis Bank — Atlas' },
  ];
  const openState = {
    isOpen: true,
    activeSuggestion: 1,
    activeDescendant: 'card-option-2',
    selectedOptionId: 'card-option-2',
  };

  const closedState = closeComboboxState(openState);

  assert.deepEqual(closedState, {
    isOpen: false,
    activeSuggestion: -1,
    activeDescendant: null,
    selectedOptionId: null,
  });
  assert.equal(activeOptionForEnter(options, closedState), null);
});

test('Enter resolves only an active option in an open combobox', () => {
  const options = [{ id: 'card-option-1', label: 'HDFC Bank — Infinia' }];

  assert.equal(activeOptionForEnter(options, {
    isOpen: true,
    activeSuggestion: 0,
    activeDescendant: 'card-option-1',
    selectedOptionId: 'card-option-1',
  }), options[0]);
});
