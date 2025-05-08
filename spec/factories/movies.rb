FactoryBot.define do
  factory :movie do
    title { Faker::Movie.title }
    genre { Movie::VALID_GENRES.sample }
    release_year { rand(1900..Time.current.year) }
    rating { rand(0.0..10.0).round(1) }
    director { Faker::Name.name }
    duration { rand(30..180) }
    main_lead { Faker::Name.name }
    streaming_platform { Movie::VALID_STREAMING_PLATFORMS.sample }
    description { Faker::Lorem.paragraph(sentence_count: 3) }
    premium { [true, false].sample }
    after(:build) do |movie|
      movie.poster.attach(
        io: File.open(Rails.root.join('tmp', 'sample_poster.jpg')),
        filename: 'sample_poster.jpg',
        content_type: 'image/jpeg'
      )
      movie.banner.attach(
        io: File.open(Rails.root.join('tmp', 'sample_banner.jpg')),
        filename: 'sample_banner.jpg',
        content_type: 'image/jpeg'
      )
    end
  end
end