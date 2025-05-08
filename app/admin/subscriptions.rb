ActiveAdmin.register Subscription do
  permit_params :user_id, :plan_type, :status, :start_date, :end_date
  index do
    selectable_column
    id_column
    column :user
    column :plan_type
    column :status
    actions
  end
end