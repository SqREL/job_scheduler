require 'spec_helper'
require_relative '../../lib/job_scheduler/job_history'

RSpec.describe JobSchedulerComponents::JobHistory do
  let(:history_file) { File.join(@temp_dir, 'test_history.json') }
  let(:job_history) { JobSchedulerComponents::JobHistory.new(history_file: history_file) }

  describe '#initialize' do
    context 'with no existing history file' do
      it 'starts with empty executions' do
        expect(job_history.executions).to be_empty
      end
    end

    context 'with existing history file' do
      let(:existing_data) do
        [
          {
            job_name: 'test_job',
            timestamp: '2023-01-01T00:00:00Z',
            success: true,
            execution_time: 1.5,
            output: 'Success'
          }
        ]
      end

      before do
        File.write(history_file, JSON.generate(existing_data))
      end

      it 'loads existing executions' do
        expect(job_history.executions.size).to eq(1)
        expect(job_history.executions.first[:job_name]).to eq('test_job')
      end
    end

    context 'with corrupted history file' do
      before do
        File.write(history_file, 'invalid json')
      end

      it 'starts with empty executions' do
        expect(job_history.executions).to be_empty
      end
    end
  end

  describe '#add_execution' do
    let(:job_name) { 'test_job' }
    let(:success) { true }
    let(:execution_time) { 2.5 }
    let(:output) { 'Job completed successfully' }

    it 'adds execution to history' do
      Timecop.freeze(Time.parse('2023-01-01 12:00:00 UTC')) do
        execution = job_history.add_execution(job_name, success, execution_time, output)
        
        expect(execution[:job_name]).to eq(job_name)
        expect(execution[:success]).to eq(success)
        expect(execution[:execution_time]).to eq(execution_time)
        expect(execution[:output]).to eq(output)
        expect(execution[:timestamp]).to eq('2023-01-01T12:00:00Z')
      end
    end

    it 'truncates long output' do
      long_output = 'x' * 1500
      execution = job_history.add_execution(job_name, success, execution_time, long_output)
      
      expect(execution[:output]).to end_with('...')
      expect(execution[:output].length).to eq(1000)
    end

    it 'saves history to file' do
      job_history.add_execution(job_name, success, execution_time, output)
      
      expect(File.exist?(history_file)).to be true
      
      saved_data = JSON.parse(File.read(history_file), symbolize_names: true)
      expect(saved_data.size).to eq(1)
      expect(saved_data.first[:job_name]).to eq(job_name)
    end

    context 'when history exceeds limit' do
      before do
        # Add 1001 executions to test pruning
        1001.times do |i|
          job_history.add_execution("job_#{i}", true, 1.0, "output #{i}")
        end
      end

      it 'keeps only last 1000 executions' do
        expect(job_history.executions.size).to eq(1000)
        expect(job_history.executions.first[:job_name]).to eq('job_1')
        expect(job_history.executions.last[:job_name]).to eq('job_1000')
      end
    end
  end

  describe '#total_executions' do
    it 'returns total number of executions' do
      3.times { |i| job_history.add_execution("job_#{i}", true, 1.0, 'output') }
      
      expect(job_history.total_executions).to eq(3)
    end
  end

  describe '#recent_failures' do
    before do
      job_history.add_execution('job_1', true, 1.0, 'success')
      job_history.add_execution('job_2', false, 0, 'failed')
      job_history.add_execution('job_3', false, 0, 'timeout')
      job_history.add_execution('job_4', true, 1.5, 'success')
    end

    it 'returns recent failed executions' do
      failures = job_history.recent_failures(5)
      
      expect(failures.size).to eq(2)
      expect(failures.map { |f| f[:job_name] }).to eq(['job_2', 'job_3'])
      expect(failures.first).to include(:job_name, :timestamp, :output)
      expect(failures.first).not_to include(:success, :execution_time)
    end

    it 'limits results to specified count' do
      failures = job_history.recent_failures(1)
      
      expect(failures.size).to eq(1)
      expect(failures.first[:job_name]).to eq('job_3')
    end
  end

  describe '#stats' do
    context 'with no executions' do
      it 'returns zero stats' do
        stats = job_history.stats
        
        expect(stats).to eq({
          total: 0,
          success_rate: 0
        })
      end
    end

    context 'with mixed executions' do
      before do
        job_history.add_execution('job_1', true, 1.0, 'success')
        job_history.add_execution('job_2', false, 0, 'failed')
        job_history.add_execution('job_3', true, 2.0, 'success')
        job_history.add_execution('job_4', true, 1.5, 'success')
      end

      it 'returns comprehensive statistics' do
        stats = job_history.stats
        
        expect(stats[:total]).to eq(4)
        expect(stats[:successful]).to eq(3)
        expect(stats[:failed]).to eq(1)
        expect(stats[:success_rate]).to eq(75.0)
        expect(stats[:avg_execution_time]).to eq(1.5)
      end
    end
  end

  describe '#job_stats' do
    let(:job_name) { 'specific_job' }

    before do
      job_history.add_execution(job_name, true, 1.0, 'success')
      job_history.add_execution('other_job', false, 0, 'failed')
      job_history.add_execution(job_name, false, 0, 'failed')
      job_history.add_execution(job_name, true, 2.0, 'success')
    end

    it 'returns statistics for specific job' do
      stats = job_history.job_stats(job_name)
      
      expect(stats[:job_name]).to eq(job_name)
      expect(stats[:total]).to eq(3)
      expect(stats[:successful]).to eq(2)
      expect(stats[:failed]).to eq(1)
      expect(stats[:success_rate]).to eq(66.67)
      expect(stats[:avg_execution_time]).to eq(1.5)
      expect(stats[:last_execution]).not_to be_nil
    end

    context 'for non-existent job' do
      it 'returns zero stats' do
        stats = job_history.job_stats('non_existent_job')
        
        expect(stats[:total]).to eq(0)
        expect(stats[:success_rate]).to eq(0)
      end
    end
  end
end