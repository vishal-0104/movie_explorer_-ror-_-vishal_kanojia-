FactoryBot.define do
  factory :movie do
    title { 'Inception' }
    genre { 'Sci-Fi' }
    release_year { 2010 }
    rating { 8.8 }
    director { 'Christopher Nolan' }
    duration { 148 }
    main_lead { 'Leonardo DiCaprio' }
    streaming_platform { 'Netflix' }
    description { 'A thief with the ability to enter dreams...' }
    premium { false }

    # Attach dummy files for poster and banner
    after(:build) do |movie|
      movie.poster.attach(
        io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'sample.jpg')),
        filename: 'sample.jpg',
        content_type: 'image/jpeg'
      )
      movie.banner.attach(
        io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'sample.jpg')),
        filename: 'sample.jpg',
        content_type: 'image/jpeg'
      )
    end
  end
end