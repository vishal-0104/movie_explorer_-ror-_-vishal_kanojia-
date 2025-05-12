require 'rails_helper'

RSpec.describe Movie, type: :model do
  let(:movie) { build(:movie) }

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
    it { should validate_numericality_of(:rating).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(10) }
    it { should validate_numericality_of(:release_year).only_integer.is_greater_than(1888) }

    context 'with invalid rating' do
      it 'is invalid with rating < 0' do
        movie.rating = -1
        expect(movie).not_to be_valid
        expect(movie.errors[:rating]).to include('must be greater than or equal to 0')
      end

      it 'is invalid with rating > 10' do
        movie.rating = 11
        expect(movie).not_to be_valid
        expect(movie.errors[:rating]).to include('must be less than or equal to 10')
      end
    end

    context 'with invalid release_year' do
      it 'is invalid with non-integer release_year' do
        movie.release_year = 2000.5
        expect(movie).not_to be_valid
        expect(movie.errors[:release_year]).to include('must be an integer')
      end

      it 'is invalid with release_year <= 1888' do
        movie.release_year = 1888
        expect(movie).not_to be_valid
        expect(movie.errors[:release_year]).to include('must be greater than 1888')
      end
    end
  end

  describe 'attachments' do
    it 'is valid with valid poster and banner' do
      expect(movie).to be_valid
    end

    it 'is invalid with wrong content type for poster' do
      movie.poster.attach(io: StringIO.new('data'), filename: 'test.txt', content_type: 'text/plain')
      expect(movie).not_to be_valid
      expect(movie.errors[:poster]).to include('must be a valid content type')
    end

    it 'is invalid with wrong content type for banner' do
      movie.banner.attach(io: StringIO.new('data'), filename: 'test.txt', content_type: 'text/plain')
      expect(movie).not_to be_valid
      expect(movie.errors[:banner]).to include('must be a valid content type')
    end

    it 'is invalid without poster' do
      movie.poster.purge
      expect(movie).not_to be_valid
      expect(movie.errors[:poster]).to include("can't be blank")
    end

    it 'is invalid without banner' do
      movie.banner.purge
      expect(movie).not_to be_valid
      expect(movie.errors[:banner]).to include("can't be blank")
    end
  end

  describe '.search_and_filter' do
    before do
      allow(NotificationService).to receive(:send_new_movie_notification)
      Movie.destroy_all
      create(:movie, title: 'Inception', genre: 'Sci-Fi', release_year: 2010, rating: 8.8, director: 'Christopher Nolan',
                     duration: '2h 28m', main_lead: 'Leonardo DiCaprio', streaming_platform: 'Netflix',
                     description: 'Dream heist thriller', premium: false)
      create(:movie, title: 'Tenet', genre: 'Action', release_year: 2020, rating: 7.5, director: 'Christopher Nolan',
                     duration: '2h', main_lead: 'John David Washington', streaming_platform: 'Amazon Prime',
                     description: 'Time travel', premium: true)
    end

    it 'filters by title' do
      results = Movie.search_and_filter({ title: 'Tenet' })
      expect(results.count).to eq(1)
      expect(results.first.title).to eq('Tenet')
    end

    it 'filters by genre' do
      results = Movie.search_and_filter({ genre: 'Sci-Fi' })
      expect(results.count).to eq(1)
      expect(results.first.genre).to eq('Sci-Fi')
    end

    it 'filters by release_year' do
      results = Movie.search_and_filter({ release_year: 2010 })
      expect(results.count).to eq(1)
      expect(results.first.release_year).to eq(2010)
    end

    it 'filters by min_rating' do
      results = Movie.search_and_filter({ min_rating: 8.0 })
      expect(results.count).to eq(1)
      expect(results.first.rating).to eq(8.8)
    end

    it 'filters by premium' do
      results = Movie.search_and_filter({ premium: true })
      expect(results.count).to eq(1)
      expect(results.first.premium).to eq(true)
    end

    it 'filters by multiple criteria' do
      results = Movie.search_and_filter({ title: 'Inception', genre: 'Sci-Fi', release_year: 2010 })
      expect(results.count).to eq(1)
      expect(results.first.title).to eq('Inception')
    end

    it 'returns no results for non-matching criteria' do
      results = Movie.search_and_filter({ title: 'Nonexistent' })
      expect(results.count).to eq(0)
    end

    it 'handles empty params' do
      results = Movie.search_and_filter({})
      expect(results.count).to eq(2)
    end

    it 'handles invalid min_rating gracefully' do
      results = Movie.search_and_filter({ min_rating: 'invalid' })
      expect(results.count).to eq(2) # Ignores invalid input
    end
  end

  describe '.create_movie' do
    before { allow(NotificationService).to receive(:send_new_movie_notification) }

    it 'creates a movie with valid attributes' do
      file = fixture_file_upload(Rails.root.join('spec/fixtures/files/sample.jpg'), 'image/jpeg')
      result = Movie.create_movie(
        title: 'Tenet',
        genre: 'Sci-Fi',
        release_year: 2020,
        rating: 7.5,
        director: 'Christopher Nolan',
        duration: '2h 30m',
        main_lead: 'John David Washington',
        streaming_platform: 'Amazon Prime',
        description: 'Time travel thriller',
        premium: true,
        poster: file,
        banner: file
      )
      expect(result[:success]).to eq(true)
      expect(result[:movie]).to be_persisted
      expect(result[:movie].title).to eq('Tenet')
    end

    it 'returns error on invalid attributes' do
      result = Movie.create_movie(title: nil)
      expect(result[:success]).to eq(false)
      expect(result[:errors][:title]).to include("can't be blank")
    end

    it 'returns error on invalid attachment content type' do
      file = fixture_file_upload(StringIO.new('data'), 'test.txt', 'text/plain')
      result = Movie.create_movie(
        title: 'Tenet',
        genre: 'Sci-Fi',
        release_year: 2020,
        rating: 7.5,
        director: 'Christopher Nolan',
        duration: '2h 30m',
        main_lead: 'John David Washington',
        streaming_platform: 'Amazon Prime',
        description: 'Time travel thriller',
        premium: true,
        poster: file,
        banner: file
      )
      expect(result[:success]).to eq(false)
      expect(result[:errors][:poster]).to include('must be a valid content type')
    end
  end

  describe '#update_movie' do
    let(:movie) { create(:movie) }
    before { allow(NotificationService).to receive(:send_updated_movie_notification) }

    it 'updates successfully with valid attributes' do
      result = movie.update_movie(title: 'Dunkirk')
      expect(result[:success]).to eq(true)
      expect(movie.reload.title).to eq('Dunkirk')
    end

    it 'fails with invalid attributes' do
      result = movie.update_movie(title: '')
      expect(result[:success]).to eq(false)
      expect(result[:errors][:title]).to include("can't be blank")
    end

    it 'updates attachments successfully' do
      new_file = fixture_file_upload(Rails.root.join('spec/fixtures/files/sample.jpg'), 'image/jpeg')
      result = movie.update_movie(poster: new_file)
      expect(result[:success]).to eq(true)
      expect(movie.poster).to be_attached
    end

    it 'fails with invalid attachment content type' do
      file = fixture_file_upload(StringIO.new('data'), 'test.txt', 'text/plain')
      result = movie.update_movie(poster: file)
      expect(result[:success]).to eq(false)
      expect(result[:errors][:poster]).to include('must be a valid content type')
    end
  end

  describe '#poster_url and #banner_url' do
    let(:movie) { create(:movie) }
    before { allow(NotificationService).to receive(:send_new_movie_notification) }

    it 'returns the poster url when attached' do
      expect(movie.poster_url).to be_present
      expect(movie.poster_url).to include('sample.jpg')
    end

    it 'returns nil when poster not attached' do
      movie.poster.purge
      expect(movie.poster_url).to be_nil
    end

    it 'returns the banner url when attached' do
      expect(movie.banner_url).to be_present
      expect(movie.banner_url).to include('sample.jpg')
    end

    it 'returns nil when banner not attached' do
      movie.banner.purge
      expect(movie.banner_url).to be_nil
    end
  end

  describe 'callbacks' do
    let(:movie) { build(:movie) }

    it 'calls send_new_movie_notification on create' do
      expect(NotificationService).to receive(:send_new_movie_notification).once
      movie.save
    end

    it 'calls send_updated_movie_notification on update' do
      movie.save
      expect(NotificationService).to receive(:send_updated_movie_notification).once
      movie.update(title: 'Updated')
    end

    it 'calls send_deleted_movie_notification on destroy' do
      movie.save
      expect(NotificationService).to receive(:send_deleted_movie_notification).once
      movie.destroy
    end

    context 'when notification service fails' do
      it 'still creates movie despite notification failure' do
        allow(NotificationService).to receive(:send_new_movie_notification).and_raise(StandardError)
        expect { movie.save }.not_to raise_error
        expect(movie).to be_persisted
      end

      it 'still updates movie despite notification failure' do
        movie.save
        allow(NotificationService).to receive(:send_updated_movie_notification).and_raise(StandardError)
        expect { movie.update(title: 'Updated') }.not_to raise_error
        expect(movie.reload.title).to eq('Updated')
      end

      it 'still destroys movie despite notification failure' do
        movie.save
        allow(NotificationService).to receive(:send_deleted_movie_notification).and_raise(StandardError)
        expect { movie.destroy }.not_to raise_error
        expect(Movie.exists?(movie.id)).to be_false
      end
    end
  end
end