class Api::V1::MoviesController < ApplicationController
  before_action :authenticate_api_v1_user!
  before_action :restrict_to_supervisor, only: [:create, :update, :destroy]
  skip_before_action :verify_authenticity_token, only: [:create, :update]

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
    
    # Check if the user can access the movie (premium check)
    if movie.premium && !current_api_v1_user.can_access_premium_movies?
      render json: { error: 'Premium subscription required to view this movie' }, status: :forbidden
      return
    end
    
    render json: movie.as_json(methods: [:poster_url, :banner_url]), status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Movie not found' }, status: :not_found
  end

  def create
    result = Movie.create_movie(movie_params)
    if result[:success]
      render json: result[:movie].as_json(methods: [:poster_url, :banner_url]), status: :created
    else
      render json: { errors: result[:errors] }, status: :unprocessable_entity
    end
  end

  def update
    movie = Movie.find(params[:id])
    result = movie.update_movie(movie_params)
    if result[:success]
      render json: result[:movie].as_json(methods: [:poster_url, :banner_url]), status: :ok
    else
      render json: { errors: result[:errors] }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Movie not found' }, status: :not_found
  end

  def destroy
    movie = Movie.find(params[:id])
    movie.destroy
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Movie not found' }, status: :not_found
  end

  private

  def movie_params
    params.permit(
      :title, :genre, :release_year, :rating, :director, :duration,
      :main_lead, :streaming_platform, :description, :premium, :poster, :banner
    )
  end

  def restrict_to_supervisor
    render json: { error: 'Unauthorized' }, status: :forbidden unless current_api_v1_user.supervisor?
  end
end