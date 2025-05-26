require 'spec_helper'
require_relative '../lib/job_scheduler'

RSpec.describe 'Job Scheduler Integration' do
  let(:repo_url) { 'https://github.com/test/repo.git' }
  let(:jobs_dir) { File.join(@temp_dir, 'jobs') }
  let(:job_scheduler) { JobScheduler.new(repo_url: repo_url, jobs_dir: jobs_dir) }

  before do
    FileUtils.mkdir_p(jobs_dir)
    
    # Create a sample job
    job_path = File.join(jobs_dir, 'sample_job')
    FileUtils.mkdir_p(job_path)
    
    config = {
      'schedule' => '0 */6 * * *',
      'description' => 'Sample job for integration testing',
      'timeout' => 10,
      'environment' => { 'TEST_ENV' => 'integration_test' }
    }
    
    File.write(File.join(job_path, 'config.yml'), config.to_yaml)
    File.write(File.join(job_path, 'execute.rb'), <<~RUBY)
      puts "Sample job executed"
      puts "Environment: \#{ENV['TEST_ENV']}"
      
      # Simulate some work
      sleep 0.1
      
      puts "Job completed successfully"
    RUBY
  end

  describe 'end-to-end job execution' do
    it 'loads and tracks job execution successfully' do
      # Load jobs
      job_scheduler.send(:reload_jobs)
      
      # Verify job was loaded
      scheduled_jobs = job_scheduler.scheduler.jobs
      expect(scheduled_jobs).not_to be_empty
      
      # Find our job (excluding the sync job)
      job_cron = scheduled_jobs.find { |j| j.original != '15m' }
      expect(job_cron).not_to be_nil
      expect(job_cron.original).to eq('0 */6 * * *')
      
      # Execute the job manually to test execution
      job = Job.new('sample_job', File.join(jobs_dir, 'sample_job'))
      result = job.execute(job_scheduler.logger)
      
      # Verify execution result
      expect(result[:success]).to be true
      expect(result[:output]).to include('Sample job executed')
      expect(result[:output]).to include('Environment: integration_test')
      expect(result[:output]).to include('Job completed successfully')
      expect(result[:execution_time]).to be > 0
    end

    it 'handles job failures gracefully' do
      # Create a failing job
      failing_job_path = File.join(jobs_dir, 'failing_job')
      FileUtils.mkdir_p(failing_job_path)
      
      config = { 'schedule' => '0 */6 * * *', 'description' => 'Failing job' }
      File.write(File.join(failing_job_path, 'config.yml'), config.to_yaml)
      File.write(File.join(failing_job_path, 'execute.rb'), <<~RUBY)
        puts "This job will fail"
        exit 1
      RUBY
      
      job = Job.new('failing_job', failing_job_path)
      
      expect { job.execute(job_scheduler.logger) }
        .to raise_error(JobSchedulerErrors::JobExecutionError, /failed with exit code 1/)
    end

    it 'handles job timeouts correctly' do
      # Create a long-running job
      timeout_job_path = File.join(jobs_dir, 'timeout_job')
      FileUtils.mkdir_p(timeout_job_path)
      
      config = { 'schedule' => '0 */6 * * *', 'timeout' => 1 }
      File.write(File.join(timeout_job_path, 'config.yml'), config.to_yaml)
      File.write(File.join(timeout_job_path, 'execute.rb'), <<~RUBY)
        puts "Starting long job"
        sleep 5
        puts "This should not be reached"
      RUBY
      
      job = Job.new('timeout_job', timeout_job_path)
      
      expect { job.execute(job_scheduler.logger) }
        .to raise_error(JobSchedulerErrors::JobTimeoutError, /timed out after 1 seconds/)
    end
  end

  describe 'job history tracking' do
    it 'tracks successful and failed executions' do
      # Create a fresh scheduler with unique history file
      fresh_scheduler = JobScheduler.new(repo_url: repo_url, jobs_dir: jobs_dir)
      unique_history_file = File.join(@temp_dir, 'unique_history.json')
      fresh_history = JobSchedulerComponents::JobHistory.new(history_file: unique_history_file)
      fresh_scheduler.instance_variable_set(:@job_history, fresh_history)
      
      # Execute a successful job
      job = Job.new('sample_job', File.join(jobs_dir, 'sample_job'))
      fresh_scheduler.send(:execute_job_with_tracking, job)
      
      # Check history
      expect(fresh_history.total_executions).to eq(1)
      
      stats = fresh_history.stats
      expect(stats[:successful]).to eq(1)
      expect(stats[:failed]).to eq(0)
      expect(stats[:success_rate]).to eq(100.0)
    end
  end

  describe 'health check' do
    it 'provides comprehensive health information' do
      health = job_scheduler.health_check
      
      expect(health).to include(
        status: 'healthy',
        active_jobs: 0,
        total_executions: be >= 0,
        recent_failures: be_an(Array),
        repository_status: be_a(String)
      )
    end
  end

  describe 'security validation' do
    it 'rejects jobs with unsafe system calls' do
      unsafe_job_path = File.join(jobs_dir, 'unsafe_job')
      FileUtils.mkdir_p(unsafe_job_path)
      
      config = { 'schedule' => '0 */6 * * *' }
      File.write(File.join(unsafe_job_path, 'config.yml'), config.to_yaml)
      File.write(File.join(unsafe_job_path, 'execute.rb'), <<~RUBY)
        system("echo 'unsafe command'")
      RUBY
      
      expect { Job.new('unsafe_job', unsafe_job_path) }
        .to raise_error(JobSchedulerErrors::SecurityError, /unsafe system calls/)
    end

    it 'validates environment variables' do
      invalid_env_job_path = File.join(jobs_dir, 'invalid_env_job')
      FileUtils.mkdir_p(invalid_env_job_path)
      
      config = {
        'schedule' => '0 */6 * * *',
        'environment' => { 'invalid-var' => 'value' }
      }
      File.write(File.join(invalid_env_job_path, 'config.yml'), config.to_yaml)
      File.write(File.join(invalid_env_job_path, 'execute.rb'), 'puts "test"')
      
      expect { Job.new('invalid_env_job', invalid_env_job_path) }
        .to raise_error(JobSchedulerErrors::ValidationError, /Invalid environment variable name/)
    end
  end

  describe 'secrets management integration' do
    let(:secrets_file) { File.join(@temp_dir, 'integration_secrets.json.enc') }
    let(:key_file) { File.join(@temp_dir, 'integration_secrets.key') }
    let(:secrets_manager) { JobSchedulerComponents::SecretsManager.new(secrets_file: secrets_file, key_file: key_file) }

    before do
      # Set up secrets for testing
      secrets_manager.set('TEST_API_KEY', 'secret_api_key_123')
      secrets_manager.set('TEST_TOKEN', 'secret_token_456')
      
      # Set up environment variable
      ENV['INTEGRATION_TEST_VAR'] = 'integration_env_value'
    end

    after do
      ENV.delete('INTEGRATION_TEST_VAR')
    end

    it 'executes jobs with secret references successfully' do
      secrets_job_path = File.join(jobs_dir, 'secrets_job')
      FileUtils.mkdir_p(secrets_job_path)
      
      config = {
        'schedule' => '0 */6 * * *',
        'description' => 'Job with secrets',
        'environment' => {
          'API_KEY' => 'secret:TEST_API_KEY',
          'TOKEN' => 'secret:TEST_TOKEN',
          'ENV_VAR' => 'env:INTEGRATION_TEST_VAR',
          'PLAIN_VAR' => 'plain_value'
        }
      }
      File.write(File.join(secrets_job_path, 'config.yml'), config.to_yaml)
      
      # Create a job that outputs the environment variables
      File.write(File.join(secrets_job_path, 'execute.rb'), <<~RUBY)
        puts "API_KEY: \#{ENV['API_KEY']}"
        puts "TOKEN: \#{ENV['TOKEN']}"
        puts "ENV_VAR: \#{ENV['ENV_VAR']}"
        puts "PLAIN_VAR: \#{ENV['PLAIN_VAR']}"
        exit 0
      RUBY
      
      # Mock the secrets manager to use our test instance
      allow(JobSchedulerComponents::SecretsManager).to receive(:new).and_return(secrets_manager)
      
      job = Job.new('secrets_job', secrets_job_path)
      logger = double('Logger', info: nil, debug: nil, error: nil)
      
      result = job.execute(logger)
      
      expect(result[:success]).to be true
      expect(result[:output]).to include('API_KEY: secret_api_key_123')
      expect(result[:output]).to include('TOKEN: secret_token_456')
      expect(result[:output]).to include('ENV_VAR: integration_env_value')
      expect(result[:output]).to include('PLAIN_VAR: plain_value')
    end

    it 'handles missing secrets gracefully during job execution' do
      missing_secret_job_path = File.join(jobs_dir, 'missing_secret_job')
      FileUtils.mkdir_p(missing_secret_job_path)
      
      config = {
        'schedule' => '0 */6 * * *',
        'environment' => {
          'MISSING_SECRET' => 'secret:NONEXISTENT_SECRET',
          'PLAIN_VAR' => 'plain_value'
        }
      }
      File.write(File.join(missing_secret_job_path, 'config.yml'), config.to_yaml)
      File.write(File.join(missing_secret_job_path, 'execute.rb'), 'puts "test"; exit 0')
      
      # Mock the secrets manager to use our test instance
      allow(JobSchedulerComponents::SecretsManager).to receive(:new).and_return(secrets_manager)
      
      # Capture warnings by monitoring STDERR
      original_stderr = $stderr
      captured_warnings = StringIO.new
      $stderr = captured_warnings
      
      # Job creation will succeed and environment resolution falls back gracefully
      job = Job.new('missing_secret_job', missing_secret_job_path)
      env = job.environment
      
      # Restore stderr
      $stderr = original_stderr
      warning_output = captured_warnings.string
      
      # Should fall back to original config and generate a warning
      expect(env['MISSING_SECRET']).to eq('secret:NONEXISTENT_SECRET')
      expect(env['PLAIN_VAR']).to eq('plain_value')
      expect(warning_output).to match(/Warning: Failed to resolve secrets.*Secret not found/)
    end

    it 'works with JobScheduler end-to-end with secrets' do
      # Create a fresh scheduler for this test
      fresh_scheduler = JobScheduler.new(repo_url: repo_url, jobs_dir: jobs_dir)
      
      # Create a job that uses secrets
      secrets_e2e_job_path = File.join(jobs_dir, 'secrets_e2e_job')
      FileUtils.mkdir_p(secrets_e2e_job_path)
      
      config = {
        'schedule' => '0 */6 * * *',
        'environment' => {
          'SECRET_VALUE' => 'secret:TEST_API_KEY',
          'PLAIN_VALUE' => 'e2e_test'
        }
      }
      File.write(File.join(secrets_e2e_job_path, 'config.yml'), config.to_yaml)
      File.write(File.join(secrets_e2e_job_path, 'execute.rb'), <<~RUBY)
        puts "Secret resolved: \#{ENV['SECRET_VALUE']}"
        puts "Plain value: \#{ENV['PLAIN_VALUE']}"
        exit 0
      RUBY
      
      # Mock the secrets manager globally
      allow(JobSchedulerComponents::SecretsManager).to receive(:new).and_return(secrets_manager)
      
      # Load the job
      fresh_scheduler.send(:reload_jobs)
      
      # Verify job was loaded
      scheduled_jobs = fresh_scheduler.scheduler.jobs
      job_cron = scheduled_jobs.find { |j| j.original != '15m' }
      expect(job_cron).not_to be_nil
      
      # Execute the job manually to test secrets resolution
      job = Job.new('secrets_e2e_job', secrets_e2e_job_path)
      result = job.execute(fresh_scheduler.logger)
      
      expect(result[:success]).to be true
      expect(result[:output]).to include('Secret resolved: secret_api_key_123')
      expect(result[:output]).to include('Plain value: e2e_test')
    end
  end
end