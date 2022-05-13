# frozen_string_literal: true

require "sidekiq_workflows"
require "sidekiq"
require 'pry'

require_relative "support/sidekiq_harness"
require_relative "support/workflow_harness"
require_relative "support/jobs"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
