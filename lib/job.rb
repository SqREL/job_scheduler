require 'yaml'
require 'timeout'
require 'shellwords'
require_relative 'job_scheduler/errors'

class Job
  attr_reader :name, :path, :config

  def initialize(name, path)
    @name = validate_job_name(name)
    @path = validate_path(path)
    @config = load_config
    validate_config! if File.exist?(config_file)
    validate_execution_safety! if File.exist?(execute_file)
  end

  def valid?
    begin
      File.exist?(config_file) && File.exist?(execute_file) && !config['schedule'].nil?
    rescue => e
      false
    end
  end

  def schedule
    config['schedule']
  end

  def description
    config['description'] || 'No description provided'
  end

  def timeout
    config['timeout'] || 300
  end

  def environment
    config['environment'] || {}
  end

  def execute(logger)
    start_time = Time.now
    logger.info "Executing job: #{name}"
    
    begin
      validate_execution_safety!
      
      output = nil
      exit_status = nil
      
      Dir.chdir(path) do
        Timeout::timeout(timeout) do
          env_vars = sanitized_environment
          output = `#{env_vars.map { |k, v| "#{k}=#{Shellwords.escape(v)}" }.join(' ')} ruby #{File.basename(execute_file)} 2>&1`
          exit_status = $?.exitstatus
        end
      end
      
      execution_time = Time.now - start_time
      
      if exit_status == 0
        logger.info "Job #{name} completed successfully in #{execution_time}s"
        logger.debug "Output: #{output}" unless output.to_s.empty?
        { success: true, output: output, execution_time: execution_time }
      else
        logger.error "Job #{name} failed with exit code #{exit_status}"
        logger.error "Error output: #{output}"
        raise JobSchedulerErrors::JobExecutionError, "Job failed with exit code #{exit_status}: #{output}"
      end
    rescue Timeout::Error
      logger.error "Job #{name} timed out after #{timeout} seconds"
      raise JobSchedulerErrors::JobTimeoutError, "Job timed out after #{timeout} seconds"
    rescue JobSchedulerErrors::SecurityError => e
      logger.error "Security error in job #{name}: #{e.message}"
      raise e
    rescue => e
      logger.error "Failed to execute job #{name}: #{e.message}"
      raise JobSchedulerErrors::JobExecutionError, "Execution failed: #{e.message}"
    end
  end

  private

  def config_file
    File.join(path, 'config.yml')
  end

  def execute_file
    File.join(path, 'execute.rb')
  end

  def load_config
    return {} unless File.exist?(config_file)
    
    content = File.read(config_file)
    validate_yaml_safety!(content)
    
    YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
  rescue Psych::SyntaxError => e
    raise JobSchedulerErrors::JobConfigurationError, "Invalid YAML in config: #{e.message}"
  rescue JobSchedulerErrors::SecurityError => e
    raise e
  rescue => e
    raise JobSchedulerErrors::JobConfigurationError, "Failed to load config: #{e.message}"
  end

  def validate_job_name(name)
    unless name.is_a?(String) && name.match?(/\A[a-zA-Z0-9_-]+\z/)
      raise JobSchedulerErrors::ValidationError, "Job name must contain only alphanumeric characters, hyphens, and underscores"
    end
    name
  end

  def validate_path(path)
    expanded_path = File.expand_path(path)
    unless File.directory?(expanded_path)
      raise JobSchedulerErrors::ValidationError, "Job path must be a valid directory: #{expanded_path}"
    end
    expanded_path
  end

  def validate_config!
    unless config.is_a?(Hash)
      raise JobSchedulerErrors::JobConfigurationError, "Config must be a hash"
    end
    
    unless config['schedule']
      raise JobSchedulerErrors::JobConfigurationError, "Job must have a schedule defined"
    end
    
    validate_schedule!(config['schedule'])
    validate_timeout!(config['timeout']) if config['timeout']
    validate_environment!(config['environment']) if config['environment']
  end

  def validate_schedule!(schedule)
    unless schedule.is_a?(String) && schedule.match?(/\A[0-9\s\*\/\-\,]+\z/)
      raise JobSchedulerErrors::JobConfigurationError, "Invalid cron schedule format: #{schedule}"
    end
  end

  def validate_timeout!(timeout)
    unless timeout.is_a?(Integer) && timeout > 0 && timeout <= 3600
      raise JobSchedulerErrors::JobConfigurationError, "Timeout must be a positive integer between 1 and 3600 seconds"
    end
  end

  def validate_environment!(env)
    unless env.is_a?(Hash)
      raise JobSchedulerErrors::JobConfigurationError, "Environment must be a hash"
    end
    
    env.each do |key, value|
      unless key.is_a?(String) && key.match?(/\A[A-Z_][A-Z0-9_]*\z/)
        raise JobSchedulerErrors::ValidationError, "Invalid environment variable name: #{key}"
      end
      
      unless value.is_a?(String)
        raise JobSchedulerErrors::ValidationError, "Environment variable values must be strings"
      end
    end
  end

  def validate_yaml_safety!(content)
    # Check for dangerous YAML constructs but allow basic references
    if content.match?(/!![^Y\s]/) || content.include?('!!ruby/') || content.include?('!!python/')
      raise JobSchedulerErrors::SecurityError, "YAML content contains potentially unsafe constructs"
    end
  end

  def validate_execution_safety!
    unless File.exist?(execute_file)
      raise JobSchedulerErrors::JobExecutionError, "Execute file not found: #{execute_file}"
    end
    
    unless File.readable?(execute_file)
      raise JobSchedulerErrors::SecurityError, "Execute file is not readable: #{execute_file}"
    end
    
    content = File.read(execute_file, 1024)
    if content.include?('`') || content.include?('system(') || content.include?('exec(')
      raise JobSchedulerErrors::SecurityError, "Execute file contains potentially unsafe system calls"
    end
  end

  def sanitized_environment
    safe_env = environment.dup
    safe_env.delete_if { |k, _| k.start_with?('RUBY_') || k.start_with?('GEM_') }
    safe_env
  end
end
