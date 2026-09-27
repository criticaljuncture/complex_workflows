require "rack/mock"
require "sidekiq/pro/web"

RSpec.describe Sidekiq::Web do
  it "serves the dashboard with session middleware" do
    app = Rack::Builder.parse_file(File.expand_path("../../../config.ru", __dir__))
    response = Rack::MockRequest.new(app).get("/")

    expect(response.status).to eq(200)
    expect(response.body).to include("Sidekiq")
  end
end
