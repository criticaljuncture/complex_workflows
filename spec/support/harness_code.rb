class CustomJobLogger < Sidekiq::JobLogger
  # Monkey patching of Sidekiq 6.4.2 implementation
  def prepare(job_hash, &block)
    # If we're using a wrapper class, like ActiveJob, use the "wrapped"
    # attribute to expose the underlying thing.
    h = {
      class: job_hash["display_class"] || job_hash["wrapped"] || job_hash["class"],
      jid: job_hash["jid"]
    }
    h[:bid] = job_hash["bid"] if job_hash.has_key?("bid")
    h[:tags] = job_hash["tags"] if job_hash.has_key?("tags")

    # Added to 6.4.2 implementation
    h[:args] = job_hash["args"] if job_hash.has_key?("args")

    Thread.current[:sidekiq_context] = h
    level = job_hash["log_level"]
    if level
      @logger.log_at(level, &block)
    else
      yield
    end
  ensure
    Thread.current[:sidekiq_context] = nil
  end
end

Sidekiq.configure_server do |config|
  config.log_formatter = Sidekiq::Logger::Formatters::JSON.new
  config.options[:job_logger] = CustomJobLogger
end