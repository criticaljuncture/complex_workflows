require 'sidekiq/pro/web'

Rails.application.routes.draw do
  mount Sidekiq::Web => '/sidekiq'
end
