class CreateMovies < ActiveRecord::Migration[7.2]
  def change
    create_table :movies do |t|
      t.string :title, null: false
      t.string :genre, null: false
      t.integer :release_year, null: false
      t.decimal :rating, precision: 3, scale: 1, null: false
      t.string :director, null: false
      t.integer :duration, null: false
      t.string :main_lead, null: false
      t.string :streaming_platform, null: false
      t.text :description, null: false
      t.boolean :premium, default: false, null: false
      t.timestamps
    end
  end
end