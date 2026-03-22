MolliePay::Engine.routes.draw do
  resources :webhooks,       only: :create
  resources :webhook_events, only: :create
end
