Rails.application.routes.draw do
  mount MolliePay::Engine => "/mollie_pay"
end
