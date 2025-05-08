class AddPosterAndBannerUrlsToMovies < ActiveRecord::Migration[7.2]
  def change
    add_column :movies, :poster_url, :string
    add_column :movies, :banner_url, :string
  end
end
