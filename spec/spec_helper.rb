require File.expand_path('on_what', File.dirname(File.dirname(__FILE__)))

require 'helpers/zone'
require 'helpers/zonelist'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    # Protect against speling errors in mocks.
    mocks.verify_doubled_constant_names = true
  end

  config.include Zone
  config.include ZoneList
end

unless on_1_8?
  begin
    require 'simplecov'

    SimpleCov.configure do
      add_filter '/spec/'
      add_filter '/vendor/'
      minimum_coverage 100
      refuse_coverage_drop
    end

    if on_travis?
      require 'codecov'
      SimpleCov.formatter = SimpleCov::Formatter::Codecov
    end

    SimpleCov.start
  rescue LoadError
    puts "Coverage is disabled - install simplecov to enable."
  end
end

require 'devops'
