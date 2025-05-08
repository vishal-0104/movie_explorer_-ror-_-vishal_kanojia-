# app/controllers/api/v1/movies_controller.rb
class Api::V1::MoviesController < ApplicationController
  before_action :authenticate_api_v1_user!
  before_action :restrict_to_supervisor, only: [:create, :update, :destroy]
  skip_before_action :verify_authenticity_token, only: [:create, :update]

  def index
    movies = Movie.search_and_filter(params.slice(:title, :genre, :release_year, :min_rating, :premium))
    movies = movies.where(premium: false) unless current_api_v1_user.can_access_premium_movies?
    movies = movies.page(params[:page]).per(10)
    render json: {
      movies: movies.as_json(methods: [:poster_url, :banner_url]),
      meta: { current_page: movies.current_page, total_pages: movies.total_pages }
    }
  end

  def show
    movie = Movie.find(params[:id])
    render json: movie.as_json(methods: [:poster_url, :banner_url])
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
      render json: result[:movie].as_json(methods: [:poster_url, :banner_url])
    else
      render json: { errors: result[:errors] }, status: :unprocessable_entity
    end
  end

  def destroy
    movie = Movie.find(params[:id])
    movie.destroy
    head :no_content
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