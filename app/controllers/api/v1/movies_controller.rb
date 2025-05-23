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

    if movie.premium && !@current_user.can_access_premium_movies?
      render json: { error: "Premium subscription required to view this movie" }, status: :forbidden
      return
    end

    render json: movie.as_json(methods: [:poster_url, :banner_url]), status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Movie not found" }, status: :not_found
  end

  def create
    result = Movie.create_movie(movie_params)
    if result[:success]
      NotificationService.send_new_movie_notification(result[:movie])
      render json: result[:movie].as_json(methods: [:poster_url, :banner_url]), status: :created
    else
      render json: { errors: result[:errors] }, status: :unprocessable_entity
    end
  end

  def update
    movie = Movie.find(params[:id])
    result = movie.update_movie(movie_params)
    if result[:success]
      NotificationService.send_updated_movie_notification(result[:movie])
      render json: result[:movie].as_json(methods: [:poster_url, :banner_url]), status: :ok
    else
      render json: { errors: result[:errors] }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Movie not found" }, status: :not_found
  end

  def destroy
    movie = Movie.find(params[:id])
    NotificationService.send_deleted_movie_notification(movie)
    movie.destroy
    render json: { message: "Movie deleted successfully", id: movie.id }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Movie not found" }, status: :not_found
  rescue StandardError => e
    Rails.logger.error("Failed to send delete notification: #{e.message}")
    render json: { error: "Failed to delete movie" }, status: :internal_server_error
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
      Rails.logger.warn("Unauthorized access attempt by user: #{@current_user&.email || 'Unauthenticated'}")
      render json: { error: "Only supervisors can perform this action" }, status: :forbidden
    end
  end
end