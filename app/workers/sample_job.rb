class SampleJob
  include Sidekiq::Worker
  sidekiq_options backtrace: 20

  def perform(title_version_id, options={})
    puts "SampleJob tv=#{title_version_id} (#{options.inspect})"
    sleep(1)
  end
end