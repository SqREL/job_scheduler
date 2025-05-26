require 'spec_helper'
require_relative '../lib/job'

RSpec.describe Job do
  let(:job_name) { 'test_job' }
  let(:job_path) { File.join(@temp_dir, job_name) }
  let(:config_content) { { 'schedule' => '0 */6 * * *', 'description' => 'Test job' } }
  let(:execute_content) { 'puts "Hello, world!"' }
  let(:logger) { double('Logger', info: nil, debug: nil, error: nil) }

  before do
    FileUtils.mkdir_p(job_path)
    File.write(File.join(job_path, 'config.yml'), config_content.to_yaml)
    File.write(File.join(job_path, 'execute.rb'), execute_content)
  end

  describe '#initialize' do
    context 'with valid job' do
      it 'creates a job instance' do
        job = Job.new(job_name, job_path)
        expect(job.name).to eq(job_name)
        expect(job.path).to eq(job_path)
        expect(job.config).to include('schedule' => '0 */6 * * *')
      end
    end

    context 'with invalid job name' do
      it 'raises validation error for special characters' do
        expect { Job.new('job with spaces', job_path) }
          .to raise_error(JobSchedulerErrors::ValidationError, /must contain only alphanumeric/)
      end

      it 'raises validation error for empty name' do
        expect { Job.new('', job_path) }
          .to raise_error(JobSchedulerErrors::ValidationError)
      end
    end

    context 'with invalid path' do
      it 'raises validation error for non-existent directory' do
        expect { Job.new(job_name, '/non/existent/path') }
          .to raise_error(JobSchedulerErrors::ValidationError, /must be a valid directory/)
      end
    end

    context 'with invalid config' do
      it 'raises error for missing schedule' do
        File.write(File.join(job_path, 'config.yml'), { 'description' => 'No schedule' }.to_yaml)
        expect { Job.new(job_name, job_path) }
          .to raise_error(JobSchedulerErrors::JobConfigurationError, /must have a schedule/)
      end

      it 'raises error for invalid YAML' do
        File.write(File.join(job_path, 'config.yml'), "invalid: yaml: content:")
        expect { Job.new(job_name, job_path) }
          .to raise_error(JobSchedulerErrors::JobConfigurationError, /Invalid YAML/)
      end

      it 'raises error for unsafe YAML constructs' do
        File.write(File.join(job_path, 'config.yml'), "schedule: !!python/object")
        expect { Job.new(job_name, job_path) }
          .to raise_error(JobSchedulerErrors::SecurityError, /unsafe constructs/)
      end
    end
  end

  describe '#valid?' do
    let(:job) { Job.new(job_name, job_path) }

    it 'returns true for valid job' do
      expect(job.valid?).to be true
    end

    it 'returns false when config.yml is missing' do
      File.delete(File.join(job_path, 'config.yml'))
      job = Job.new(job_name, job_path)
      expect(job.valid?).to be false
    end

    it 'returns false when execute.rb is missing' do
      File.delete(File.join(job_path, 'execute.rb'))
      job = Job.new(job_name, job_path)
      expect(job.valid?).to be false
    end
  end

  describe '#execute' do
    let(:job) { Job.new(job_name, job_path) }

    context 'with successful execution' do
      it 'executes the job and returns success result' do
        result = job.execute(logger)
        
        expect(result[:success]).to be true
        expect(result[:output]).to include('Hello, world!')
        expect(result[:execution_time]).to be > 0
        expect(logger).to have_received(:info).with(/Executing job: #{job_name}/)
        expect(logger).to have_received(:info).with(/completed successfully/)
      end
    end

    context 'with job timeout' do
      let(:config_content) { { 'schedule' => '0 */6 * * *', 'timeout' => 1 } }
      let(:execute_content) { 'sleep 3' }

      it 'raises timeout error' do
        expect { job.execute(logger) }
          .to raise_error(JobSchedulerErrors::JobTimeoutError, /timed out after 1 seconds/)
      end
    end

    context 'with job failure' do
      let(:execute_content) { 'exit 1' }

      it 'raises execution error' do
        expect { job.execute(logger) }
          .to raise_error(JobSchedulerErrors::JobExecutionError, /failed with exit code 1/)
      end
    end

    context 'with environment variables' do
      let(:config_content) do
        {
          'schedule' => '0 */6 * * *',
          'environment' => { 'TEST_VAR' => 'test_value' }
        }
      end
      let(:execute_content) { 'puts ENV["TEST_VAR"]' }

      it 'sets environment variables during execution' do
        result = job.execute(logger)
        expect(result[:output]).to include('test_value')
      end
    end

    context 'with unsafe execute file' do
      let(:execute_content) { 'system("ls")' }

      it 'raises security error' do
        expect { job.execute(logger) }
          .to raise_error(JobSchedulerErrors::SecurityError, /unsafe system calls/)
      end
    end
  end

  describe '#timeout' do
    it 'returns configured timeout' do
      config = { 'schedule' => '0 */6 * * *', 'timeout' => 120 }
      File.write(File.join(job_path, 'config.yml'), config.to_yaml)
      job = Job.new(job_name, job_path)
      expect(job.timeout).to eq(120)
    end

    it 'returns default timeout when not configured' do
      job = Job.new(job_name, job_path)
      expect(job.timeout).to eq(300)
    end
  end

  describe '#environment' do
    it 'returns configured environment' do
      config = { 'schedule' => '0 */6 * * *', 'environment' => { 'FOO' => 'bar' } }
      File.write(File.join(job_path, 'config.yml'), config.to_yaml)
      job = Job.new(job_name, job_path)
      expect(job.environment).to eq({ 'FOO' => 'bar' })
    end

    it 'returns empty hash when not configured' do
      job = Job.new(job_name, job_path)
      expect(job.environment).to eq({})
    end

    context 'with secrets management' do
      let(:secrets_file) { File.join(@temp_dir, 'job_secrets.json.enc') }
      let(:key_file) { File.join(@temp_dir, 'job_secrets.key') }

      before do
        # Set up secrets for testing
        secrets_manager = JobSchedulerComponents::SecretsManager.new(
          secrets_file: secrets_file,
          key_file: key_file
        )
        secrets_manager.set('TEST_SECRET', 'secret_value')
        
        # Set up environment variable
        ENV['TEST_ENV_VAR'] = 'env_value'
      end

      after do
        ENV.delete('TEST_ENV_VAR')
      end

      it 'resolves secret references in environment variables' do
        config = {
          'schedule' => '0 */6 * * *',
          'environment' => {
            'SECRET_VAL' => 'secret:TEST_SECRET',
            'PLAIN_VAL' => 'plain_value'
          }
        }
        File.write(File.join(job_path, 'config.yml'), config.to_yaml)
        
        # Mock the secrets manager to use our test files
        allow(JobSchedulerComponents::SecretsManager).to receive(:new).and_return(
          JobSchedulerComponents::SecretsManager.new(
            secrets_file: secrets_file,
            key_file: key_file
          )
        )
        
        job = Job.new(job_name, job_path)
        env = job.environment
        
        expect(env['SECRET_VAL']).to eq('secret_value')
        expect(env['PLAIN_VAL']).to eq('plain_value')
      end

      it 'resolves environment variable references' do
        config = {
          'schedule' => '0 */6 * * *',
          'environment' => {
            'ENV_VAL' => 'env:TEST_ENV_VAR',
            'PLAIN_VAL' => 'plain_value'
          }
        }
        File.write(File.join(job_path, 'config.yml'), config.to_yaml)
        
        # Mock the secrets manager
        allow(JobSchedulerComponents::SecretsManager).to receive(:new).and_return(
          JobSchedulerComponents::SecretsManager.new(
            secrets_file: secrets_file,
            key_file: key_file
          )
        )
        
        job = Job.new(job_name, job_path)
        env = job.environment
        
        expect(env['ENV_VAL']).to eq('env_value')
        expect(env['PLAIN_VAL']).to eq('plain_value')
      end

      it 'falls back to plain environment when secrets unavailable' do
        config = {
          'schedule' => '0 */6 * * *',
          'environment' => {
            'SECRET_VAL' => 'secret:NONEXISTENT_SECRET',
            'PLAIN_VAL' => 'plain_value'
          }
        }
        File.write(File.join(job_path, 'config.yml'), config.to_yaml)
        
        # Mock secrets manager to raise an error
        allow(JobSchedulerComponents::SecretsManager).to receive(:new).and_raise(StandardError.new('Secrets unavailable'))
        
        # Capture warnings by monitoring STDERR
        original_stderr = $stderr
        captured_warnings = StringIO.new
        $stderr = captured_warnings
        
        job = Job.new(job_name, job_path)
        env = job.environment
        
        # Restore stderr
        $stderr = original_stderr
        warning_output = captured_warnings.string
        
        # Should fall back to original config
        expect(env['SECRET_VAL']).to eq('secret:NONEXISTENT_SECRET')
        expect(env['PLAIN_VAL']).to eq('plain_value')
        expect(warning_output).to match(/Warning: Failed to resolve secrets/)
      end
    end
  end
end