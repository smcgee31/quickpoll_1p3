Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :lti do
    get "config", to: "configuration#show", defaults: { format: :xml }, as: :configuration
    post "launch", to: "launch#create", as: :launch

    get "me", to: "sessions#show", as: :me

    get "jwks", to: "jwks#show", as: :jwks
    get "tool_config", to: "tool_config#show", defaults: { format: :json }, as: :tool_config

    resources :polls, only: %i[index create] do
      resources :votes, only: :create
    end
  end
end
