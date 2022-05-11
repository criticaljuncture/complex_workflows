# frozen_string_literal: true

RSpec.describe SidekiqWorkflows do
  it "has a version number" do
    expect(SidekiqWorkflows::VERSION).not_to be nil
  end

  it "our sidekiq harness works" do
    performed_jobs = SidekiqHarness.new.perform(<<-RUBY)
      Job.perform_async("1")
      Job.perform_async("2")
      Job.perform_async("shutdown")
    RUBY

    expect(performed_jobs.map(&:args)).to contain_exactly(%w(1), %w(2), %w(shutdown))
  end

  it "performs the steps in order" do
    performed_jobs = SidekiqHarness.new.perform(<<-RUBY, timeout: 0)
      workflow("a", "b") do
        step(:step_1) do |*args|
          step_jobs do
            # raise @workflow_batch.inspect
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
    RUBY

    expect(performed_jobs.map(&:args)).to eql [
      %w(a b),
      [1, %w(a b)],
      [2, %w(a b)],
      ["shutdown"]
    ]
  end
end
