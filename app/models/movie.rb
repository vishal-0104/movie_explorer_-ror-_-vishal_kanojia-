class Movie < ApplicationRecord
  validates :title, :genre, :release_year, :rating, :director, :duration, :main_lead, :streaming_platform, :description, presence: true
  validates :premium, inclusion: { in: [true, false] }
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }
  validates :release_year, numericality: { greater_than: 1888, only_integer: true }

  has_one_attached :poster
  has_one_attached :banner
  validates :poster, content_type: ['image/jpeg', 'image/png', 'image/gif']
  validates :banner, content_type: ['image/jpeg', 'image/png', 'image/gif']


  def self.search_and_filter(params)
    movies = all
    movies = movies.where('title ILIKE ?', "%#{params[:title]}%") if params[:title].present?
    movies = movies.where(genre: params[:genre]) if params[:genre].present?
    movies = movies.where(release_year: params[:release_year]) if params[:release_year].present?
    movies = movies.where('rating >= ?', params[:min_rating].to_f) if params[:min_rating].present?
    movies = movies.where(premium: params[:premium]) if params[:premium].present? && params[:premium].in?(['true', 'false', true, false])
    movies
  end

  def self.create_movie(params)
    movie = new(params.except(:poster, :banner))
    if movie.save
      movie.poster.attach(params[:poster]) if params[:poster].present?
      movie.banner.attach(params[:banner]) if params[:banner].present?
      { success: true, movie: movie }
    else
      { success: false, errors: movie.errors.full_messages }
    end
  end

  def update_movie(params)
    if update(params.except(:poster, :banner))
      poster.attach(params[:poster]) if params[:poster].present?
      banner.attach(params[:banner]) if params[:banner].present?
      { success: true, movie: self }
    else
      { success: false, errors: errors.full_messages }
    end
  end

  def poster_url
    return unless poster.attached?
    if poster.service.is_a?(ActiveStorage::Service::CloudinaryService)
      poster.url
    else
      Rails.application.routes.url_helpers.rails_blob_url(poster, only_path: true)
    end
  end

  def banner_url
    return unless banner.attached?
    if banner.service.is_a?(ActiveStorage::Service::CloudinaryService)
      banner.url
    else
      Rails.application.routes.url_helpers.rails_blob_url(banner, only_path: true)
    end
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[title genre release_year rating director duration main_lead streaming_platform description premium created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end