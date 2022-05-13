class Job
  include Sidekiq::Job

  def perform(*args)
    if args == ["shutdown"]
      Process.kill("TERM", File.read("tmp/sidekiq.pid").to_i)
    elsif args.first == "sleep"
      sleep(args[1])
    end
  end
end