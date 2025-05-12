class AddIndexesAndConstraintsToMovies < ActiveRecord::Migration[7.2]
  def change
    
    add_index :movies, :title
    add_index :movies, :genre
    add_index :movies, :release_year
    add_index :movies, :premium

    
    change_column :movies, :rating, :decimal, precision: 3, scale: 1, null: false, default: 0.0
    change_column :movies, :release_year, :integer, null: false, limit: 4 
  end
end