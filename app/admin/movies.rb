ActiveAdmin.register Movie do
  permit_params :title, :genre, :release_year, :rating, :director, :duration,
                :main_lead, :streaming_platform, :description, :premium, :poster, :banner

  filter :title
  filter :genre
  filter :release_year
  filter :rating
  filter :director
  filter :duration
  filter :main_lead
  filter :streaming_platform
  filter :description
  filter :premium
  filter :created_at
  filter :updated_at

  form do |f|
    f.inputs do
      f.input :title
      f.input :genre
      f.input :release_year
      f.input :rating
      f.input :director
      f.input :duration
      f.input :main_lead
      f.input :streaming_platform
      f.input :description
      f.input :premium
      f.input :poster, as: :file
      f.input :banner, as: :file
    end
    f.actions
  end

  controller do
    def create
      @movie = Movie.new(permitted_params[:movie].except(:poster, :banner))
      if @movie.save
        @movie.poster.attach(permitted_params[:movie][:poster]) if permitted_params[:movie][:poster].present?
        @movie.banner.attach(permitted_params[:movie][:banner]) if permitted_params[:movie][:banner].present?
        redirect_to admin_movie_path(@movie), notice: 'Movie created successfully.'
      else
        render :new
      end
    end

    def update
      @movie = Movie.find(params[:id])
      if @movie.update(permitted_params[:movie].except(:poster, :banner))
        @movie.poster.attach(permitted_params[:movie][:poster]) if permitted_params[:movie][:poster].present?
        @movie.banner.attach(permitted_params[:movie][:banner]) if permitted_params[:movie][:banner].present?
        redirect_to admin_movie_path(@movie), notice: 'Movie updated successfully.'
      else
        render :edit
      end
    end
  end

  show do
    attributes_table do
      row :title
      row :genre
      row :release_year
      row :rating
      row :director
      row :duration
      row :main_lead
      row :streaming_platform
      row :description
      row :premium
      row :poster do |movie|
        if movie.poster.attached?
          tag.img src: movie.poster_url, width: 100
        else
          'No poster attached'
        end
      end
      row :banner do |movie|
        if movie.banner.attached?
          tag.img src: movie.banner_url, width: 100
        else
          'No banner attached'
        end
      end
    end
  end
end