class Job
  attr_reader :name, :path, :config

  def initialize(name, path)
    @name = name
    @path = path
    @config = load_config
  end

  def valid?
    File.exist?(config_file) && File.exist?(execute_file) && config['schedule']
  end

  def schedule
    config['schedule']
  end

  def description
    config['description'] || 'No description provided'
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
    YAML.load_file(config_file)
  rescue
    {}
  end
end
