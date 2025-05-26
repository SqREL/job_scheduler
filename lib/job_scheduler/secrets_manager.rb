require 'json'
require 'fileutils'
require 'base64'
require 'openssl'
require_relative 'errors'

module JobSchedulerComponents
  class SecretsManager
    attr_reader :secrets_file, :key_file

    def initialize(secrets_file: './secrets.json.enc', key_file: './secrets.key')
      @secrets_file = File.expand_path(secrets_file)
      @key_file = File.expand_path(key_file)
      @cache = {}
      ensure_key_exists
    end

    # Get a secret value by key
    def get(key)
      return @cache[key] if @cache.key?(key)
      
      secrets = load_secrets
      value = secrets[key]
      
      # Cache for performance but don't cache nil values
      @cache[key] = value if value
      value
    end

    # Set a secret value (encrypts and saves)
    def set(key, value)
      secrets = load_secrets
      secrets[key] = value
      save_secrets(secrets)
      
      # Update cache
      @cache[key] = value
      true
    end

    # Delete a secret
    def delete(key)
      secrets = load_secrets
      deleted_value = secrets.delete(key)
      save_secrets(secrets)
      
      # Remove from cache
      @cache.delete(key)
      !deleted_value.nil?
    end

    # List all secret keys (not values)
    def keys
      load_secrets.keys
    end

    # Check if a secret exists
    def exists?(key)
      load_secrets.key?(key)
    end

    # Resolve environment variables with secret references
    # Supports syntax like: secret:TELEGRAM_BOT_TOKEN or env:HOME
    def resolve_environment(env_hash)
      return {} unless env_hash.is_a?(Hash)
      
      resolved = {}
      env_hash.each do |key, value|
        resolved[key] = resolve_value(value)
      end
      resolved
    end

    # Import secrets from environment variables
    def import_from_env(prefix = 'SECRET_')
      imported = 0
      ENV.each do |key, value|
        if key.start_with?(prefix)
          secret_key = key.sub(prefix, '')
          set(secret_key, value)
          imported += 1
        end
      end
      imported
    end

    # Backup secrets to a different location
    def backup(backup_file)
      return false unless File.exist?(secrets_file)
      FileUtils.cp(secrets_file, backup_file)
      true
    end

    private

    def resolve_value(value)
      return value unless value.is_a?(String)
      
      case value
      when /^secret:(.+)$/
        # Reference to a secret: secret:TELEGRAM_BOT_TOKEN
        secret_key = $1
        get(secret_key) || raise(JobSchedulerErrors::ValidationError, "Secret not found: #{secret_key}")
      when /^env:(.+)$/
        # Reference to environment variable: env:HOME
        env_key = $1
        ENV[env_key] || raise(JobSchedulerErrors::ValidationError, "Environment variable not found: #{env_key}")
      when /^file:(.+)$/
        # Reference to file content: file:/path/to/token.txt
        file_path = $1
        File.read(file_path).strip rescue raise(JobSchedulerErrors::ValidationError, "Cannot read file: #{file_path}")
      else
        # Plain value
        value
      end
    end

    def ensure_key_exists
      return if File.exist?(key_file)
      
      # Generate a new encryption key
      key = OpenSSL::Random.random_bytes(32)
      File.write(key_file, Base64.strict_encode64(key))
      File.chmod(0600, key_file)  # Read/write for owner only
    end

    def encryption_key
      @encryption_key ||= Base64.strict_decode64(File.read(key_file))
    end

    def load_secrets
      return {} unless File.exist?(secrets_file)
      
      encrypted_data = File.read(secrets_file)
      decrypted_json = decrypt(encrypted_data)
      JSON.parse(decrypted_json)
    rescue => e
      raise JobSchedulerErrors::SecurityError, "Failed to load secrets: #{e.message}"
    end

    def save_secrets(secrets)
      json_data = JSON.pretty_generate(secrets)
      encrypted_data = encrypt(json_data)
      
      # Ensure directory exists
      FileUtils.mkdir_p(File.dirname(secrets_file))
      
      # Write with secure permissions
      File.write(secrets_file, encrypted_data)
      File.chmod(0600, secrets_file)  # Read/write for owner only
    end

    def encrypt(data)
      cipher = OpenSSL::Cipher.new('AES-256-GCM')
      cipher.encrypt
      cipher.key = encryption_key
      
      # GCM mode uses 12-byte IV
      iv = cipher.random_iv
      encrypted = cipher.update(data) + cipher.final
      tag = cipher.auth_tag
      
      # Combine IV (12 bytes) + tag (16 bytes) + encrypted data and encode
      combined = iv + tag + encrypted
      Base64.strict_encode64(combined)
    end

    def decrypt(encrypted_data)
      combined = Base64.strict_decode64(encrypted_data)
      
      # Extract IV (12 bytes for GCM), tag (16 bytes), and encrypted data
      iv = combined[0..11]
      tag = combined[12..27]
      encrypted = combined[28..-1]
      
      cipher = OpenSSL::Cipher.new('AES-256-GCM')
      cipher.decrypt
      cipher.key = encryption_key
      cipher.iv = iv
      cipher.auth_tag = tag
      
      cipher.update(encrypted) + cipher.final
    end
  end
end