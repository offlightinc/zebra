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

export function isGmailWorkflowError(err: unknown): err is
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
