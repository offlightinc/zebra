export class GmailConfigError extends Error {
  readonly _tag = "GmailConfigError";

  constructor(message: string) {
    super(message);
    this.name = "GmailConfigError";
  }
}

export class GmailAuthError extends Error {
  readonly _tag = "GmailAuthError";

  constructor(message: string) {
    super(message);
    this.name = "GmailAuthError";
  }
}

export class GmailDatabaseError extends Error {
  readonly _tag = "GmailDatabaseError";
  readonly operation: string;
  readonly cause: unknown;

  constructor(input: { readonly operation: string; readonly cause: unknown }) {
    super(`Gmail database operation failed: ${input.operation}`);
    this.name = "GmailDatabaseError";
    this.operation = input.operation;
    this.cause = input.cause;
  }
}

export class GmailProviderError extends Error {
  readonly _tag = "GmailProviderError";
  readonly operation: string;
  readonly status?: number;
  readonly cause?: unknown;

  constructor(input: {
    readonly operation: string;
    readonly message: string;
    readonly status?: number;
    readonly cause?: unknown;
  }) {
    super(input.message);
    this.name = "GmailProviderError";
    this.operation = input.operation;
    this.status = input.status;
    this.cause = input.cause;
  }
}

export class GmailNotConnectedError extends Error {
  readonly _tag = "GmailNotConnectedError";

  constructor() {
    super("Gmail is not connected for this user.");
    this.name = "GmailNotConnectedError";
  }
}

export type GmailWorkflowError =
  | GmailConfigError
  | GmailAuthError
  | GmailDatabaseError
  | GmailProviderError
  | GmailNotConnectedError;

const gmailWorkflowErrorTags = new Set([
  "GmailConfigError",
  "GmailAuthError",
  "GmailDatabaseError",
  "GmailProviderError",
  "GmailNotConnectedError",
]);

export function isGmailWorkflowError(err: unknown): err is GmailWorkflowError {
  return Boolean(gmailWorkflowErrorCause(err));
}

export function gmailWorkflowErrorCause(err: unknown): GmailWorkflowError | null {
  if (!err || typeof err !== "object") return null;
  const tag = (err as { _tag?: unknown })._tag;
  if (typeof tag === "string" && gmailWorkflowErrorTags.has(tag)) {
    return err as GmailWorkflowError;
  }
  const fiberCause = effectFiberFailureCause(err);
  const fiberFailure = gmailWorkflowErrorFromEffectCause(fiberCause);
  if (fiberFailure) return fiberFailure;
  const cause = (err as { cause?: unknown }).cause;
  if (cause && cause !== err) return gmailWorkflowErrorCause(cause);
  return null;
}

function effectFiberFailureCause(err: object): unknown {
  const symbol = Object.getOwnPropertySymbols(err).find((candidate) =>
    candidate.description === "effect/Runtime/FiberFailure/Cause"
  );
  return symbol ? (err as Record<symbol, unknown>)[symbol] : null;
}

function gmailWorkflowErrorFromEffectCause(cause: unknown): GmailWorkflowError | null {
  if (!cause || typeof cause !== "object") return null;
  const tag = (cause as { _tag?: unknown })._tag;
  if (tag === "Fail") {
    const failure = (cause as { failure?: unknown; error?: unknown }).failure ??
      (cause as { error?: unknown }).error;
    return gmailWorkflowErrorCause(failure);
  }
  if (tag === "Sequential" || tag === "Parallel") {
    return gmailWorkflowErrorFromEffectCause((cause as { left?: unknown }).left) ??
      gmailWorkflowErrorFromEffectCause((cause as { right?: unknown }).right);
  }
  return gmailWorkflowErrorFromEffectCause((cause as { cause?: unknown }).cause);
}

export function isDirectGmailWorkflowError(err: unknown): err is
  | GmailConfigError
  | GmailAuthError
  | GmailDatabaseError
  | GmailProviderError
  | GmailNotConnectedError {
  return err instanceof GmailConfigError ||
    err instanceof GmailAuthError ||
    err instanceof GmailDatabaseError ||
    err instanceof GmailProviderError ||
    err instanceof GmailNotConnectedError;
}
