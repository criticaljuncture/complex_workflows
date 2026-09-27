# frozen_string_literal: true

require "active_support/concern"
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
    include Sidekiq::Job
  end

  class_methods do
    def workflow(&blk)
      ComplexWorkflows::Workflow.new(&blk).register(self)
    end

    def start(*args)
      new.start(*args)
    end
  end

  def step_jobs
    @workflow_batch.jobs do
      @step_batch = Sidekiq::Batch.new
      @step_batch.description = @description
      @step_batch.callback_queue = self.class.sidekiq_options["queue"]
      @step_batch.on(:success, "#{self.class}##{@next_step.identifier}", batch_callback_options(@args)) if @next_step.present?

      jobs_enqueued = true
      @step_batch.jobs do
        yield

        unless work_enqueued?(@step_batch)
          @step_batch.invalidate_all # invalidate Sidekiq's empty batch placeholder job
          jobs_enqueued = false
        end
      end

      raise NoJobsEnqueued unless jobs_enqueued
    end
  end

  def workflow_jobs
    @workflow_batch.jobs { yield }
  end

  def parent_jobs
    @parent_batch.jobs { yield }
  end

  private

  def batch_callback_options(args)
    {"args" => args}
  end

  def callback_args(options)
    options.is_a?(Array) ? options : options["args"]
  end

  def work_enqueued?(batch)
    unless batch.instance_variable_defined?(:@added) && batch.instance_variable_defined?(:@pushed)
      raise Error, "unsupported sidekiq-pro version: cannot inspect jobs pushed to batch"
    end

    batch.instance_variable_get(:@added).present? ||
      batch.instance_variable_get(:@pushed).present? ||
      batch.status.child_count.positive?
  end
end
