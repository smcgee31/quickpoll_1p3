class CreateLtiLaunchStates < ActiveRecord::Migration[8.0]
  def change
    create_table :lti_launch_states do |t|
      t.references :lti_registration, null: false, foreign_key: true
      t.string :state, null: false
      t.string :nonce, null: false
      t.datetime :used_at

      t.timestamps
    end
    add_index :lti_launch_states, :state, unique: true
  end
end
