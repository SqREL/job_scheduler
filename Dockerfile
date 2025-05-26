# Base stage with common dependencies
FROM ruby:3.2-alpine AS base

RUN apk add --no-cache git build-base

# Create non-root user
RUN addgroup -g 1000 deploy && \
    adduser -D -s /bin/sh -u 1000 -G deploy deploy

WORKDIR /app

# Copy dependency files
COPY Gemfile* ./

# Test stage for CI
FROM base AS test

RUN bundle config set --local deployment 'false' && \
    bundle install

# Copy application code
COPY . .
RUN chmod +x bin/scheduler bin/secrets

# Set up directories with proper permissions
RUN mkdir -p /app/jobs /app/logs && \
    chown -R deploy:deploy /app

# Switch to non-root user
USER deploy

# Default command for test stage
CMD ["bundle", "exec", "rspec"]

# Production stage
FROM base AS production

RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install

# Copy application code
COPY . .
RUN chmod +x bin/scheduler bin/secrets

# Set up directories with proper permissions
RUN mkdir -p /app/jobs /app/logs && \
    chown -R deploy:deploy /app

# Switch to non-root user
USER deploy

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ruby -e "require_relative 'lib/job_scheduler'; puts 'healthy'" || exit 1

CMD ["sh", "-c", "exec bin/scheduler -r \"$REPO_URL\""]
