require 'yaml'

module TestConfig
  class << self
    def current_config
      config[current_adapter] || raise("adapter '#{name}' is not configured")
    end

    def adapters
      @adapters ||=
        config.keys.reject {|key| skipped_adapters.any? {|adapter| key.to_s.include?(adapter) } }
    end

    # #current_adapter and #current_adapter= use an environment variable because
    # the value must be passed to a child process. When a test suite is run by executing +rake+
    # a Ruby process is started. +RSpec::Core::RakeTask+ runs +spec+ in a Ruby child process.
    # The adapter is chosen by the parent process but tested by the child process. Using an
    # environment variable is the simplest way of passing a value from the parent to the child.
    def current_adapter
      ENV.fetch('ADAPTER')
    end

    def current_adapter=(adapter)
      ENV['ADAPTER'] = adapter
    end

    def skipped_adapters
      @skipped_adapters ||= ENV['SKIPPED_ADAPTERS'].to_s.downcase.split(/[,:;]/)
    end
    private :skipped_adapters

    def config
      @config ||= YAML.safe_load(File.read(config_path))
    end
    private :config

    def config_path
      File.join(File.dirname(__FILE__), 'config.default.yml')
    end
    private :config_path
  end
end
