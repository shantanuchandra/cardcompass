import { nextObservationAt } from "./recurrence_policy.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function throwsInvalid(input: Parameters<typeof nextObservationAt>[0]): void {
  let error: unknown;
  try {
    nextObservationAt(input);
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error && error.message === "invalid_completed_at",
    "invalid observation time was accepted",
  );
}

const base = {
  cardId: "00000000-0000-4000-8000-000000000000",
  completedAt: "2026-01-31T23:30:00.000Z",
  acquisitionStatus: "available" as const,
  hasActiveCardholder: false,
};

Deno.test("successful observations use deterministic card jitter in the inclusive 30 plus or minus 3 day window", () => {
  const first = nextObservationAt({ ...base, outcome: "success" });
  const repeated = nextObservationAt({ ...base, outcome: "success" });
  assert(first === "2026-03-05T23:30:00.000Z", "literal +3 day jitter changed");
  assert(first === repeated, "same card did not repeat bit-for-bit");

  const different = nextObservationAt({
    ...base,
    cardId: "11111111-1111-4111-8111-111111111111",
    outcome: "not_modified",
  });
  assert(
    different === "2026-02-28T23:30:00.000Z",
    "literal -2 day jitter changed",
  );
  assert(
    String(first) !== String(different),
    "different cards did not distribute jitter",
  );
});

Deno.test("short terminal outcomes use deterministic 7 plus or minus 1 day cadence", () => {
  const expected = new Map(
    [
      ["blocked", "2026-02-06T23:30:00.000Z"],
      ["missing", "2026-02-06T23:30:00.000Z"],
      ["failed", "2026-02-06T23:30:00.000Z"],
    ] as const,
  );
  for (const [outcome, dueAt] of expected) {
    assert(
      nextObservationAt({ ...base, outcome }) === dueAt,
      `${outcome} did not use the short cadence`,
    );
  }
});

Deno.test("UTC-day arithmetic crosses leap and year boundaries without local-time drift", () => {
  assert(
    nextObservationAt({
      ...base,
      cardId: "22222222-2222-4222-8222-222222222222",
      completedAt: "2024-01-31T12:00:00.000Z",
      outcome: "success",
    }) === "2024-03-01T12:00:00.000Z",
    "leap boundary drifted",
  );
  assert(
    nextObservationAt({
      ...base,
      completedAt: "2025-12-31T00:00:00.000Z",
      outcome: "failed",
    }) === "2026-01-06T00:00:00.000Z",
    "year boundary drifted",
  );
  assert(
    nextObservationAt({
      ...base,
      completedAt: "2026-03-07T07:30:00.000Z",
      outcome: "success",
    }) === "2026-04-09T07:30:00.000Z",
    "fixed UTC duration drifted across a daylight-saving transition",
  );
});

Deno.test("held discontinued cards recur and unheld discontinued cards stop", () => {
  assert(
    nextObservationAt({
      ...base,
      acquisitionStatus: "discontinued",
      hasActiveCardholder: true,
      outcome: "success",
    }) === "2026-03-05T23:30:00.000Z",
    "held discontinued card lost the normal cadence",
  );
  assert(
    nextObservationAt({
      ...base,
      acquisitionStatus: "discontinued",
      hasActiveCardholder: false,
      outcome: "success",
    }) === null,
    "unheld discontinued card was scheduled",
  );
});

Deno.test("malformed and future completion timestamps fail closed", () => {
  throwsInvalid({ ...base, completedAt: "not-a-date", outcome: "success" });
  throwsInvalid({
    ...base,
    completedAt: "2026-02-30T00:00:00.000Z",
    outcome: "success",
  });
  throwsInvalid({
    ...base,
    completedAt: "2026-02-20 00:00:00.000Z",
    outcome: "success",
  });
  throwsInvalid({
    ...base,
    completedAt: "2026-02-20T05:30:00.000+05:30",
    outcome: "success",
  });
  throwsInvalid({
    ...base,
    completedAt: "2026-02-20T00:00:00Z",
    outcome: "success",
  });
  throwsInvalid({
    ...base,
    completedAt: "2999-01-01T00:00:00.000Z",
    outcome: "success",
  });
});
