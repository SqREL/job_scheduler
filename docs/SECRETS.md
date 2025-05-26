# Secrets Management

The job scheduler includes a secure secrets management system that encrypts and stores sensitive information like API keys, passwords, and tokens outside of your job configurations.

## Why Use Secrets Management?

**Security Benefits:**
- 🔐 **Encrypted storage** - Secrets are encrypted with AES-256-GCM
- 🚫 **No secrets in Git** - Keep sensitive data out of your job repository
- 🔄 **Easy rotation** - Update secrets without touching job configs
- 🎯 **Centralized management** - One place to manage all secrets
- 👥 **Team-friendly** - Share job configs without exposing secrets

## Quick Start

### 1. Store Secrets

```bash
# Set individual secrets
./bin/secrets set TELEGRAM_BOT_TOKEN "1234567890:ABCdefGHIjklMNOpqrs"
./bin/secrets set DATABASE_PASSWORD "super_secure_password"
./bin/secrets set API_KEY "sk-1234567890abcdef"

# Import from environment variables (SECRET_* prefix)
export SECRET_SLACK_WEBHOOK="https://hooks.slack.com/..."
export SECRET_SMTP_PASSWORD="email_password"
./bin/secrets import
```

### 2. Reference Secrets in Jobs

Instead of hardcoding secrets in `config.yml`:

```yaml
# ❌ INSECURE - Don't do this
environment:
  TELEGRAM_BOT_TOKEN: "1234567890:ABCdefGHIjklMNOpqrs"
  DATABASE_PASSWORD: "super_secure_password"
```

Use secret references:

```yaml
# ✅ SECURE - Do this instead
environment:
  TELEGRAM_BOT_TOKEN: "secret:TELEGRAM_BOT_TOKEN"
  DATABASE_PASSWORD: "secret:DATABASE_PASSWORD"
  API_KEY: "secret:API_KEY"
```

### 3. Mixed References

You can mix different types of references:

```yaml
environment:
  # Secret from encrypted storage
  API_KEY: "secret:OPENAI_API_KEY"
  
  # System environment variable
  HOME_DIR: "env:HOME"
  
  # File content
  SSH_KEY: "file:/etc/secrets/ssh_key"
  
  # Plain text value
  LOG_LEVEL: "INFO"
```

## Secrets CLI Tool

### Basic Commands

```bash
# Set a secret
./bin/secrets set <key> <value>
./bin/secrets set TELEGRAM_BOT_TOKEN "your_token_here"

# Get a secret (shows masked value)
./bin/secrets get TELEGRAM_BOT_TOKEN
# Output: Secret 'TELEGRAM_BOT_TOKEN': 123***...xyz

# List all secret keys
./bin/secrets list

# Check if a secret exists
./bin/secrets exists TELEGRAM_BOT_TOKEN

# Delete a secret
./bin/secrets delete OLD_API_KEY
```

### Advanced Operations

```bash
# Import secrets from environment (SECRET_* prefix)
export SECRET_DATABASE_URL="postgresql://..."
export SECRET_REDIS_URL="redis://..."
./bin/secrets import

# Backup encrypted secrets
./bin/secrets backup ./backup/secrets-$(date +%Y%m%d).json.enc

# Use custom secrets file location
./bin/secrets -f /etc/scheduler/secrets.json.enc set API_KEY "value"
```

## File Structure

The secrets system creates two files:

```
├── secrets.json.enc    # Encrypted secrets (safe to backup)
└── secrets.key         # Encryption key (keep secure!)
```

**Important:** 
- `secrets.key` is the master encryption key - keep it secure!
- `secrets.json.enc` contains encrypted data - safe to backup
- Both files have `600` permissions (owner read/write only)

## Security Features

### Encryption
- **Algorithm**: AES-256-GCM (authenticated encryption)
- **Key size**: 256-bit randomly generated key
- **IV**: Random initialization vector per encryption
- **Authentication**: Built-in authentication prevents tampering

### Access Control
- Files are created with `600` permissions (owner only)
- No secrets are logged or printed in plain text
- CLI tool masks secret values when displaying

### Reference Types

| Type | Syntax | Description | Example |
|------|--------|-------------|---------|
| Secret | `secret:KEY` | Encrypted secret from storage | `secret:API_KEY` |
| Environment | `env:VAR` | System environment variable | `env:HOME` |
| File | `file:PATH` | Content from file | `file:/etc/token` |
| Plain | `value` | Literal string value | `INFO` |

## Best Practices

### 1. Secret Naming
```bash
# Use descriptive, uppercase names with underscores
./bin/secrets set TELEGRAM_BOT_TOKEN "..."
./bin/secrets set DATABASE_PASSWORD "..."
./bin/secrets set OPENAI_API_KEY "..."

# Group related secrets
./bin/secrets set PROD_DB_PASSWORD "..."
./bin/secrets set STAGING_DB_PASSWORD "..."
```

### 2. Environment Setup
```bash
# For development, use environment import
export SECRET_TELEGRAM_BOT_TOKEN="dev_token"
export SECRET_DATABASE_URL="postgresql://localhost/dev"
./bin/secrets import

# For production, set secrets individually
./bin/secrets set TELEGRAM_BOT_TOKEN "prod_token"
./bin/secrets set DATABASE_URL "postgresql://prod-server/db"
```

### 3. Backup Strategy
```bash
# Regular backups
./bin/secrets backup ./backups/secrets-$(date +%Y%m%d).json.enc

# Before major changes
./bin/secrets backup ./backups/secrets-before-update.json.enc
```

### 4. Team Workflows
```bash
# Team member joins:
# 1. They get the secrets.key file securely (not via Git!)
# 2. They restore the encrypted secrets file
# 3. Jobs work immediately without config changes

# Secret rotation:
# 1. Update the secret
./bin/secrets set API_KEY "new_key_value"
# 2. Jobs automatically pick up the new value
# 3. No job config changes needed
```

## Integration Examples

### Telegram Notification Job
```yaml
# config.yml
environment:
  TELEGRAM_BOT_TOKEN: "secret:TELEGRAM_BOT_TOKEN"
  TELEGRAM_CHAT_ID: "secret:TELEGRAM_CHAT_ID"
```

```bash
# Setup
./bin/secrets set TELEGRAM_BOT_TOKEN "1234567890:ABCdefGHI..."
./bin/secrets set TELEGRAM_CHAT_ID "123456789"
```

### Database Backup Job
```yaml
# config.yml
environment:
  DATABASE_URL: "secret:PROD_DATABASE_URL"
  BACKUP_ENCRYPTION_KEY: "secret:BACKUP_ENCRYPTION_KEY"
  S3_ACCESS_KEY: "secret:S3_ACCESS_KEY"
  S3_SECRET_KEY: "secret:S3_SECRET_KEY"
```

### API Monitor Job
```yaml
# config.yml
environment:
  API_KEY: "secret:MONITORING_API_KEY"
  SLACK_WEBHOOK: "secret:SLACK_WEBHOOK_URL"
  PD_INTEGRATION_KEY: "secret:PAGERDUTY_KEY"
```

## Migration from Plain Environment Variables

If you have existing jobs with hardcoded secrets:

```bash
# 1. Extract secrets from your config.yml
# Old config.yml:
#   environment:
#     API_KEY: "sk-1234567890"

# 2. Store the secret
./bin/secrets set API_KEY "sk-1234567890"

# 3. Update config.yml
#   environment:
#     API_KEY: "secret:API_KEY"

# 4. Test the job to ensure it still works
```

## Troubleshooting

### Common Issues

**"Secret not found" error:**
```bash
# Check if secret exists
./bin/secrets list
./bin/secrets exists SECRET_NAME

# Set the missing secret
./bin/secrets set SECRET_NAME "value"
```

**"Failed to load secrets" error:**
- Check file permissions on `secrets.json.enc` and `secrets.key`
- Ensure the encryption key file hasn't been corrupted
- Try restoring from a backup

**Jobs not picking up secret changes:**
- Secrets are resolved at job execution time
- No restart needed - changes take effect immediately
- Check job logs for secret resolution errors

### Recovery

**Lost encryption key:**
```bash
# If you have a backup of secrets.key:
cp backup/secrets.key ./secrets.key

# If key is completely lost:
# Unfortunately, encrypted secrets cannot be recovered
# You'll need to re-enter all secrets
rm secrets.json.enc secrets.key
./bin/secrets set SECRET_NAME "new_value"
```

**Corrupted secrets file:**
```bash
# Restore from backup
cp backup/secrets-20240101.json.enc ./secrets.json.enc

# Or start fresh if no backup
rm secrets.json.enc
# Re-enter secrets as needed
```

## Security Considerations

### Do:
- ✅ Keep `secrets.key` secure and backed up safely
- ✅ Use `600` permissions on secrets files
- ✅ Back up encrypted secrets regularly
- ✅ Rotate secrets periodically
- ✅ Use descriptive secret names

### Don't:
- ❌ Commit `secrets.key` or `secrets.json.enc` to Git
- ❌ Share secrets.key via insecure channels
- ❌ Store secrets in job configs or code
- ❌ Use weak or predictable secret values
- ❌ Log or print secret values in plain text