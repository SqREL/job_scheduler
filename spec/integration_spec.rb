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
end