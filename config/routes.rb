Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)

  namespace :api do
    namespace :v1 do
      devise_for :users, controllers: {
        sessions: 'api/v1/users/sessions',
        registrations: 'api/v1/users/registrations'
      }

      resources :movies, only: [:index, :show, :create, :update, :destroy]

      resources :subscriptions, only: [:create] do
        collection do
          get :status
          post :confirm
          post :cancel
        end
      end

      post 'webhooks/stripe', to: 'subscriptions#webhook'

      patch 'users/update_device_token', to: 'users#update_device_token'
    end
  end
end