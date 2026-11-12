class CreateLtiPlatforms < ActiveRecord::Migration[8.0]
  def change
    create_table :lti_platforms do |t|
      t.string :issuer, null: false
      t.string :name, null: false
      t.string :auth_endpoint, null: false
      t.string :token_endpoint, null: false
      t.string :jwks_uri, null: false

      t.timestamps
    end
    add_index :lti_platforms, :issuer, unique: true
  end
end
