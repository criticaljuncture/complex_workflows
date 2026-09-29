require "./lib/complex_workflows"
require "./spec/support/sidekiq_config"
require "./spec/support/jobs"
require "./spec/support/workflow_harness"

class ChainableWorkflow
  include ComplexWorkflows

  workflow do
    step(:step_1) do |id|
      step_jobs do
        Job.perform_async "step_1", id
      end
    end

    success do |id|
      if id < 3
        parent_jobs do
          ChainableWorkflow::Starter.perform_async(id + 1)
        end
      end
    end
  end
end

class ParentWorkflow
  include ComplexWorkflows

  workflow do
    step(:run_all) do |id|
      step_jobs do
        ChainableWorkflow::Starter.perform_async(1)
      end
    end

    success do |id|
      Job.perform_async "shutdown"
    end
  end
end

ParentWorkflow.start
