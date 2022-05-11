require 'open3'
require 'timeout'
require 'tempfile'

class SidekiqHarness
  PID_FILE = "tmp/sidekiq.pid"

  class PerformedJob
    attr_reader :job_class, :args, :bid
    def initialize(job_class:, args:, bid: nil)
      @job_class = job_class
      @args = args
      @bid = bid
    end
  end

  def perform(code, timeout: 5)
    Redis.new.flushdb

    harness_code = Tempfile.new(["job", ".rb"], "./tmp/")
    harness_code.write <<-RUBY
      require './spec/support/harness_code.rb'
      require './spec/support/jobs.rb'
      require './spec/support/workflow_harness.rb'

      #{code}
    RUBY
    harness_code.close

    performed_jobs = []
    Open3.popen3("bundle exec sidekiq -r #{harness_code.path} -q critical -q high -q default -q low") do |stdin, stdout, stderr, wait_thr|
      pid = wait_thr.pid
      File.open(PID_FILE, "w"){|f| f.write(pid)}

      Timeout.timeout(timeout) do
        stdout.each_line do |line|
          parsed_line = JSON.parse(line)
          if parsed_line["msg"] == "done"
            klass = parsed_line["ctx"]["class"]
            args = parsed_line["ctx"]["args"]
            performed_jobs << PerformedJob.new(
              job_class: klass,
              args: args,
            ) unless klass == 'Sidekiq::Batch::Callback'
          end
        end
        stderr.each_line { |line| warn line }
      end
    rescue Timeout::Error
      Process.kill("TERM", pid)
      raise "Sidekiq didn't get killed properly"
    end
    performed_jobs
  ensure
    File.unlink(PID_FILE) if File.exists?(PID_FILE)
  end
end