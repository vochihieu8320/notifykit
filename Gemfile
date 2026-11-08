# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  # Host-app frameworks, used only by spec/dummy (not runtime deps of the gem).
  gem "activejob", "~> 7.2.0"
  gem "activerecord", "~> 7.2.0"
  gem "pg", "~> 1.5"
  gem "railties", "~> 7.2.0"

  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.66", require: false
  gem "rubocop-rspec", "~> 3.0", require: false
  gem "webrick", "~> 1.8" # mock provider HTTP servers in specs
end
