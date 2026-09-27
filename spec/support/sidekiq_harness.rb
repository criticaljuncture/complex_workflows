require "open3"
require "timeout"
require "tempfile"

class SidekiqHarness
  class PerformedJob
    attr_reader :job_class, :args, :bid
    def initialize(job_class:, args:, bid: nil)
      @job_class = job_class
      @args = args
      @bid = bid
    end
  end

  def perform(code, timeout: 30)
    raise ArgumentError, "timeout must be positive" unless timeout.positive?

    Sidekiq.redis(&:flushdb)

    Tempfile.create(["complex_workflows_harness", ".rb"]) do |file|
      file.write(harness_source(code))
      file.flush
      run_sidekiq(file.path, timeout)
    end
  end

  private

  def run_sidekiq(path, timeout)
    performed_jobs = []
    failed_jobs = []
    output = +""
    Open3.popen2e("bundle", "exec", "sidekiq", "-v", "-c10", "-t1", "-r", path,
      "-q", "critical", "-q", "high", "-q", "default", "-q", "low") do |stdin, stdout, wait_thr|
      stdin.close
      begin
        Timeout.timeout(timeout) do
          stdout.each_line do |line|
            output << line
            record_job(line, performed_jobs, failed_jobs)
          end
          unless wait_thr.value.success?
            raise "Unable to run sidekiq: exit status=#{wait_thr.value.exitstatus}\n#{output}"
          end
          raise "Sidekiq jobs failed:\n#{output}" unless failed_jobs.empty?
        end
      rescue Timeout::Error
        raise "No `shutdown` job encountered; timed out after #{timeout}s\n#{output}"
      ensure
        if wait_thr.alive?
          Process.kill("TERM", wait_thr.pid)
          Process.kill("KILL", wait_thr.pid) unless wait_thr.join(5)
        end
      end
    end
    performed_jobs
  end

  def record_job(line, performed_jobs, failed_jobs)
    parsed_line = JSON.parse(line)
    failed_jobs << parsed_line if parsed_line["msg"] == "fail"
    return unless parsed_line["msg"] == "start"

    context = parsed_line.fetch("ctx")
    return if context["class"] == "Sidekiq::Batch::Callback"

    performed_jobs << PerformedJob.new(job_class: context["class"], args: context["args"])
  rescue JSON::ParserError
    # Startup failures can print plain text; retain it in the failure output.
    nil
  end

  private

  def harness_source(code)
    <<~RUBY
      require "./lib/complex_workflows"
      require "./spec/support/sidekiq_config"
      require "./spec/support/jobs"
      require "./spec/support/workflow_harness"

      #{code.strip}
    RUBY
  end
end
