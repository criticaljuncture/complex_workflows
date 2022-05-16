# frozen_string_literal: true

require 'active_support/concern'
require "active_support/core_ext/object/blank"

require "sidekiq-pro"

require_relative "complex_workflows/version"
require_relative "complex_workflows/step"
require_relative "complex_workflows/workflow"

module ComplexWorkflows
  class Error < StandardError; end
  class NoJobsEnqueued < Error; end

  extend ActiveSupport::Concern

  included do
    include Sidekiq::Worker
  end

  class_methods do
    def workflow(&blk)
      ComplexWorkflows::Workflow.new(&blk).register(self)
    end
  end

  def step_jobs
    @workflow_batch.jobs do
      @step_batch = Sidekiq::Batch.new
      @step_batch.description = @description
      @step_batch.callback_queue = self.class.sidekiq_options["queue"]
      @step_batch.on(:success, "#{self.class}##{@next_step.identifier}", @args) if @next_step.present?

      jobs_enqueued = @step_batch.jobs do
        yield
      end

      raise NoJobsEnqueued unless jobs_enqueued.present?
    end
  end

  def workflow_jobs
    @workflow_batch.jobs { yield }
  end

  def parent_jobs
    @parent_batch.jobs { yield }
  end
end
