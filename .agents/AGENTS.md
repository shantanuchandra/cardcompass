# Workspace Assistant Rules

This file registers instructions and rules for AI assistant agents (like Antigravity) working on the CardCompass codebase.

## Credit Card Statement Pruning Guidelines

- **Product Manager Feedback Loop**: Always check if the file `pm_pruning_feedback.json` exists in the project root directory before working on, modifying, or creating card statement text extraction, pruning, or parsing logic.
- **Feedback Retrieval**: If `pm_pruning_feedback.json` exists, read it to understand the Product Manager's feedback, constraints, and instructions regarding the statement parsing filters.
- **Rule Adherence**: You must strictly respect the guidelines and adjustments written by the Product Manager in `pm_pruning_feedback.json` when modifying regex patterns, LlM prompts, or pruning thresholds.
