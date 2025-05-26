require 'spec_helper'
require_relative '../../lib/job_scheduler/secrets_manager'

RSpec.describe JobSchedulerComponents::SecretsManager do
  let(:secrets_file) { File.join(@temp_dir, 'test_secrets.json.enc') }
  let(:key_file) { File.join(@temp_dir, 'test_secrets.key') }
  let(:secrets_manager) { JobSchedulerComponents::SecretsManager.new(secrets_file: secrets_file, key_file: key_file) }

  describe '#initialize' do
    it 'creates encryption key file if it does not exist' do
      # Access secrets_manager to trigger initialization
      secrets_manager
      
      expect(File.exist?(key_file)).to be true
      expect(File.stat(key_file).mode & 0777).to eq(0600)
    end

    it 'uses existing key file if it exists' do
      # Create a key file first
      original_key = 'test_key_content_base64_encoded'
      File.write(key_file, original_key)
      
      manager = JobSchedulerComponents::SecretsManager.new(secrets_file: secrets_file, key_file: key_file)
      
      # Key file should not be overwritten
      expect(File.read(key_file)).to eq(original_key)
    end
  end

  describe '#set and #get' do
    it 'stores and retrieves secrets' do
      key = 'TEST_SECRET'
      value = 'secret_value_123'
      
      expect(secrets_manager.set(key, value)).to be true
      expect(secrets_manager.get(key)).to eq(value)
    end

    it 'returns nil for non-existent secrets' do
      expect(secrets_manager.get('NON_EXISTENT')).to be_nil
    end

    it 'overwrites existing secrets' do
      key = 'TEST_SECRET'
      
      secrets_manager.set(key, 'old_value')
      secrets_manager.set(key, 'new_value')
      
      expect(secrets_manager.get(key)).to eq('new_value')
    end

    it 'persists secrets to encrypted file' do
      key = 'PERSISTENT_SECRET'
      value = 'persistent_value'
      
      secrets_manager.set(key, value)
      
      # Create new manager instance to test persistence
      new_manager = JobSchedulerComponents::SecretsManager.new(secrets_file: secrets_file, key_file: key_file)
      expect(new_manager.get(key)).to eq(value)
    end

    it 'caches secrets for performance' do
      key = 'CACHED_SECRET'
      value = 'cached_value'
      
      secrets_manager.set(key, value)
      
      # First call loads from file
      result1 = secrets_manager.get(key)
      
      # Second call should use cache (we can't easily test this directly,
      # but we can verify the result is consistent)
      result2 = secrets_manager.get(key)
      
      expect(result1).to eq(value)
      expect(result2).to eq(value)
    end
  end

  describe '#delete' do
    it 'deletes existing secrets' do
      key = 'DELETE_ME'
      value = 'delete_value'
      
      secrets_manager.set(key, value)
      expect(secrets_manager.exists?(key)).to be true
      
      expect(secrets_manager.delete(key)).to be true
      expect(secrets_manager.exists?(key)).to be false
      expect(secrets_manager.get(key)).to be_nil
    end

    it 'returns false for non-existent secrets' do
      expect(secrets_manager.delete('NON_EXISTENT')).to be false
    end

    it 'removes secret from cache' do
      key = 'CACHE_DELETE'
      value = 'cache_value'
      
      secrets_manager.set(key, value)
      secrets_manager.get(key)  # Load into cache
      
      secrets_manager.delete(key)
      
      expect(secrets_manager.get(key)).to be_nil
    end
  end

  describe '#keys' do
    it 'returns empty array when no secrets exist' do
      expect(secrets_manager.keys).to eq([])
    end

    it 'returns all secret keys' do
      secrets_manager.set('KEY1', 'value1')
      secrets_manager.set('KEY2', 'value2')
      secrets_manager.set('KEY3', 'value3')
      
      keys = secrets_manager.keys
      expect(keys).to contain_exactly('KEY1', 'KEY2', 'KEY3')
    end
  end

  describe '#exists?' do
    it 'returns true for existing secrets' do
      secrets_manager.set('EXISTS', 'value')
      expect(secrets_manager.exists?('EXISTS')).to be true
    end

    it 'returns false for non-existent secrets' do
      expect(secrets_manager.exists?('DOES_NOT_EXIST')).to be false
    end
  end

  describe '#resolve_environment' do
    before do
      secrets_manager.set('SECRET_KEY', 'secret_value')
      secrets_manager.set('API_TOKEN', 'token_123')
      
      # Set up test environment variable
      ENV['TEST_ENV_VAR'] = 'env_value'
      
      # Create test file
      @test_file = File.join(@temp_dir, 'test_file.txt')
      File.write(@test_file, 'file_content')
    end

    after do
      ENV.delete('TEST_ENV_VAR')
    end

    it 'resolves secret references' do
      env_hash = {
        'SECRET_VALUE' => 'secret:SECRET_KEY',
        'PLAIN_VALUE' => 'plain_text'
      }
      
      resolved = secrets_manager.resolve_environment(env_hash)
      
      expect(resolved['SECRET_VALUE']).to eq('secret_value')
      expect(resolved['PLAIN_VALUE']).to eq('plain_text')
    end

    it 'resolves environment variable references' do
      env_hash = {
        'ENV_VALUE' => 'env:TEST_ENV_VAR',
        'PLAIN_VALUE' => 'plain_text'
      }
      
      resolved = secrets_manager.resolve_environment(env_hash)
      
      expect(resolved['ENV_VALUE']).to eq('env_value')
      expect(resolved['PLAIN_VALUE']).to eq('plain_text')
    end

    it 'resolves file references' do
      env_hash = {
        'FILE_VALUE' => "file:#{@test_file}",
        'PLAIN_VALUE' => 'plain_text'
      }
      
      resolved = secrets_manager.resolve_environment(env_hash)
      
      expect(resolved['FILE_VALUE']).to eq('file_content')
      expect(resolved['PLAIN_VALUE']).to eq('plain_text')
    end

    it 'handles mixed reference types' do
      env_hash = {
        'SECRET_VAL' => 'secret:SECRET_KEY',
        'ENV_VAL' => 'env:TEST_ENV_VAR',
        'FILE_VAL' => "file:#{@test_file}",
        'PLAIN_VAL' => 'plain_text'
      }
      
      resolved = secrets_manager.resolve_environment(env_hash)
      
      expect(resolved['SECRET_VAL']).to eq('secret_value')
      expect(resolved['ENV_VAL']).to eq('env_value')
      expect(resolved['FILE_VAL']).to eq('file_content')
      expect(resolved['PLAIN_VAL']).to eq('plain_text')
    end

    it 'raises error for non-existent secret reference' do
      env_hash = { 'BAD_SECRET' => 'secret:NON_EXISTENT' }
      
      expect { secrets_manager.resolve_environment(env_hash) }
        .to raise_error(JobSchedulerErrors::ValidationError, /Secret not found: NON_EXISTENT/)
    end

    it 'raises error for non-existent environment variable' do
      env_hash = { 'BAD_ENV' => 'env:NON_EXISTENT_ENV' }
      
      expect { secrets_manager.resolve_environment(env_hash) }
        .to raise_error(JobSchedulerErrors::ValidationError, /Environment variable not found: NON_EXISTENT_ENV/)
    end

    it 'raises error for non-existent file' do
      env_hash = { 'BAD_FILE' => 'file:/non/existent/file' }
      
      expect { secrets_manager.resolve_environment(env_hash) }
        .to raise_error(JobSchedulerErrors::ValidationError, /Cannot read file: \/non\/existent\/file/)
    end

    it 'returns empty hash for nil input' do
      expect(secrets_manager.resolve_environment(nil)).to eq({})
    end

    it 'returns empty hash for non-hash input' do
      expect(secrets_manager.resolve_environment('not a hash')).to eq({})
    end
  end

  describe '#import_from_env' do
    before do
      ENV['SECRET_TEST_KEY'] = 'test_value'
      ENV['SECRET_ANOTHER_KEY'] = 'another_value'
      ENV['NOT_SECRET_KEY'] = 'ignored_value'
    end

    after do
      ENV.delete('SECRET_TEST_KEY')
      ENV.delete('SECRET_ANOTHER_KEY')
      ENV.delete('NOT_SECRET_KEY')
    end

    it 'imports environment variables with SECRET_ prefix' do
      imported_count = secrets_manager.import_from_env('SECRET_')
      
      expect(imported_count).to eq(2)
      expect(secrets_manager.get('TEST_KEY')).to eq('test_value')
      expect(secrets_manager.get('ANOTHER_KEY')).to eq('another_value')
      expect(secrets_manager.get('KEY')).to be_nil  # NOT_SECRET_KEY should not be imported
    end

    it 'returns 0 when no matching environment variables exist' do
      imported_count = secrets_manager.import_from_env('NONEXISTENT_')
      expect(imported_count).to eq(0)
    end

    it 'uses custom prefix' do
      ENV['CUSTOM_TEST'] = 'custom_value'
      
      imported_count = secrets_manager.import_from_env('CUSTOM_')
      
      expect(imported_count).to eq(1)
      expect(secrets_manager.get('TEST')).to eq('custom_value')
      
      ENV.delete('CUSTOM_TEST')
    end
  end

  describe '#backup' do
    it 'creates backup of secrets file' do
      secrets_manager.set('BACKUP_SECRET', 'backup_value')
      
      backup_file = File.join(@temp_dir, 'backup.json.enc')
      expect(secrets_manager.backup(backup_file)).to be true
      
      expect(File.exist?(backup_file)).to be true
      
      # Verify backup works by loading from it
      new_manager = JobSchedulerComponents::SecretsManager.new(
        secrets_file: backup_file, 
        key_file: key_file
      )
      expect(new_manager.get('BACKUP_SECRET')).to eq('backup_value')
    end

    it 'returns false when no secrets file exists' do
      backup_file = File.join(@temp_dir, 'backup.json.enc')
      expect(secrets_manager.backup(backup_file)).to be false
    end
  end

  describe 'encryption and security' do
    it 'creates encrypted files with proper permissions' do
      secrets_manager.set('SECURITY_TEST', 'secure_value')
      
      expect(File.exist?(secrets_file)).to be true
      expect(File.stat(secrets_file).mode & 0777).to eq(0600)
      expect(File.stat(key_file).mode & 0777).to eq(0600)
    end

    it 'cannot decrypt with wrong key' do
      secrets_manager.set('DECRYPT_TEST', 'decrypt_value')
      
      # Create new manager with different key file
      wrong_key_file = File.join(@temp_dir, 'wrong_key.key')
      wrong_manager = JobSchedulerComponents::SecretsManager.new(
        secrets_file: secrets_file,
        key_file: wrong_key_file
      )
      
      expect { wrong_manager.get('DECRYPT_TEST') }
        .to raise_error(JobSchedulerErrors::SecurityError, /Failed to load secrets/)
    end

    it 'handles corrupted secrets file gracefully' do
      secrets_manager.set('CORRUPT_TEST', 'corrupt_value')
      
      # Corrupt the file with invalid base64
      File.write(secrets_file, 'corrupted_data_not_base64!')
      
      # Clear cache so it has to reload from file
      secrets_manager.instance_variable_set(:@cache, {})
      
      expect { secrets_manager.get('CORRUPT_TEST') }
        .to raise_error(JobSchedulerErrors::SecurityError, /Failed to load secrets/)
    end
  end

  describe 'file content trimming' do
    it 'strips whitespace from file content' do
      test_file = File.join(@temp_dir, 'whitespace_file.txt')
      File.write(test_file, "  content_with_whitespace  \n")
      
      env_hash = { 'FILE_VAL' => "file:#{test_file}" }
      resolved = secrets_manager.resolve_environment(env_hash)
      
      expect(resolved['FILE_VAL']).to eq('content_with_whitespace')
    end
  end
end