class RemovePosterAndBannerUrlsFromMovies < ActiveRecord::Migration[7.2]
  def change
    remove_column :movies, :poster_url, :string
    remove_column :movies, :banner_url, :string
  end
end