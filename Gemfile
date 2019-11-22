gem_sources   = ENV.fetch('GEM_SERVERS','https://rubygems.org').split(/[, ]+/)
puppet_version = ENV.fetch('PUPPET_VERSION', '~> 5.5')

gem_sources.each { |gem_source| source gem_source }

group :test do
  gem 'rake'
  gem 'puppet', puppet_version
  gem 'rspec'
  gem 'rspec-puppet'
  gem 'puppet-strings'
  gem 'hiera-puppet-helper'
  gem 'puppetlabs_spec_helper'
  gem 'metadata-json-lint'
  gem 'puppet-lint-empty_string-check',   :require => false
  gem 'puppet-lint-trailing_comma-check', :require => false
  gem 'simp-rspec-puppet-facts', ENV.fetch('SIMP_RSPEC_PUPPET_FACTS_VERSION', '~> 2.2')
  gem 'simp-rake-helpers', ENV.fetch('SIMP_RAKE_HELPERS_VERSION', '~> 5.8')
  #gem 'puppet-syntax', ENV.fetch('PUPPET_SYNTAX_VERSION', '~> 2.5.0') # 2.6.0 broke plans

  # This fragile garbage tries to only load bolt when
  # PUPPET_VERSION supports it
  if puppet_version =~ /^(>|~>|>=|=)?\s*(6|7|8)(\.|\s*\Z)/
    gem 'bolt', ENV.fetch('BOLT_VERSION', '~> 1.30')
  end
end

group :development do
  gem 'pry'
  gem 'pry-doc'
end

group :system_tests do
  gem 'beaker'
  gem 'beaker-rspec'
  gem 'simp-beaker-helpers', ENV.fetch('SIMP_BEAKER_HELPERS_VERSION', '~> 1.13')
end
