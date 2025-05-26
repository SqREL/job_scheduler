require 'spec_helper'
require 'open3'

RSpec.describe 'Secrets CLI Tool' do
  let(:secrets_bin) { File.join(File.dirname(__FILE__), '..', 'bin', 'secrets') }
  let(:secrets_file) { File.join(@temp_dir, 'cli_test_secrets.json.enc') }
  let(:key_file) { File.join(@temp_dir, 'cli_test_secrets.key') }
  let(:base_command) { "#{secrets_bin} -f #{secrets_file} -k #{key_file}" }

  before do
    # Ensure the secrets binary is executable
    File.chmod(0755, secrets_bin) if File.exist?(secrets_bin)
  end

  def run_command(command)
    stdout, stderr, status = Open3.capture3(command)
    {
      stdout: stdout.strip,
      stderr: stderr.strip,
      success: status.success?,
      exit_code: status.exitstatus
    }
  end

  describe 'help and usage' do
    it 'shows usage when run without arguments' do
      result = run_command(secrets_bin)
      
      expect(result[:success]).to be false
      expect(result[:exit_code]).to eq(1)
      expect(result[:stdout]).to include('Usage: secrets [command] [options]')
    end

    it 'shows help with -h flag' do
      result = run_command("#{secrets_bin} -h")
      
      expect(result[:success]).to be true
      expect(result[:exit_code]).to eq(0)
      expect(result[:stdout]).to include('Usage: secrets [command] [options]')
      expect(result[:stdout]).to include('Commands:')
      expect(result[:stdout]).to include('set <key> <value>')
    end
  end

  describe 'set command' do
    it 'sets a secret successfully' do
      result = run_command("#{base_command} set TEST_SECRET 'secret_value_123'")
      
      expect(result[:success]).to be true
      expect(result[:stdout]).to include("Secret 'TEST_SECRET' set successfully")
    end

    it 'shows error when key or value is missing' do
      result = run_command("#{base_command} set TEST_SECRET")
      
      expect(result[:success]).to be false
      expect(result[:stdout]).to include("Error: 'set' command requires key and value")
    end

    it 'handles values with spaces and special characters' do
      special_value = 'secret with spaces & special chars!'
      result = run_command("#{base_command} set SPECIAL_SECRET '#{special_value}'")
      
      expect(result[:success]).to be true
      expect(result[:stdout]).to include("Secret 'SPECIAL_SECRET' set successfully")
    end
  end

  describe 'get command' do
    before do
      # Set up some test secrets
      run_command("#{base_command} set TEST_GET_SECRET 'get_value_123'")
      run_command("#{base_command} set SHORT_SECRET 'abc'")
    end

    it 'gets an existing secret (masked)' do
      result = run_command("#{base_command} get TEST_GET_SECRET")
      
      expect(result[:success]).to be true
      expect(result[:stdout]).to include("Secret 'TEST_GET_SECRET':")
      # Check for masking pattern (first 3 chars + asterisks + last 3 chars)
      expect(result[:stdout]).to match(/get\*+123/)
    end

    it 'masks short secrets completely' do
      result = run_command("#{base_command} get SHORT_SECRET")
      
      expect(result[:success]).to be true
      expect(result[:stdout]).to include("Secret 'SHORT_SECRET': ***")
    end

    it 'shows error for non-existent secret' do
      result = run_command("#{base_command} get NONEXISTENT_SECRET")
      
      expect(result[:success]).to be false
      expect(result[:stdout]).to include("Secret 'NONEXISTENT_SECRET' not found")
    end

    it 'shows error when key is missing' do
      result = run_command("#{base_command} get")
      
      expect(result[:success]).to be false
      expect(result[:stdout]).to include("Error: 'get' command requires a key")
    end
  end

  describe 'list command' do
    it 'shows empty list when no secrets exist' do
      result = run_command("#{base_command} list")
      
      expect(result[:success]).to be true
      expect(result[:stdout]).to include('No secrets stored')
    end

    it 'lists all secret keys' do
      # Set up test secrets
      run_command("#{base_command} set SECRET_A 'value_a'")
      run_command("#{base_command} set SECRET_B 'value_b'")
      run_command("#{base_command} set SECRET_C 'value_c'")
      
      result = run_command("#{base_command} list")
      
      expect(result[:success]).to be true
      expect(result[:stdout]).to include('Stored secrets:')
      expect(result[:stdout]).to include('SECRET_A')
      expect(result[:stdout]).to include('SECRET_B')
      expect(result[:stdout]).to include('SECRET_C')
    end
  end

  describe 'exists command' do
    before do
      run_command("#{base_command} set EXISTS_SECRET 'exists_value'")
    end

    it 'returns success for existing secret' do
      result = run_command("#{base_command} exists EXISTS_SECRET")
      
      expect(result[:success]).to be true
      expect(result[:exit_code]).to eq(0)
      expect(result[:stdout]).to include("Secret 'EXISTS_SECRET' exists")
    end

    it 'returns failure for non-existent secret' do
      result = run_command("#{base_command} exists NONEXISTENT_SECRET")
      
      expect(result[:success]).to be false
      expect(result[:exit_code]).to eq(1)
      expect(result[:stdout]).to include("Secret 'NONEXISTENT_SECRET' does not exist")
    end

    it 'shows error when key is missing' do
      result = run_command("#{base_command} exists")
      
      expect(result[:success]).to be false
      expect(result[:stdout]).to include("Error: 'exists' command requires a key")
    end
  end

  describe 'delete command' do
    before do
      run_command("#{base_command} set DELETE_ME 'delete_value'")
    end

    it 'deletes existing secret' do
      result = run_command("#{base_command} delete DELETE_ME")
      
      expect(result[:success]).to be true
      expect(result[:stdout]).to include("Secret 'DELETE_ME' deleted successfully")
      
      # Verify it's gone
      check_result = run_command("#{base_command} exists DELETE_ME")
      expect(check_result[:success]).to be false
    end

    it 'shows error for non-existent secret' do
      result = run_command("#{base_command} delete NONEXISTENT_SECRET")
      
      expect(result[:success]).to be false
      expect(result[:stdout]).to include("Secret 'NONEXISTENT_SECRET' not found")
    end

    it 'shows error when key is missing' do
      result = run_command("#{base_command} delete")
      
      expect(result[:success]).to be false
      expect(result[:stdout]).to include("Error: 'delete' command requires a key")
    end
  end

  describe 'import command' do
    before do
      ENV['SECRET_IMPORT_TEST1'] = 'import_value_1'
      ENV['SECRET_IMPORT_TEST2'] = 'import_value_2'
      ENV['NOT_SECRET_TEST'] = 'should_not_import'
    end

    after do
      ENV.delete('SECRET_IMPORT_TEST1')
      ENV.delete('SECRET_IMPORT_TEST2')
      ENV.delete('NOT_SECRET_TEST')
    end

    it 'imports secrets from environment variables' do
      result = run_command("#{base_command} import")
      
      expect(result[:success]).to be true
      expect(result[:stdout]).to include('Imported 2 secrets from environment variables')
      
      # Verify secrets were imported
      check1 = run_command("#{base_command} exists IMPORT_TEST1")
      check2 = run_command("#{base_command} exists IMPORT_TEST2")
      check3 = run_command("#{base_command} exists TEST")  # Should not exist
      
      expect(check1[:success]).to be true
      expect(check2[:success]).to be true
      expect(check3[:success]).to be false
    end

    it 'shows message when no secrets to import' do
      # Clear the environment variables
      ENV.delete('SECRET_IMPORT_TEST1')
      ENV.delete('SECRET_IMPORT_TEST2')
      
      result = run_command("#{base_command} import")
      
      expect(result[:success]).to be true
      expect(result[:stdout]).to include('No secrets found to import')
    end
  end

  describe 'backup command' do
    before do
      run_command("#{base_command} set BACKUP_SECRET 'backup_value'")
    end

    it 'creates backup of secrets file' do
      backup_file = File.join(@temp_dir, 'backup_test.json.enc')
      result = run_command("#{base_command} backup #{backup_file}")
      
      expect(result[:success]).to be true
      expect(result[:stdout]).to include("Secrets backed up to: #{backup_file}")
      expect(File.exist?(backup_file)).to be true
    end

    it 'shows error when backup destination is missing' do
      result = run_command("#{base_command} backup")
      
      expect(result[:success]).to be false
      expect(result[:stdout]).to include("Error: 'backup' command requires a destination file")
    end
  end

  describe 'unknown command' do
    it 'shows error for unknown command' do
      result = run_command("#{base_command} unknown_command")
      
      expect(result[:success]).to be false
      expect(result[:stdout]).to include("Error: Unknown command 'unknown_command'")
      expect(result[:stdout]).to include('Usage: secrets [command] [options]')
    end
  end

  describe 'custom file locations' do
    let(:custom_secrets_file) { File.join(@temp_dir, 'custom_secrets.json.enc') }
    let(:custom_key_file) { File.join(@temp_dir, 'custom_key.key') }

    it 'uses custom file locations when specified' do
      custom_command = "#{secrets_bin} -f #{custom_secrets_file} -k #{custom_key_file}"
      
      result = run_command("#{custom_command} set CUSTOM_SECRET 'custom_value'")
      expect(result[:success]).to be true
      
      # Verify files were created in custom locations
      expect(File.exist?(custom_secrets_file)).to be true
      expect(File.exist?(custom_key_file)).to be true
      
      # Verify we can retrieve the secret
      get_result = run_command("#{custom_command} get CUSTOM_SECRET")
      expect(get_result[:success]).to be true
      expect(get_result[:stdout]).to include("Secret 'CUSTOM_SECRET':")
    end
  end

  describe 'error handling' do
    it 'handles file permission errors gracefully' do
      # This test might not work on all systems, so we'll make it conditional
      if Process.uid != 0  # Skip if running as root
        # Create a directory we can't write to
        read_only_dir = File.join(@temp_dir, 'readonly')
        FileUtils.mkdir_p(read_only_dir)
        File.chmod(0444, read_only_dir)  # Read-only
        
        readonly_secrets = File.join(read_only_dir, 'readonly_secrets.json.enc')
        readonly_key = File.join(read_only_dir, 'readonly_key.key')
        
        readonly_command = "#{secrets_bin} -f #{readonly_secrets} -k #{readonly_key}"
        result = run_command("#{readonly_command} set TEST_SECRET 'value'")
        
        expect(result[:success]).to be false
        expect(result[:stdout]).to include('Error:')
        
        # Clean up
        File.chmod(0755, read_only_dir)
      end
    end
  end
end