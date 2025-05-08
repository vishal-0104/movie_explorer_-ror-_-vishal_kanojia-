require 'rails_helper'

RSpec.describe Movie, type: :model do
  it 'is valid with valid attributes' do
    movie = build(:movie)
    expect(movie).to be_valid
  end

  it 'is invalid without poster on create' do
    movie = build(:movie, poster: nil)
    movie.validate
    expect(movie.errors[:poster]).to include('must be attached')
  end
end