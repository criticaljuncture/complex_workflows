class Job
  include Sidekiq::Job

  def perform(*args)
    if args == ["shutdown"]
      Process.kill("TERM", File.read("tmp/sidekiq.pid").to_i)
    end
  end
end
