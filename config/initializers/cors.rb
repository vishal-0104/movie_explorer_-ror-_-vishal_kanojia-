Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'http://localhost:3000', 'http://localhost:3001' # Frontend URLs
    resource '*', headers: :any, methods: [:get, :post, :put, :patch, :delete, :options]
  end
end