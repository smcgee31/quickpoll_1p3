class AddLtiPlatformToLtiUsersAndLtiContexts < ActiveRecord::Migration[8.0]
  def change
    add_reference :lti_users, :lti_platform, foreign_key: true
    add_reference :lti_contexts, :lti_platform, foreign_key: true

    change_column_null :lti_users, :lti_consumer_id, true
    change_column_null :lti_contexts, :lti_consumer_id, true
    change_column_null :lti_users, :lti1p1_user_id, true
    add_index :lti_users, [ :lti_platform_id, :lti1p3_sub ], unique: true, where: "lti1p3_sub IS NOT NULL"
    add_index :lti_contexts, [ :lti_platform_id, :context_id ], unique: true, where: "context_id IS NOT NULL"
  end
end
