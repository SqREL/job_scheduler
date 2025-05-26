# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Essential Commands

### Development Setup
```bash
# Install dependencies using asdf (required for this project)
asdf exec bundle install

# Make the entry point executable
chmod +x bin/scheduler
```

### Testing
```bash
# Run full test suite (59 tests total)
asdf exec bundle exec rspec

# Run specific test files
asdf exec bundle exec rspec spec/job_spec.rb
asdf exec bundle exec rspec spec/job_scheduler_spec.rb
asdf exec bundle exec rspec spec/integration_spec.rb

# Run with progress format for quick overview
asdf exec bundle exec rspec --format progress

# Run tests with documentation format for detailed output
asdf exec bundle exec rspec --format documentation
```

### Running the Application
```bash
# Basic usage - requires Git repository URL
./bin/scheduler -r https://github.com/your/jobs-repo.git

# Force sync only (useful for testing)
./bin/scheduler -r https://github.com/your/jobs-repo.git -f

# With verbose logging
./bin/scheduler -r https://github.com/your/jobs-repo.git -v

# Custom jobs directory
./bin/scheduler -r https://github.com/your/jobs-repo.git -d /custom/path
```

### Docker Operations
```bash
# Build and run with docker-compose
docker-compose up -d

# View logs
docker-compose logs -f scheduler

# Build manually
docker build -t ruby-scheduler .
```

## Architecture Overview

### Core Components

**JobScheduler (`lib/job_scheduler.rb`)**
- Main orchestrator that manages the entire job lifecycle
- Handles Git repository synchronization every 15 minutes
- Uses Rufus::Scheduler for cron-based job scheduling
- Integrates with JobHistory for execution tracking
- Provides health check and statistics endpoints

**Job (`lib/job.rb`)**
- Represents individual job definitions with validation
- Handles job execution with timeout and environment variable support
- Implements comprehensive security validation (YAML safety, system call blocking)
- Validates job configurations and file structures

**JobHistory (`lib/job_scheduler/job_history.rb`)**
- Tracks job execution history with persistent JSON storage
- Provides statistics and failure analysis
- Maintains rolling history (last 1000 executions)
- Supports per-job and global statistics

**Error Hierarchy (`lib/job_scheduler/errors.rb`)**
- Custom exception classes for specific error scenarios
- Enables precise error handling and logging
- Types: ValidationError, SecurityError, JobExecutionError, JobTimeoutError, etc.

### Key Architectural Patterns

**Security-First Design**
- Input validation at multiple layers (job names, repository URLs, YAML content)
- System call detection to prevent unsafe command execution
- Environment variable sanitization and validation
- YAML safety checks to prevent code injection

**Job Isolation and Safety**
- Each job runs in its own directory context
- Configurable timeouts (1-3600 seconds)
- Environment variable scoping per job
- Exit code tracking for success/failure determination

**Monitoring and Observability**
- Structured logging with timestamps
- Job execution history with performance metrics
- Health check endpoints for system monitoring
- Failure tracking and success rate calculations

### Job Repository Structure
Jobs are loaded from a Git repository with this required structure:
```
job_name/
├── config.yml    # Schedule, timeout, environment vars
└── execute.rb    # The actual job script
```

**config.yml Requirements:**
- `schedule`: Cron expression (required)
- `timeout`: Seconds (optional, default 300)
- `environment`: Hash of env vars (optional)
- `description`: Human readable description (optional)

### Testing Strategy

**Test Organization:**
- `spec/job_spec.rb`: Unit tests for Job class (19 tests)
- `spec/job_scheduler_spec.rb`: Unit tests for JobScheduler class (19 tests)
- `spec/job_scheduler/job_history_spec.rb`: Unit tests for JobHistory (14 tests)
- `spec/integration_spec.rb`: End-to-end workflow tests (7 tests)

**Key Test Scenarios:**
- Security validation (unsafe YAML, system calls)
- Job execution with timeouts and environment variables
- Error handling for various failure modes
- Repository synchronization and job loading
- Job history tracking and statistics

### Important Development Notes

**Ruby Environment:**
- Must use `asdf exec bundle` for all Ruby commands
- Uses custom error namespaces (JobSchedulerErrors, JobSchedulerComponents)
- RSpec configuration includes Timecop for time-based testing

**Security Considerations:**
- Job execution happens in chdir context for isolation
- System call validation prevents `system()`, `exec()`, backticks
- YAML loading uses safe_load with restricted classes
- Environment variables are sanitized (no RUBY_/GEM_ prefixes)

**Docker Configuration:**
- Runs as non-root user (deploy:1000)
- Read-only filesystem with specific tmpfs mounts
- Health checks integrated for monitoring
- Multi-stage build optimization for production

**Deployment Options:**
- Systemd service configuration included
- Docker/docker-compose ready
- VPS deployment with screen/tmux support
- Git repository auto-sync every 15 minutes