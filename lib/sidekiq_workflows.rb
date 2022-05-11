# frozen_string_literal: true

require 'active_support/concern'
require "active_support/core_ext/object/blank"

require "sidekiq-pro"

require_relative "sidekiq_workflows/version"
require_relative "sidekiq_workflows/step"
require_relative "sidekiq_workflows/workflow"

module SidekiqWorkflows
  extend ActiveSupport::Concern

  @@descendants = []
  def self.descendants
    Dir["#{Rails.root}/app/**/*.rb"].each { |file| require_dependency file } if Rails.env.development?
    @@descendants
  end

  def self.titles_with_negative_pending
    descendants.map(&:titles_with_negative_pending).flatten.uniq
  end

  def self.titles_in_process
    descendants.map(&:titles_in_process).flatten.uniq
  end

  included do
    include Sidekiq::Worker
    @@descendants << self
  end

  class_methods do
    def workflow(&blk)
      SidekiqWorkflows::Workflow.new(&blk).register(self)
    end
  end

  def step_jobs
    @workflow_batch.jobs do
      step_batch = Sidekiq::Batch.new
      step_batch.description = @description
      step_batch.callback_queue = :critical
      step_batch.on(:success, "#{self.class}##{@next_step.identifier}", @args) if @next_step.present?

      step_batch.jobs do
        yield
      end
    end
  end

  def workflow_jobs
    @workflow_batch.jobs { yield }
  end

  def parent_jobs
    @parent_batch.jobs { yield }
  end
end
