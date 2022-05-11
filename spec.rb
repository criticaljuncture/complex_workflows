require 'open3'
require 'timeout'
require 'tempfile'
require 'sidekiq'

class SidekiqWorkflowHarness
  PID_FILE = "tmp/sidekiq.pid"

  class PerformedJob
    attr_reader :job_class, :args, :bid
    def initialize(job_class:, args:, bid: nil)
      @job_class = job_class
      @args = args
      @bid = bid
    end
  end

  def perform(timeout: 5)
    Redis.new.flushdb

    yield

    performed_jobs = []
    Open3.popen3("bundle exec sidekiq -r ./spec/fixtures/harness_code.rb") do |stdin, stdout, stderr, wait_thr|
      pid = wait_thr.pid
      File.open(PID_FILE, "w"){|f| f.write(pid)}

      Timeout.timeout(timeout) do
        stdout.each_line do |line|
          parsed_line = JSON.parse(line)
          if parsed_line["msg"] == "done"
            performed_jobs << PerformedJob.new(
              job_class: parsed_line["ctx"]["class"],
              args: parsed_line["ctx"]["args"],
            )
          end
        end
        stderr.each_line { |line| warn line }
      end
    rescue Timeout::Error
      warn "Sidekiq didn't get killed properly"
      Process.kill("TERM", pid)
    end
    performed_jobs
  ensure
    File.unlink(PID_FILE) if File.exists?(PID_FILE)
  end
end

require_relative 'spec/fixtures/jobs'

performed_jobs = SidekiqWorkflowHarness.new.perform do
  A.perform_async(1)
  B.perform_async(2)
  Shutdown.perform_async
end

puts performed_jobs.inspect
