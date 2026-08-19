import { accessActionHandlers } from "./access.ts";
import { cardDataActionHandlers } from "./card_data.ts";

export const actionHandlers = Object.freeze({
  ...accessActionHandlers,
  ...cardDataActionHandlers,
});
