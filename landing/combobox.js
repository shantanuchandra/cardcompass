export function closeComboboxState(state = {}) {
  return {
    ...state,
    isOpen: false,
    activeSuggestion: -1,
    activeDescendant: null,
    selectedOptionId: null,
  };
}

export function activeOptionForEnter(options, state = {}) {
  if (!state.isOpen || !Array.isArray(options) || !Number.isInteger(state.activeSuggestion)) return null;
  if (state.activeSuggestion < 0 || state.activeSuggestion >= options.length) return null;

  const option = options[state.activeSuggestion];
  if (!option || (state.activeDescendant && option.id !== state.activeDescendant)) return null;
  return option;
}
