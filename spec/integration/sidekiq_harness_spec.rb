RSpec.describe SidekiqHarness do
  it "reports startup errors including stderr" do
    expect { described_class.new.perform('raise "harness startup failure"') }
      .to raise_error(RuntimeError, /harness startup failure/)
  end

  it "reports job failures even when Sidekiq exits successfully" do
    code = <<~RUBY
      class FailingJob
        include Sidekiq::Job
        sidekiq_options retry: false

        def perform
          raise "harness job failure"
        ensure
          Job.perform_async("shutdown")
        end
      end

      FailingJob.perform_async
    RUBY

    expect { described_class.new.perform(code) }
      .to raise_error(RuntimeError, /harness job failure/)
  end

  it "terminates a child that never shuts down" do
    expect { described_class.new.perform("sleep 60", timeout: 1) }
      .to raise_error(RuntimeError, /timed out after 1s/)
  end

  it "rejects a disabled timeout" do
    expect { described_class.new.perform("", timeout: 0) }
      .to raise_error(ArgumentError, /timeout must be positive/)
  end
end
