# app/models/movie.rb
class Movie < ApplicationRecord
  validates :title, :genre, :release_year, :rating, :director, :duration, :main_lead, :streaming_platform, :description, presence: true
  validates :premium, inclusion: { in: [true, false] }

  has_one_attached :poster
  has_one_attached :banner

  after_create :send_notification

  def self.search_and_filter(params)
    movies = all
    movies = movies.where('title ILIKE ?', "%#{params[:title]}%") if params[:title].present?
    movies = movies.where(genre: params[:genre]) if params[:genre].present?
    movies = movies.where(release_year: params[:release_year]) if params[:release_year].present?
    movies = movies.where('rating >= ?', params[:min_rating]) if params[:min_rating].present?
    movies = movies.where(premium: params[:premium]) if params[:premium].present?
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
    if poster.attached?
      # Use Cloudinary URL if configured, otherwise Active Storage URL
      if poster.service.is_a?(ActiveStorage::Service::CloudinaryService)
        poster.url
      else
        Rails.application.routes.url_helpers.rails_blob_url(poster, only_path: true)
      end
    end
  end

  def banner_url
    if banner.attached?
      if banner.service.is_a?(ActiveStorage::Service::CloudinaryService)
        banner.url
      else
        Rails.application.routes.url_helpers.rails_blob_url(banner, only_path: true)
      end
    end
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[title genre release_year rating director duration main_lead streaming_platform description premium created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end

  after_create :send_notification
  private

  def send_notification
    return unless User.exists?(device_token: present?) # Skip if no users with device tokens

    device_tokens = User.where.not(device_token: [nil, '']).pluck(:device_token)
    return if device_tokens.empty?

    notification = {
      title: 'New Movie Added!',
      body: "#{title} is now available on #{streaming_platform}.",
      data: {
        movie_id: id.to_s,
        poster_url: poster_url || '',
        banner_url: banner_url || ''
      }
    }

    device_tokens.each do |token|
      begin
        FCMService.send_notification(token, notification)
      rescue StandardError => e
        Rails.logger.error "Failed to send notification to #{token}: #{e.message}"
      end
    end
  end
end