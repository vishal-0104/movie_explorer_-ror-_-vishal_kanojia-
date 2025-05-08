ActiveAdmin.register User do
  permit_params :email, :password, :password_confirmation, :role

  index do
    selectable_column
    id_column
    column :email
    column :role
    column :created_at
    column "Subscription Plan" do |user|
      user.subscription&.plan_type || "None"
    end
    actions
  end

  filter :email
  filter :role, as: :select, collection: User.roles.keys
  filter :subscription_plan_type, as: :select, collection: Subscription.plan_types.keys, label: "Subscription Plan"
  filter :created_at

  form do |f|
    f.inputs do
      f.input :email
      f.input :password
      f.input :password_confirmation
      f.input :role, as: :select, collection: User.roles.keys
    end
    f.actions
  end
end