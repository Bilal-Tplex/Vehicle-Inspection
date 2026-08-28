/** An error with an HTTP status attached, thrown by route handlers. */
export class ApiError extends Error {
  constructor(status, message, details = undefined) {
    super(message);
    this.status = status;
    this.details = details;
  }

  static badRequest(message, details) {
    return new ApiError(400, message, details);
  }

  static unauthorized(message = 'Not authenticated') {
    return new ApiError(401, message);
  }

  static forbidden(message = 'You do not have access to this') {
    return new ApiError(403, message);
  }

  static notFound(message = 'Not found') {
    return new ApiError(404, message);
  }

  /** 422 means the payload is wrong; the mobile client will not retry it. */
  static unprocessable(message, details) {
    return new ApiError(422, message, details);
  }
}

/** Wraps an async handler so a rejected promise reaches the error middleware. */
export const asyncRoute = (handler) => (req, res, next) =>
  Promise.resolve(handler(req, res, next)).catch(next);

/**
 * Single error shape for the whole API.
 *
 * The mobile client's `mapToFailure` switches on status code, so the codes here
 * are part of the contract: 401 prompts re-authentication, 422 is terminal, 5xx
 * is retried with backoff.
 */
export function errorHandler(error, req, res, _next) {
  const status = error.status ?? 500;

  if (status >= 500) {
    console.error(`[${req.method} ${req.originalUrl}]`, error);
  }

  res.status(status).json({
    error: {
      message:
        status >= 500 ? 'Something went wrong on the server.' : error.message,
      ...(error.details ? { details: error.details } : {}),
    },
  });
}

export function notFoundHandler(req, res) {
  res.status(404).json({ error: { message: `No route for ${req.method} ${req.originalUrl}` } });
}
