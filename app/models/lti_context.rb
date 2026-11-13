class LtiContext < ApplicationRecord
  belongs_to :lti_consumer, optional: true
  belongs_to :lti_platform, optional: true
  has_many :polls, dependent: :destroy

  validates :context_id, presence: true
  validates :context_id, uniqueness: { scope: :lti_consumer_id }, if: -> { lti_consumer.present? }
  validates :context_id, uniqueness: { scope: :lti_platform_id }, if: -> { lti_platform.present? }
  validate :must_belong_to_consumer_or_platform

  private

  def must_belong_to_consumer_or_platform
    if lti_consumer.nil? && lti_platform.nil?
      errors.add(:base, "must belong to a consumer or a platform")
    end
  end
end
