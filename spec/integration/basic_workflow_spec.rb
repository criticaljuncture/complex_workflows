RSpec.describe ComplexWorkflows do
  it "our sidekiq harness works" do
    performed_jobs = SidekiqHarness.new.perform(<<-RUBY)
      Job.perform_async("1")
      Job.perform_async("2")
      Job.perform_async("shutdown")
    RUBY
    expect(performed_jobs.map(&:args)).to contain_exactly(%w(1), %w(2), %w(shutdown))
  end

  it "performs the steps in order, passings args" do
    performed_jobs = SidekiqHarness.new.perform(<<-RUBY)
      workflow = create_workflow do
        step(:step_1) do |*args|
          step_jobs do
            Job.perform_async(1, args)
          end
        end

        step(:step_2) do |*args|
          step_jobs do
            Job.perform_async(2, args)
          end
        end

        success do
          Job.perform_async "shutdown"
        end
      end
      workflow.start("a", "b")
    RUBY

    expect(performed_jobs.map(&:args)).to eql [
      %w(a b),
      [1, %w(a b)],
      [2, %w(a b)],
      ["shutdown"]
    ]
  end

  it "performs the steps in order, but workflow jobs can go anywhere later" do
    performed_jobs = SidekiqHarness.new.perform(<<-RUBY, timeout: 0)
      workflow = create_workflow do
        step(:step_1) do
          step_jobs do
            Job.perform_async "step_1"
          end
        end

        step(:step_2) do
          step_jobs do
            Job.perform_async "step_2"
          end

          workflow_jobs do
            Job.perform_in 2, "step_2_workflow"
          end
        end

        step(:step_3) do
          step_jobs do
            Job.perform_async "step_3"
          end
        end

        success do
          Job.perform_async "shutdown"
        end
      end
      workflow.start
    RUBY

    expect(performed_jobs.map(&:args)).to eql [
      %w(), # whole workflow
      %w(step_1),
      %w(step_2),
      %w(step_3),
      %w(step_2_workflow),
      %w(shutdown),
    ]
  end

  it "can chain batches" do
    performed_jobs = SidekiqHarness.new.perform(<<-RUBY)
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
                ChainableWorkflow::Starter.perform_async(id+1)
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
    RUBY

    expect(performed_jobs.map{|j| [j.job_class, j.args]}).to eql [
      ["ParentWorkflow", []],
      ["ChainableWorkflow::Starter", [1]],
      ["ChainableWorkflow", [1]], # perform method, step 1
      ["Job", ["step_1", 1]],     # actions of step 1
      ["ChainableWorkflow::Starter", [2]],
      ["ChainableWorkflow", [2]], # perform method, step 1
      ["Job", ["step_1", 2]],     # actions of step 1
      ["ChainableWorkflow::Starter", [3]],
      ["ChainableWorkflow", [3]], # perform method, step 1
      ["Job", ["step_1", 3]],     # actions of step 1
      ["Job", ["shutdown"]],      # final success
    ]
  end
end