FROM ruby:3.2-alpine

RUN apk add --no-cache git build-base

# Create non-root user
RUN addgroup -g 1000 deploy && \
    adduser -D -s /bin/sh -u 1000 -G deploy deploy

WORKDIR /app

# Copy dependency files
COPY Gemfile* ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install

# Copy application code
COPY . .
RUN chmod +x bin/scheduler

# Set up directories with proper permissions
RUN mkdir -p /app/jobs /app/logs && \
    chown -R deploy:deploy /app

# Switch to non-root user
USER deploy

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ruby -e "require_relative 'lib/job_scheduler'; puts 'healthy'" || exit 1

CMD ["sh", "-c", "exec bin/scheduler -r \"$REPO_URL\""]
