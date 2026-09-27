class Job
  include Sidekiq::Job

  def perform(*args)
    if args == ["shutdown"]
      Process.kill("TERM", Process.pid)
    end
  end
end
