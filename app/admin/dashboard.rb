# frozen_string_literal: true
ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { I18n.t("active_admin.dashboard") } do
    # Hero Section: Welcome Message with Cinematic Flair
    div class: "hero-section", style: "background: linear-gradient(to right, #1a1a1a, #4a4a4a); color: white; padding: 40px; border-radius: 10px; text-align: center; margin-bottom: 20px;" do
      h1 "Welcome to Movie Explorer+ Admin Hub 🎬", style: "font-size: 2.5em; margin-bottom: 10px;"
      p "Lights, camera, action! Manage your cinematic universe with ease.", style: "font-size: 1.2em; opacity: 0.9;"
      small "Explore movies, users, subscriptions, and more from your director's chair.", style: "display: block; margin-top: 10px; color: #ddd;"
    end

    # Columns Layout for Key Metrics and Panels
    columns do
      # Left Column: Recent Movies and Quick Stats
      column do
        # Recent Movies Panel
        panel "🎥 Latest Blockbusters" do
          if Movie.any?
            ul do
              Movie.order(created_at: :desc).limit(5).each do |movie|
                li do
                  div style: "display: flex; align-items: center; margin-bottom: 10px;" do
                    if movie.poster.attached?
                      img src: rails_blob_path(movie.poster, only_path: true), style: "width: 50px; height: 75px; object-fit: cover; margin-right: 10px; border-radius: 5px;"
                    end
                    div do
                      strong link_to(movie.title, admin_movie_path(movie))
                      div "Genre: #{movie.genre} | Premium: #{movie.premium ? 'Yes' : 'No'}", style: "font-size: 0.9em; color: #666;"
                    end
                  end
                end
              end
            end
            div link_to("View All Movies", admin_movies_path), class: "button", style: "margin-top: 10px; display: inline-block;"
          else
            para "No movies yet. Time to roll the film!", style: "color: #999;"
          end
        end

        # Quick Stats Panel
        panel "📊 Cinema Stats" do
          div class: "stats-grid", style: "display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; text-align: center;" do
            div class: "stat-box", style: "background: #f0f0f0; padding: 15px; border-radius: 5px;" do
              h3 Movie.count, style: "font-size: 1.8em; margin: 0; color: #333;"
              p "Total Movies", style: "margin: 5px 0; color: #666;"
            end
            div class: "stat-box", style: "background: #f0f0f0; padding: 15px; border-radius: 5px;" do
              h3 User.count, style: "font-size: 1.8em; margin: 0; color: #333;"
              p "Total Users", style: "margin: 5px 0; color: #666;"
            end
            div class: "stat-box", style: "background: #f0f0f0; padding: 15px; border-radius: 5px;" do
              h3 Subscription.where(plan_type: "premium").count, style: "font-size: 1.8em; margin: 0; color: #333;"
              p "Premium Subscriptions", style: "margin: 5px 0; color: #666;"
            end
          end
        end
      end

      # Right Column: User Activity and Subscription Insights
      column do
        # Recent Users Panel
        panel "👥 Recent Users" do
          if User.any?
            table_for User.order(created_at: :desc).limit(5) do
              column :email
              column :role
              column "Subscription" do |user|
                user.subscription&.plan_type&.capitalize || "None"
              end
              column :created_at, &:created_at
            end
            div link_to("View All Users", admin_users_path), class: "button", style: "margin-top: 10px; display: inline-block;"
          else
            para "No users yet. Time to build your audience!", style: "color: #999;"
          end
        end

        # Subscription Insights Panel
        panel "💸 Subscription Insights" do
          div style: "margin-bottom: 15px;" do
            h4 "Subscription Breakdown", style: "margin: 0 0 10px;"
            Subscription.plan_types.keys.each do |plan|
              count = Subscription.where(plan_type: plan).count
              div do
                span "#{plan.capitalize}: ", style: "font-weight: bold;"
                span count
                div style: "background: #ddd; height: 10px; border-radius: 5px; overflow: hidden; margin-top: 5px;" do
                  div style: "width: #{(count.to_f / Subscription.count * 100).round}%; background: #4CAF50; height: 100%;"
                end
              end
            end
          end
          div link_to("Manage Subscriptions", admin_subscriptions_path), class: "button", style: "margin-top: 10px; display: inline-block;"
        end
      end
    end

    # Footer Section: Quick Actions
    div class: "quick-actions", style: "margin-top: 20px; padding: 20px; background: #f9f9f9; border-radius: 10px; text-align: center;" do
      h3 "Quick Actions 🎥", style: "margin-bottom: 15px;"
      div style: "display: flex; justify-content: center; gap: 15px;" do
        link_to "Add New Movie", new_admin_movie_path, class: "button", style: "padding: 10px 20px; background: #e50914; color: white; border-radius: 5px;"
        link_to "Create User", new_admin_user_path, class: "button", style: "padding: 10px 20px; background: #1a73e8; color: white; border-radius: 5px;"
        link_to "View Reports", admin_dashboard_path, class: "button", style: "padding: 10px 20px; background: #ff9800; color: white; border-radius: 5px;"
      end
    end
  end # content
end