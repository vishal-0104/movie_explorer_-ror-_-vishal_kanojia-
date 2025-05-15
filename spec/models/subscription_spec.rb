require 'rails_helper'

RSpec.describe Movie, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:genre) }
    it { should validate_presence_of(:release_year) }
    it { should validate_presence_of(:rating) }
    it { should validate_presence_of(:director) }
    it { should validate_presence_of(:duration) }
    it { should validate_presence_of(:main_lead) }
    it { should validate_presence_of(:streaming_platform) }
    it { should validate_presence_of(:description) }

    it { should validate_inclusion_of(:premium).in_array([true, false]) }

    it { should validate_numericality_of(:rating).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(10) }
    it { should validate_numericality_of(:release_year).is_greater_than(1888).only_integer }

    it 'validates poster content type' do
      movie = build(:movie)
      movie.poster.detach
      movie.poster.attach(
        io: StringIO.new('invalid content'),
        filename: 'invalid.txt',
        content_type: 'text/plain'
      )
      expect(movie).not_to be_valid
      expect(movie.errors[:poster]).to include('has an invalid content type')
    end

    it 'validates banner content type' do
      movie = build(:movie)
      movie.banner.detach
      movie.banner.attach(
        io: StringIO.new('invalid content'),
        filename: 'invalid.txt',
        content_type: 'text/plain'
      )
      expect(movie).not_to be_valid
      expect(movie.errors[:banner]).to include('has an invalid content type')
    end
  end

  describe 'associations' do
    it { should have_one_attached(:poster) }
    it { should have_one_attached(:banner) }
  end

  describe '.search_and_filter' do
    let!(:movie1) { create(:movie, title: 'Inception', genre: 'Sci-Fi', release_year: 2010, rating: 8.8, premium: false) }
    let!(:movie2) { create(:movie, title: 'The Matrix', genre: 'Sci-Fi', release_year: 1999, rating: 8.7, premium: true) }
    let!(:movie3) { create(:movie, title: 'Titanic', genre: 'Romance', release_year: 1997, rating: 7.8, premium: false) }

    it 'filters by title' do
      expect(Movie.search_and_filter(title: 'Incep')).to eq([movie1])
    end

    it 'filters by genre' do
      expect(Movie.search_and_filter(genre: 'Sci-Fi')).to match_array([movie1, movie2])
    end

    it 'filters by release_year' do
      expect(Movie.search_and_filter(release_year: 2010)).to eq([movie1])
    end

    it 'filters by min_rating' do
      expect(Movie.search_and_filter(min_rating: 8.0)).to match_array([movie1, movie2])
    end

    it 'filters by premium' do
      expect(Movie.search_and_filter(premium: true)).to eq([movie2])
      expect(Movie.search_and_filter(premium: 'false')).to eq([movie1, movie3])
    end

    it 'combines multiple filters' do
      expect(Movie.search_and_filter(genre: 'Sci-Fi', min_rating: 8.8)).to eq([movie1])
    end

    it 'returns all movies when no filters are provided' do
      expect(Movie.search_and_filter({})).to match_array([movie1, movie2, movie3])
    end
  end

  describe '.create_movie' do
    let(:valid_params) do
      {
        title: 'New Movie',
        genre: 'Action',
        release_year: 2023,
        rating: 7.5,
        director: 'John Doe',
        duration: 120,
        main_lead: 'Jane Doe',
        streaming_platform: 'HBO',
        description: 'An action-packed adventure...',
        premium: true,
        poster: Rack::Test::UploadedFile.new(StringIO.new('dummy image'), 'image/jpeg', original_filename: 'sample.jpg'),
        banner: Rack::Test::UploadedFile.new(StringIO.new('dummy image'), 'image/jpeg', original_filename: 'sample.jpg')
      }
    end

    let(:invalid_params) do
      valid_params.merge(title: nil)
    end

    it 'creates a movie with valid params and attaches poster and banner' do
      result = Movie.create_movie(valid_params)
      expect(result[:success]).to be true
      movie = result[:movie]
      expect(movie).to be_persisted
      expect(movie.title).to eq('New Movie')
      expect(movie.poster).to be_attached
      expect(movie.banner).to be_attached
    end

    it 'returns errors for invalid params' do
      result = Movie.create_movie(invalid_params)
      expect(result[:success]).to be false
      expect(result[:errors]).to include("Title can't be blank")
    end
  end

  describe '#update_movie' do
    let(:movie) { create(:movie) }
    let(:update_params) do
      {
        title: 'Updated Movie',
        poster: Rack::Test::UploadedFile.new(StringIO.new('dummy image'), 'image/jpeg', original_filename: 'sample.jpg'),
        banner: Rack::Test::UploadedFile.new(StringIO.new('dummy image'), 'image/jpeg', original_filename: 'sample.jpg')
      }
    end

    let(:invalid_params) do
      update_params.merge(rating: 11)
    end

    it 'updates a movie with valid params and attaches new poster and banner' do
      result = movie.update_movie(update_params)
      expect(result[:success]).to be true
      movie.reload
      expect(movie.title).to eq('Updated Movie')
      expect(movie.poster).to be_attached
      expect(movie.banner).to be_attached
    end

    it 'returns errors for invalid params' do
      result = movie.update_movie(invalid_params)
      expect(result[:success]).to be false
      expect(result[:errors]).to include('Rating must be less than or equal to 10')
    end
  end

  describe 'notifications' do
    let(:movie) { build(:movie) }

    before do
      allow(NotificationService).to receive(:send_new_movie_notification)
      allow(NotificationService).to receive(:send_updated_movie_notification)
      allow(NotificationService).to receive(:send_deleted_movie_notification)
      allow(Rails.logger).to receive(:error)
    end

    it 'sends new movie notification on create' do
      movie.save!
      expect(NotificationService).to have_received(:send_new_movie_notification).with(movie)
    end

    it 'sends updated movie notification on update' do
      movie.save!
      movie.update!(title: 'Updated Title')
      expect(NotificationService).to have_received(:send_updated_movie_notification).with(movie)
    end

    it 'sends deleted movie notification on destroy' do
      movie.save!
      movie.destroy!
      expect(NotificationService).to have_received(:send_deleted_movie_notification).with(movie)
    end

    it 'logs error but does not raise on new movie notification failure' do
      allow(NotificationService).to receive(:send_new_movie_notification).and_raise(StandardError.new('Notification failed'))
      expect { movie.save! }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/\[Movie\] Failed to send new movie notification for movie #{movie.id}: Notification failed/)
    end

    it 'logs error but does not raise on updated movie notification failure' do
      movie.save!
      allow(NotificationService).to receive(:send_updated_movie_notification).and_raise(StandardError.new('Notification failed'))
      expect { movie.update!(title: 'Updated') }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/\[Movie\] Failed to send updated movie notification for movie #{movie.id}: Notification failed/)
    end

    it 'logs error but does not raise on deleted movie notification failure' do
      movie.save!
      allow(NotificationService).to receive(:send_deleted_movie_notification).and_raise(StandardError.new('Notification failed'))
      expect { movie.destroy! }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/\[Movie\] Failed to send deleted movie notification for movie #{movie.id}: Notification failed/)
    end
  end

  describe '.ransackable_attributes' do
    it 'returns allowed searchable attributes' do
      expect(Movie.ransackable_attributes).to match_array(
        %w[title genre release_year rating director duration main_lead streaming_platform description premium created_at updated_at]
      )
    end
  end

  describe '.ransackable_associations' do
    it 'returns empty array' do
      expect(Movie.ransackable_associations).to eq([])
    end
  end
end