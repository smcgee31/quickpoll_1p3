class LtiUser < ApplicationRecord
  # lti1p1_user_id is required only when the user has a consumer. lti1p3_sub is required
  #     only when the user has a platform. The existing uniqueness rules stay.
  belongs_to :lti_consumer, optional: true
  belongs_to :lti_platform, optional: true
  has_many :votes, dependent: :destroy

  validates :lti1p1_user_id, presence: true, uniqueness: { scope: :lti_consumer_id }, if: -> { lti_consumer.present? }
  validates :lti1p3_sub, presence: true, if: -> { lti_platform.present? }
  validates :lti1p3_sub, uniqueness: { scope: :lti_platform_id }, allow_nil: true, if: -> { lti_platform.present? }

  validate :must_belong_to_consumer_or_platform

  private

  def must_belong_to_consumer_or_platform
    if lti_consumer.nil? && lti_platform.nil?
      errors.add(:base, "must belong to a consumer or a platform")
    end
  end
end
