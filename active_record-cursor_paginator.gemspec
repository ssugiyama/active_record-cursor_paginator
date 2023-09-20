# frozen_string_literal: true

require_relative 'lib/active_record/cursor_paginator/version'

Gem::Specification.new do |spec|
  spec.name = 'active_record-cursor_paginator'
  spec.version = ActiveRecord::CursorPaginator::VERSION
  spec.authors = ['Shinichi Sugiyama']
  spec.email = ['sugiyama-shinichi@kayac.com']

  spec.summary = 'cursor pagination for ActiveRecord'
  spec.description =
    'This library is an implementation of cursor pagination for ActiveRecord relations ' \
    'based on "https://github.com/xing/rails_cursor_pagination". ' \
    'Additional features are: ' \
    '- receives a relation with orders, and it is unnecessary to specify orders to this library separately.' \
    '- supports bidirectional pagination.'

  spec.homepage = 'https://github.com/ssugiyama/active_record-cursor_paginator'
  spec.license = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.7.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/Changelog.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) {|f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency 'activerecord', '>= 6.0'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata['rubygems_mfa_required'] = 'true'
end
