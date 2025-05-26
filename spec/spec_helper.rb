require 'rspec'
require 'timecop'
require 'fileutils'
require 'tmpdir'
require 'stringio'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!

  config.before(:each) do
    @original_dir = Dir.pwd
    @temp_dir = Dir.mktmpdir('job_scheduler_test')
  end

  config.after(:each) do
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end
end