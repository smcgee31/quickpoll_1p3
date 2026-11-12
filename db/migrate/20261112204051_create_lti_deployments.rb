class CreateLtiDeployments < ActiveRecord::Migration[8.0]
  def change
    create_table :lti_deployments do |t|
      t.references :lti_registration, null: false, foreign_key: true
      t.string :deployment_id, null: false

      t.timestamps
    end
    add_index :lti_deployments, [ :lti_registration_id, :deployment_id ], unique: true
  end
end
