# Ruby Lambda Scheduler

A lightweight Ruby application that mimics AWS Lambda functionality by scheduling and executing jobs from a Git repository. Perfect for running on a VPS with automatic job discovery and execution.

## Features

- 🔄 **Auto-sync**: Pulls job definitions from Git repository every 15 minutes
- 📅 **Cron scheduling**: Uses standard cron expressions for job timing
- 🏗️ **Job isolation**: Each job runs in its own directory with separate logs
- 🔧 **Hot reload**: Automatically discovers new jobs without restart
- 📊 **Comprehensive logging**: Tracks execution, errors, and performance
- 🐳 **Docker ready**: Includes Docker and docker-compose configurations
- 🚀 **Force execution**: Manual job sync and execution capability

## Quick Start

### 1. Installation

```bash
# Clone this repository
git clone https://github.com/your/ruby-lambda-scheduler.git
cd ruby-lambda-scheduler

# Install dependencies
bundle install

# Make scheduler executable
chmod +x bin/scheduler
```

### 2. Create Jobs Repository

Create a separate Git repository for your jobs with this structure:

```
jobs-repo/
├── daily_report/
│   ├── README.md
│   ├── config.yml
│   └── execute.rb
├── backup_database/
│   ├── README.md
│   ├── config.yml
│   └── execute.rb
└── health_check/
    ├── README.md
    ├── config.yml
    └── execute.rb
```

### 3. Run Scheduler

```bash
# Start the scheduler
./bin/scheduler -r https://github.com/your/jobs-repo.git

# With custom jobs directory
./bin/scheduler -r https://github.com/your/jobs-repo.git -d /opt/jobs

# Force sync only (useful for testing)
./bin/scheduler -r https://github.com/your/jobs-repo.git -f

# Verbose logging
./bin/scheduler -r https://github.com/your/jobs-repo.git -v
```

## Job Configuration

### config.yml Format

```yaml
# Required: Cron schedule (minute hour day month weekday)
schedule: "0 9 * * 1-5"  # Weekdays at 9 AM

# Optional: Job description
description: "Send daily email report"

# Optional: Timeout in seconds (default: no timeout)
timeout: 300

# Optional: Environment variables for the job
environment:
  API_KEY: "your-api-key"
  DATABASE_URL: "postgresql://user:pass@localhost/db"
  SMTP_HOST: "smtp.example.com"
```

### execute.rb Format

```ruby
#!/usr/bin/env ruby

# Your job logic here
puts "Starting daily report generation..."

# Access environment variables from config.yml
api_key = ENV['API_KEY']
db_url = ENV['DATABASE_URL']

begin
  # Perform your task
  puts "Connecting to database..."
  puts "Generating report..."
  puts "Sending email..."
  
  # Success
  puts "Report sent successfully!"
  exit 0
rescue => e
  # Log error and exit with failure code
  puts "Error: #{e.message}"
  exit 1
end
```

## Cron Schedule Examples

```yaml
# Every 15 minutes
schedule: "*/15 * * * *"

# Daily at 2:30 AM
schedule: "30 2 * * *"

# Weekdays at 9 AM
schedule: "0 9 * * 1-5"

# First day of every month at midnight
schedule: "0 0 1 * *"

# Every Sunday at 3 AM
schedule: "0 3 * * 0"
```

## Deployment

### Systemd Service

```bash
# Copy service file
sudo cp systemd/scheduler.service /etc/systemd/system/

# Edit service file with your settings
sudo nano /etc/systemd/system/scheduler.service

# Enable and start
sudo systemctl enable scheduler
sudo systemctl start scheduler

# Check status
sudo systemctl status scheduler
```

### Docker Deployment

```bash
# Build and run with docker-compose
docker-compose up -d

# Build manually
docker build -t ruby-scheduler .
docker run -e REPO_URL=https://github.com/your/jobs-repo.git ruby-scheduler
```

### Manual VPS Setup

```bash
# Clone to VPS
git clone https://github.com/your/ruby-lambda-scheduler.git /opt/scheduler
cd /opt/scheduler

# Install Ruby and dependencies
bundle install

# Create systemd service or use screen/tmux
screen -S scheduler
./bin/scheduler -r https://github.com/your/jobs-repo.git
```

## Command Line Options

```
Usage: scheduler [options]
    -r, --repo URL                   Git repository URL (required)
    -d, --jobs-dir DIR               Jobs directory (default: ./jobs)
    -v, --verbose                    Verbose logging
    -f, --force-sync                 Force sync and exit
    -h, --help                       Show this help
```

## Example Jobs

### Simple Health Check

**config.yml:**
```yaml
schedule: "*/5 * * * *"  # Every 5 minutes
description: "Check service health"
```

**execute.rb:**
```ruby
#!/usr/bin/env ruby
require 'net/http'

uri = URI('https://your-service.com/health')
response = Net::HTTP.get_response(uri)

if response.code == '200'
  puts "Service healthy"
  exit 0
else
  puts "Service unhealthy: #{response.code}"
  exit 1
end
```

### Database Backup

**config.yml:**
```yaml
schedule: "0 2 * * *"  # Daily at 2 AM
description: "Backup PostgreSQL database"
environment:
  DB_NAME: "production"
  BACKUP_DIR: "/backups"
```

**execute.rb:**
```ruby
#!/usr/bin/env ruby

db_name = ENV['DB_NAME']
backup_dir = ENV['BACKUP_DIR']
timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
backup_file = "#{backup_dir}/#{db_name}_#{timestamp}.sql"

system("pg_dump #{db_name} > #{backup_file}")

if $?.success?
  puts "Backup created: #{backup_file}"
  exit 0
else
  puts "Backup failed"
  exit 1
end
```

## Monitoring and Logs

The scheduler logs all activities to STDOUT. For production:

```bash
# Redirect to log file
./bin/scheduler -r https://github.com/your/jobs-repo.git >> /var/log/scheduler.log 2>&1

# Use systemd for log management
journalctl -u scheduler -f

# Docker logs
docker-compose logs -f scheduler
```

## Troubleshooting

### Common Issues

1. **Git authentication**: Use SSH keys or personal access tokens for private repos
2. **Permission errors**: Ensure scheduler user has write access to jobs directory  
3. **Job failures**: Check individual job logs and exit codes
4. **Schedule conflicts**: Verify cron expressions with online validators

### Debug Mode

```bash
# Run with verbose logging
./bin/scheduler -r https://github.com/your/jobs-repo.git -v

# Test job sync only
./bin/scheduler -r https://github.com/your/jobs-repo.git -f
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## License

MIT License - see LICENSE file for details.

# config/example_job_structure.md
# Example Job Structure

Each job should be in its own directory with the following structure:

```
jobs/
├── email_report/
│   ├── README.md
│   ├── config.yml
│   └── execute.rb
├── data_backup/
│   ├── README.md
│   ├── config.yml
│   └── execute.rb
└── health_check/
    ├── README.md
    ├── config.yml
    └── execute.rb
```

## config.yml format:
```yaml
schedule: "0 9 * * 1-5"  # Cron format: weekdays at 9 AM
description: "Send daily email report"
timeout: 300  # Optional: timeout in seconds
environment:  # Optional: environment variables
  API_KEY: "your-api-key"
  DATABASE_URL: "postgresql://..."
```

## execute.rb format:
```ruby
#!/usr/bin/env ruby

# Your job logic here
puts "Executing email report job..."

# Access environment variables if defined in config.yml
api_key = ENV['API_KEY']

# Perform your task
# Exit with 0 for success, non-zero for failure
exit 0
```
