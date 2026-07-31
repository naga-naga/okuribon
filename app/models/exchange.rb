# frozen_string_literal: true

class Exchange < ApplicationRecord
  belongs_to :owner, class_name: 'User', inverse_of: :owned_exchanges

  has_many :participations, dependent: :destroy
  has_many :books, through: :participations

  # NOT NULL のカラムは presence でも弾く。DB の例外ではなくフォームのエラーとして返すため
  validates :name, :invite_token, :random_seed,
            :registration_starts_at, :registration_ends_at, :wish_starts_at, :wish_ends_at,
            presence: true

  validate :registration_period_order
  validate :wish_period_order
  validate :periods_do_not_overlap

  private

  def registration_period_order
    return if registration_starts_at.blank? || registration_ends_at.blank?
    return if registration_starts_at < registration_ends_at

    errors.add(:registration_ends_at, :before_start)
  end

  def wish_period_order
    return if wish_starts_at.blank? || wish_ends_at.blank?
    return if wish_starts_at < wish_ends_at

    errors.add(:wish_ends_at, :before_start)
  end

  # 各期間は開始時刻を含み終了時刻を含まないため、境界が同時刻でも重ならない
  def periods_do_not_overlap
    return if registration_ends_at.blank? || wish_starts_at.blank?
    return if registration_ends_at <= wish_starts_at

    errors.add(:wish_starts_at, :overlaps_registration)
  end
end
