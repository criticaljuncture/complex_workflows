Sidekiq.configure_server do |config|
  config.average_scheduled_poll_interval = 1
  config.logger.formatter = Sidekiq::Logger::Formatters::JSON.new
  config[:logged_job_attributes] = %w[bid tags args]
  config.on(:heartbeat) do
    Sidekiq.logger.debug "first heartbeat or recovering from an outage and need to reestablish our heartbeat"
  end
end
