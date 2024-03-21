# frozen_string_literal: true

require 'bundler/setup'
require 'base64'
require 'test_config'
require 'temping'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    config = TestConfig.current_config
    puts "Testing adapter #{TestConfig.current_adapter} " \
         "(#{RUBY_DESCRIPTION}, ActiveRecord #{ActiveRecord::VERSION::STRING}, " \
         "gemfile #{ENV.fetch('BUNDLE_GEMFILE', nil)})"
    case config['adapter']
    when 'mysql2'
      ActiveRecord::Base.establish_connection(config.except('database'))
      ActiveRecord::Base.connection.execute("CREATE DATABASE #{config['database']} " \
                                            'DEFAULT CHARACTER SET utf8 ' \
                                            'DEFAULT COLLATE utf8_unicode_ci')
    when 'postgresql'
      ActiveRecord::Base.establish_connection(config.except('database'))
      ActiveRecord::Base.connection.execute("CREATE DATABASE #{config['database']} " \
                                            "ENCODING = 'UTF8'" \
                                            "TEMPLATE 'template0'")
    end
    ActiveRecord::Base.establish_connection(config)
  end

  config.after(:suite) do
    Temping.teardown
    config = TestConfig.current_config
    case config['adapter']
    when 'mysql2'
      ActiveRecord::Base.connection.execute("DROP DATABASE IF EXISTS #{config['database']}")
    when 'postgresql'
      ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(config.except('database').merge(database: 'template1'))
      ActiveRecord::Base.connection.execute("DROP DATABASE IF EXISTS #{config['database']}")
    end
    ActiveRecord::Base.remove_connection
  end
end
