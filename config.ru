# config.ru
require 'sidekiq-pro'
require 'sidekiq/pro/web'

Sidekiq.configure_client do |config|
  config.redis = { url: "redis://#{ENV['REDIS_HOST']}:#{ENV['REDIS_PORT']}" }
end

unless File.exists?(".session.key")
  require 'securerandom'
  File.open(".session.key", "w") {|f| f.write(SecureRandom.hex(32)) }
end

use Rack::Session::Cookie, secret: File.read(".session.key"), same_site: true, max_age: 86400

run Rack::URLMap.new('/' => Sidekiq::Web)
