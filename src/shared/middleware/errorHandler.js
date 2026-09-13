/**
 * Global error handler middleware
 */
const errorHandler = (err, req, res, next) => {
  const statusCode = err.statusCode || err.status || 500;
  const message = err.message || 'Internal server error';

  // Don't leak stack traces in production
  const response = {
    success: false,
    message,
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack }),
  };

  // Log 5xx errors
  if (statusCode >= 500) {
    console.error('Server error:', {
      method: req.method,
      url: req.url,
      status: statusCode,
      error: err.message,
      stack: err.stack,
    });
  }

  res.status(statusCode).json(response);
};

/**
 * Create a standard API error
 */
class AppError extends Error {
  constructor(message, statusCode = 500) {
    super(message);
    this.statusCode = statusCode;
    this.name = 'AppError';
  }
}

module.exports = { errorHandler, AppError };
