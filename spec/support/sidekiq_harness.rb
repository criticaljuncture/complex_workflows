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
      require './lib/complex_workflows'
      require './spec/support/sidekiq_config.rb'
      require './spec/support/jobs.rb'
      require './spec/support/workflow_harness.rb'

      #{code}
    RUBY
    harness_code.close
    FileUtils.cp(harness_code.path, "copy.rb")

    performed_jobs = []
    status = Open3.popen3("bundle exec sidekiq -v -c10 -r #{harness_code.path} -q critical -q high -q default -q low") do |stdin, stdout, stderr, wait_thr|
      pid = wait_thr.pid
      File.open(PID_FILE, "w"){|f| f.write(pid)}

      Timeout.timeout(timeout) do
        stdout.each_line do |line|
          # puts line
          parsed_line = JSON.parse(line)
          if parsed_line["lvl"] == "WARN"
            warn parsed_line["msg"];
            next
          end

          if parsed_line["msg"] == "start"
            klass = parsed_line["ctx"]["class"]
            args = parsed_line["ctx"]["args"]
            performed_jobs << PerformedJob.new(
              job_class: klass,
              args: args,
            ) unless klass == 'Sidekiq::Batch::Callback'
          end
        end
        stderr.each_line { |line| puts line }

        if wait_thr.value != 0
          raise "Unable to start sidekiq: exit status=#{wait_thr.value}"
        end
      end
    rescue Timeout::Error
      Process.kill("TERM", pid)
      raise "No `shutdown` job encounted; timed out after #{timeout}s"
    end
    performed_jobs
  ensure
    File.unlink(PID_FILE) if File.exists?(PID_FILE)
  end
end