# config.ru
Encoding.default_external = Encoding::UTF_8

require "sidekiq-pro"
require "sidekiq/pro/web"
require "rack/session/cookie"

Sidekiq.configure_client do |config|
  config.redis = {url: ENV.fetch("REDIS_URL") { "redis://#{ENV.fetch("REDIS_HOST", "localhost")}:#{ENV.fetch("REDIS_PORT", "6379")}" }}
end

unless File.exist?(".session.key")
  require "securerandom"
  File.write(".session.key", SecureRandom.hex(32))
end

use Rack::Session::Cookie, secret: File.read(".session.key"), same_site: true, max_age: 86400

run Rack::URLMap.new("/" => Sidekiq::Web)
