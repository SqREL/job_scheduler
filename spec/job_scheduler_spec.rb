require 'spec_helper'
require_relative '../lib/job_scheduler'

RSpec.describe JobScheduler do
  let(:repo_url) { 'https://github.com/test/repo.git' }
  let(:jobs_dir) { File.join(@temp_dir, 'jobs') }
  let(:job_scheduler) { JobScheduler.new(repo_url: repo_url, jobs_dir: jobs_dir) }

  describe '#initialize' do
    context 'with valid repository URL' do
      it 'creates a job scheduler instance' do
        expect(job_scheduler.repo_url).to eq(repo_url)
        expect(job_scheduler.jobs_dir).to eq(jobs_dir)
        expect(job_scheduler.logger).to be_a(Logger)
        expect(job_scheduler.scheduler).to be_a(Rufus::Scheduler)
      end

      it 'creates jobs directory if it does not exist' do
        non_existent_dir = File.join(@temp_dir, 'new_jobs')
        expect(Dir.exist?(non_existent_dir)).to be false
        
        JobScheduler.new(repo_url: repo_url, jobs_dir: non_existent_dir)
        
        expect(Dir.exist?(non_existent_dir)).to be true
      end
    end

    context 'with invalid repository URL' do
      it 'raises validation error for invalid scheme' do
        expect { JobScheduler.new(repo_url: 'ftp://invalid.com', jobs_dir: jobs_dir) }
          .to raise_error(JobSchedulerErrors::ValidationError, /Invalid repository URL scheme/)
      end

      it 'raises validation error for malformed URL' do
        expect { JobScheduler.new(repo_url: 'not-a-url', jobs_dir: jobs_dir) }
          .to raise_error(JobSchedulerErrors::ValidationError, /Invalid repository URL/)
      end
    end

    context 'with unsafe jobs directory' do
      it 'raises security error for directory traversal' do
        expect { JobScheduler.new(repo_url: repo_url, jobs_dir: '../unsafe') }
          .to raise_error(JobSchedulerErrors::SecurityError, /Unsafe jobs directory path/)
      end
    end
  end

  describe '#sync_repository' do
    let(:git_double) { double('Git') }

    context 'when repository does not exist' do
      it 'clones the repository' do
        expect(Git).to receive(:clone).with(repo_url, jobs_dir)
        
        job_scheduler.send(:sync_repository)
      end

      it 'handles git clone errors' do
        expect(Git).to receive(:clone).and_raise(Git::GitExecuteError.new('Clone failed'))
        
        expect { job_scheduler.send(:sync_repository) }
          .to raise_error(JobSchedulerErrors::GitError, /Failed to sync repository/)
      end
    end

    context 'when repository exists' do
      before do
        FileUtils.mkdir_p(File.join(jobs_dir, '.git'))
      end

      it 'pulls latest changes' do
        expect(Git).to receive(:open).with(jobs_dir).and_return(git_double)
        expect(git_double).to receive(:pull)
        
        job_scheduler.send(:sync_repository)
      end

      it 'handles git pull errors' do
        expect(Git).to receive(:open).with(jobs_dir).and_return(git_double)
        expect(git_double).to receive(:pull).and_raise(Git::GitExecuteError.new('Pull failed'))
        
        expect { job_scheduler.send(:sync_repository) }
          .to raise_error(JobSchedulerErrors::GitError, /Failed to sync repository/)
      end
    end
  end

  describe '#load_job' do
    let(:job_name) { 'test_job' }
    let(:job_path) { File.join(jobs_dir, job_name) }

    before do
      FileUtils.mkdir_p(job_path)
    end

    context 'with valid job' do
      before do
        File.write(File.join(job_path, 'config.yml'), {
          'schedule' => '0 */6 * * *',
          'description' => 'Test job'
        }.to_yaml)
        File.write(File.join(job_path, 'execute.rb'), 'puts "test"')
      end

      it 'loads and schedules the job' do
        expect(job_scheduler.scheduler).to receive(:cron).with('0 */6 * * *')
        
        job_scheduler.send(:load_job, job_name, job_path)
      end
    end

    context 'with invalid job' do
      it 'logs warning for missing files' do
        expect(job_scheduler.logger).to receive(:warn).with(/Skipping job test_job: missing config.yml or execute.rb/)
        
        job_scheduler.send(:load_job, job_name, job_path)
      end

      it 'handles configuration errors gracefully' do
        File.write(File.join(job_path, 'config.yml'), 'invalid: yaml:')
        File.write(File.join(job_path, 'execute.rb'), 'puts "test"')
        
        expect(job_scheduler.logger).to receive(:error).with(/Configuration error for job test_job:/)
        
        job_scheduler.send(:load_job, job_name, job_path)
      end

      it 'handles security errors gracefully' do
        File.write(File.join(job_path, 'config.yml'), {
          'schedule' => '0 */6 * * *'
        }.to_yaml)
        File.write(File.join(job_path, 'execute.rb'), 'system("rm -rf /")')
        
        expect(job_scheduler.logger).to receive(:error).with(/Security error for job test_job:/)
        
        job_scheduler.send(:load_job, job_name, job_path)
      end
    end
  end

  describe '#execute_job_with_tracking' do
    let(:job_double) { double('Job') }
    let(:job_name) { 'test_job' }

    before do
      allow(job_double).to receive(:name).and_return(job_name)
    end

    context 'with successful execution' do
      it 'tracks successful job execution' do
        result = { success: true, execution_time: 1.5, output: 'Success' }
        expect(job_double).to receive(:execute).with(job_scheduler.logger).and_return(result)
        expect(job_scheduler.instance_variable_get(:@job_history))
          .to receive(:add_execution).with(job_name, true, 1.5, 'Success')
        
        job_scheduler.send(:execute_job_with_tracking, job_double)
      end
    end

    context 'with timeout error' do
      it 'tracks timeout and logs error' do
        allow(job_double).to receive(:timeout).and_return(120)
        expect(job_double).to receive(:execute)
          .and_raise(JobSchedulerErrors::JobTimeoutError.new('Timeout'))
        expect(job_scheduler.instance_variable_get(:@job_history))
          .to receive(:add_execution).with(job_name, false, 120, 'Timeout')
        
        job_scheduler.send(:execute_job_with_tracking, job_double)
      end
    end

    context 'with execution error' do
      it 'tracks failure and logs error' do
        expect(job_double).to receive(:execute)
          .and_raise(JobSchedulerErrors::JobExecutionError.new('Failed'))
        expect(job_scheduler.instance_variable_get(:@job_history))
          .to receive(:add_execution).with(job_name, false, 0, 'Failed')
        
        job_scheduler.send(:execute_job_with_tracking, job_double)
      end
    end
  end

  describe '#health_check' do
    let(:job_history) { job_scheduler.instance_variable_get(:@job_history) }

    it 'returns health status information' do
      allow(job_history).to receive(:total_executions).and_return(10)
      allow(job_history).to receive(:recent_failures).and_return([])
      
      health = job_scheduler.health_check
      
      expect(health).to include(
        status: 'healthy',
        active_jobs: 0,
        total_executions: 10,
        recent_failures: [],
        repository_status: anything
      )
    end
  end

  describe '#job_stats' do
    it 'returns job statistics' do
      job_history = job_scheduler.instance_variable_get(:@job_history)
      expected_stats = { total: 5, successful: 4, failed: 1 }
      
      expect(job_history).to receive(:stats).and_return(expected_stats)
      
      expect(job_scheduler.job_stats).to eq(expected_stats)
    end
  end

  describe '#force_sync' do
    it 'performs sync and reload operations' do
      expect(job_scheduler).to receive(:sync_repository)
      expect(job_scheduler).to receive(:reload_jobs)
      
      job_scheduler.force_sync
    end
  end
end