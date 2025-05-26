module JobSchedulerErrors
  class Error < StandardError; end
  
  class GitError < Error; end
  class JobConfigurationError < Error; end
  class JobExecutionError < Error; end
  class JobTimeoutError < Error; end
  class SecurityError < Error; end
  class ValidationError < Error; end
end