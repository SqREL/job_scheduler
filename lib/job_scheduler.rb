require 'git'
require 'rufus-scheduler'
require 'logger'
require 'yaml'
require 'fileutils'

class JobScheduler
  attr_reader :logger, :scheduler, :jobs_dir, :repo_url

  def initialize(repo_url:, jobs_dir: './jobs', log_level: Logger::INFO)
    @repo_url = repo_url
    @jobs_dir = File.expand_path(jobs_dir)
    @logger = Logger.new(STDOUT)
    @logger.level = log_level
    @scheduler = Rufus::Scheduler.new
    
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
    rescue => e
      logger.error "Failed to sync repository: #{e.message}"
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
      config = YAML.load_file(config_file)
      schedule = config['schedule']
      
      unless schedule
        logger.warn "Skipping job #{job_name}: no schedule defined"
        return
      end

      # Schedule the job
      scheduler.cron schedule do
        execute_job(job_name, job_path, execute_file)
      end

      logger.info "Loaded job: #{job_name} with schedule: #{schedule}"
    rescue => e
      logger.error "Failed to load job #{job_name}: #{e.message}"
    end
  end

  def execute_job(job_name, job_path, execute_file)
    logger.info "Executing job: #{job_name}"
    start_time = Time.now
    
    begin
      # Change to job directory and execute
      Dir.chdir(job_path) do
        output = `ruby #{File.basename(execute_file)} 2>&1`
        exit_status = $?.exitstatus
        
        if exit_status == 0
          logger.info "Job #{job_name} completed successfully in #{Time.now - start_time}s"
          logger.debug "Output: #{output}" unless output.empty?
        else
          logger.error "Job #{job_name} failed with exit code #{exit_status}"
          logger.error "Error output: #{output}"
        end
      end
    rescue => e
      logger.error "Failed to execute job #{job_name}: #{e.message}"
    end
  end
end
