module SidekiqWorkflow
  extend ActiveSupport::Concern

  included do
    include Sidekiq::Worker
  end

  class_methods do
    def workflow(&blk)
      Workflow.new(&blk).register(self)
    end
  end

  def step_jobs
    @workflow_batch.jobs do
      step_batch = Sidekiq::Batch.new
      step_batch.description = @description
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