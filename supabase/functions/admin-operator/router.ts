import { accessActionHandlers } from "./access.ts";
import { cardDataActionHandlers } from "./card_data.ts";
import { inboxActionHandlers } from "./inbox.ts";
import { customerActionHandlers } from "./customers.ts";
import { systemActionHandlers } from "./system.ts";

export const actionHandlers = Object.freeze(Object.assign(
  Object.create(null),
  accessActionHandlers,
  cardDataActionHandlers,
  inboxActionHandlers,
  customerActionHandlers,
  systemActionHandlers,
));
