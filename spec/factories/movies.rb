FactoryBot.define do
  factory :movie do
    title { Faker::Movie.title }
    genre { %w[Action Sci-Fi Drama Comedy].sample }
    release_year { rand(1900..2023) }
    rating { rand(0.0..10.0).round(1) }
    director { Faker::Name.name }
    duration { "#{rand(1..3)}h #{rand(0..59)}m" }
    main_lead { Faker::Name.name }
    streaming_platform { %w[Netflix Amazon\ Prime Hulu Disney+].sample }
    description { Faker::Lorem.paragraph }
    premium { [true, false].sample }

    after(:build) do |movie|
      movie.poster.attach(
        io: fixture_file_upload(Rails.root.join("spec/fixtures/files/sample.jpg"), "image/jpeg"),
        filename: "sample.jpg",
        content_type: "image/jpeg"
      )
      movie.banner.attach(
        io: fixture_file_upload(Rails.root.join("spec/fixtures/files/sample.jpg"), "image/jpeg"),
        filename: "sample.jpg",
        content_type: "image/jpeg"
      )
    end
  end
end