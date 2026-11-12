class CreateLtiRegistrations < ActiveRecord::Migration[8.0]
  def change
    create_table :lti_registrations do |t|
      t.references :lti_platform, null: false, foreign_key: true
      t.string :client_id, null: false
      t.text :public_key, null: false
      t.text :private_key, null: false
      t.string :kid, null: false

      t.timestamps
    end
    add_index :lti_registrations, [ :lti_platform_id, :client_id ], unique: true
  end
end
