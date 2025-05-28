class Api::V1::MoviesController < ApplicationController
  before_action :authenticate_api_v1_user!, except: [:index]
  before_action :restrict_to_supervisor, only: [:create, :update, :destroy]
  skip_before_action :verify_authenticity_token

  def index
    movies = Movie.search_and_filter(params.slice(:title, :genre, :release_year, :min_rating, :premium))
    movies = movies.page(params[:page]).per(10)
    render json: {
      movies: movies.as_json(methods: [:poster_url, :banner_url]),
      meta: { current_page: movies.current_page, total_pages: movies.total_pages, total_count: movies.total_count }
    }, status: :ok
  end

  def show
    movie = Movie.find(params[:id])
    unless @current_user.supervisor? || @current_user.can_access_premium_movies?
      if movie.premium
        render json: { error: "Premium subscription required to view this movie" }, status: :forbidden
        return
      end
    end
    render json: movie.as_json(methods: [:poster_url, :banner_url]), status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Movie not found" }, status: :not_found
  end

  def create
    movie = Movie.new(movie_params)
    if movie.save
      begin
        NotificationService.send_new_movie_notification(movie)
      rescue StandardError => e
        Rails.logger.error("Failed to send new movie notification for movie #{movie.id}: #{e.message}, Backtrace: #{e.backtrace.join("\n")}")
      end
      render json: movie.as_json(methods: [:poster_url, :banner_url]), status: :created
    else
      render json: { errors: movie.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    movie = Movie.find(params[:id])
    if movie.update(movie_params)
      begin
        NotificationService.send_updated_movie_notification(movie)
      rescue StandardError => e
        Rails.logger.error("Failed to send updated movie notification for movie #{movie.id}: #{e.message}, Backtrace: #{e.backtrace.join("\n")}")
      end
      render json: movie.as_json(methods: [:poster_url, :banner_url]), status: :ok
    else
      render json: { errors: movie.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Movie not found" }, status: :not_found
  end

  def destroy
    movie = Movie.find(params[:id])
    if movie.destroy
      begin
        NotificationService.send_deleted_movie_notification(movie)
      rescue StandardError => e
        Rails.logger.error("Failed to send deleted movie notification for movie #{movie.id}: #{e.message}, Backtrace: #{e.backtrace.join("\n")}")
      end
      render json: { message: "Movie deleted successfully", id: movie.id }, status: :ok
    else
      render json: { error: "Failed to delete movie" }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Movie not found" }, status: :not_found
  end

  private

  def movie_params
    params.permit(
      :title, :genre, :release_year, :rating, :director, :duration,
      :main_lead, :streaming_platform, :description, :premium, :poster, :banner
    ).tap do |whitelisted|
      whitelisted[:premium] = ActiveModel::Type::Boolean.new.cast(whitelisted[:premium]) if whitelisted[:premium].present?
    end
  end

  def restrict_to_supervisor
    unless @current_user&.supervisor?
      render json: { error: "Only supervisors can perform this action" }, status: :forbidden
    end
  end
end