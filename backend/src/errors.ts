/** Typed errors that map to stable error codes the app understands. */
export type ErrorCode =
  | 'not_configured'
  | 'upstream_timeout'
  | 'upstream_error'
  | 'invalid_output'
  | 'bad_request'
  | 'unauthorized'
  | 'rate_limited';

export class ServiceError extends Error {
  constructor(
    public readonly code: ErrorCode,
    message: string,
    public readonly status: number = 502,
  ) {
    super(message);
    this.name = 'ServiceError';
  }
}

export function notConfigured(what: string): ServiceError {
  return new ServiceError('not_configured', `${what} is not configured on the server`, 503);
}
