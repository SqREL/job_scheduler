require 'git'
require 'rufus-scheduler'
require 'logger'
require 'yaml'
require 'fileutils'
require 'uri'
require_relative 'job'
require_relative 'job_scheduler/errors'
require_relative 'job_scheduler/job_history'

class JobScheduler
  attr_reader :logger, :scheduler, :jobs_dir, :repo_url

  def initialize(repo_url:, jobs_dir: './jobs', log_level: Logger::INFO)
    @repo_url = validate_repo_url(repo_url)
    validate_jobs_dir_safety!(jobs_dir)
    @jobs_dir = File.expand_path(jobs_dir)
    @logger = create_logger(log_level)
    @scheduler = Rufus::Scheduler.new
    @job_history = JobSchedulerComponents::JobHistory.new
    @active_jobs = {}
    
    setup_jobs_directory
  end

  def start
    logger.info "Starting Job Scheduler"
    
    # Schedule repository sync every 15 minutes
    scheduler.every '15m' do
      sync_repository
      reload_jobs
    end

    # Initial sync and job loading
    sync_repository
    reload_jobs

    logger.info "Job Scheduler started. Press Ctrl+C to stop."
    scheduler.join
  end

  def force_sync
    logger.info "Force syncing repository"
    sync_repository
    reload_jobs
  end

  def health_check
    {
      status: 'healthy',
      active_jobs: @active_jobs.size,
      total_executions: @job_history.total_executions,
      recent_failures: @job_history.recent_failures(10),
      repository_status: repository_health
    }
  end

  def job_stats
    @job_history.stats
  end

  private

  def setup_jobs_directory
    FileUtils.mkdir_p(jobs_dir) unless Dir.exist?(jobs_dir)
  end

  def sync_repository
    logger.info "Syncing repository: #{repo_url}"
    
    begin
      if Dir.exist?(File.join(jobs_dir, '.git'))
        # Pull latest changes
        git = Git.open(jobs_dir)
        git.pull
        logger.info "Repository updated successfully"
      else
        # Clone repository
        FileUtils.rm_rf(jobs_dir) if Dir.exist?(jobs_dir)
        Git.clone(repo_url, jobs_dir)
        logger.info "Repository cloned successfully"
      end
    rescue Git::GitExecuteError => e
      logger.error "Failed to sync repository: #{e.message}"
      raise JobSchedulerErrors::GitError, "Failed to sync repository: #{e.message}"
    rescue => e
      logger.error "Failed to sync repository: #{e.message}"
      raise JobSchedulerErrors::GitError, "Failed to sync repository: #{e.message}"
    end
  end

  def reload_jobs
    logger.info "Reloading jobs from #{jobs_dir}"
    
    # Clear existing scheduled jobs (except the sync job)
    scheduler.jobs.each do |job|
      scheduler.unschedule(job) unless job.original == '15m'
    end

    # Scan for job directories
    Dir.glob(File.join(jobs_dir, '*')).each do |job_path|
      next unless File.directory?(job_path)
      
      job_name = File.basename(job_path)
      load_job(job_name, job_path)
    end
  end

  def load_job(job_name, job_path)
    config_file = File.join(job_path, 'config.yml')
    execute_file = File.join(job_path, 'execute.rb')
    
    unless File.exist?(config_file) && File.exist?(execute_file)
      logger.warn "Skipping job #{job_name}: missing config.yml or execute.rb"
      return
    end

    begin
      # Try to create and validate the job first
      job = Job.new(job_name, job_path)
      unless job.valid?
        logger.warn "Validation failed for job #{job_name}"
        return
      end

      # Schedule the job
      scheduler.cron job.schedule do
        execute_job_with_tracking(job)
      end

      logger.info "Loaded job: #{job_name} with schedule: #{job.schedule}"
    rescue JobSchedulerErrors::JobConfigurationError => e
      logger.error "Configuration error for job #{job_name}: #{e.message}"
    rescue JobSchedulerErrors::SecurityError => e
      logger.error "Security error for job #{job_name}: #{e.message}"
    rescue => e
      logger.error "Failed to load job #{job_name}: #{e.message}"
    end
  end

  def execute_job_with_tracking(job)
    execution_id = "#{job.name}_#{Time.now.to_i}_#{rand(1000)}"
    @active_jobs[execution_id] = { job: job, started_at: Time.now }
    
    begin
      result = job.execute(logger)
      @job_history.add_execution(job.name, true, result[:execution_time], result[:output])
    rescue JobSchedulerErrors::JobTimeoutError => e
      logger.error "Job #{job.name} timed out: #{e.message}"
      @job_history.add_execution(job.name, false, job.timeout, e.message)
    rescue JobSchedulerErrors::JobExecutionError => e
      logger.error "Job #{job.name} execution failed: #{e.message}"
      @job_history.add_execution(job.name, false, 0, e.message)
    rescue => e
      logger.error "Unexpected error executing job #{job.name}: #{e.message}"
      @job_history.add_execution(job.name, false, 0, e.message)
    ensure
      @active_jobs.delete(execution_id)
    end
  end

  private

  def validate_repo_url(url)
    begin
      uri = URI.parse(url)
      unless %w[http https git ssh].include?(uri.scheme) || url.match?(/\A[\w\-\.]+@[\w\-\.]+:/)
        raise JobSchedulerErrors::ValidationError, "Invalid repository URL scheme"
      end
      url
    rescue URI::InvalidURIError
      raise JobSchedulerErrors::ValidationError, "Invalid repository URL format"
    end
  end

  def validate_jobs_dir_safety!(path)
    if path.include?('..') || path.include?('../')
      raise JobSchedulerErrors::SecurityError, "Unsafe jobs directory path"
    end
  end

  def create_logger(log_level)
    logger = Logger.new(STDOUT)
    logger.level = log_level
    logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
    logger
  end

  def repository_health
    return 'not_cloned' unless Dir.exist?(File.join(jobs_dir, '.git'))
    
    begin
      git = Git.open(jobs_dir)
      last_commit = git.log.first
      {
        status: 'healthy',
        last_commit: last_commit.sha[0..7],
        last_commit_date: last_commit.date
      }
    rescue => e
      { status: 'error', message: e.message }
    end
  end
end
