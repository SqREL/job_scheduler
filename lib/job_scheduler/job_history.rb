require 'json'
require 'fileutils'

module JobSchedulerComponents
  class JobHistory
    attr_reader :executions

    def initialize(history_file: './job_history.json')
      @history_file = history_file
      @executions = load_history
    end

    def add_execution(job_name, success, execution_time, output)
      execution = {
        job_name: job_name,
        timestamp: Time.now.iso8601,
        success: success,
        execution_time: execution_time,
        output: truncate_output(output.to_s)
      }
      
      @executions << execution
      
      # Keep only last 1000 executions
      @executions = @executions.last(1000) if @executions.size > 1000
      
      save_history
      execution
    end

    def total_executions
      @executions.size
    end

    def recent_failures(limit = 10)
      @executions
        .select { |e| !e[:success] }
        .last(limit)
        .map { |e| { job_name: e[:job_name], timestamp: e[:timestamp], output: e[:output] } }
    end

    def stats
      total = @executions.size
      return { total: 0, success_rate: 0 } if total == 0

      successful = @executions.count { |e| e[:success] }
      success_rate = (successful.to_f / total * 100).round(2)

      {
        total: total,
        successful: successful,
        failed: total - successful,
        success_rate: success_rate,
        avg_execution_time: average_execution_time
      }
    end

    def job_stats(job_name)
      job_executions = @executions.select { |e| e[:job_name] == job_name }
      total = job_executions.size
      return { total: 0, success_rate: 0 } if total == 0

      successful = job_executions.count { |e| e[:success] }
      success_rate = (successful.to_f / total * 100).round(2)

      {
        job_name: job_name,
        total: total,
        successful: successful,
        failed: total - successful,
        success_rate: success_rate,
        last_execution: job_executions.last&.dig(:timestamp),
        avg_execution_time: average_execution_time(job_executions)
      }
    end

    private

    def load_history
      return [] unless File.exist?(@history_file)
      
      content = File.read(@history_file)
      JSON.parse(content, symbolize_names: true)
    rescue JSON::ParserError, Errno::ENOENT
      []
    end

    def save_history
      FileUtils.mkdir_p(File.dirname(@history_file))
      File.write(@history_file, JSON.pretty_generate(@executions))
    rescue => e
      # Silently fail to avoid disrupting job execution
      warn "Failed to save job history: #{e.message}"
    end

    def truncate_output(output)
      output.length > 1000 ? "#{output[0...997]}..." : output
    end

    def average_execution_time(executions = @executions)
      successful_executions = executions.select { |e| e[:success] && e[:execution_time] }
      return 0 if successful_executions.empty?

      total_time = successful_executions.sum { |e| e[:execution_time] }
      (total_time / successful_executions.size).round(2)
    end
  end
end