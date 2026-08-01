# frozen_string_literal: true

class Exchange < ApplicationRecord
  # 招待トークンは URL に載る。総当たりで引き当てられない長さにする
  INVITE_TOKEN_BYTES = 16
  # 乱数シードは bigint に収める。Random.new_seed は 128bit あって入らない
  RANDOM_SEED_LIMIT = 2**62

  belongs_to :owner, class_name: 'User', inverse_of: :owned_exchanges

  has_many :participations, dependent: :destroy
  has_many :books, through: :participations

  # シードを差し替えると結果を作り直せてしまうため、作成後は動かせない。
  # 招待トークンは主催者が再発行するので readonly にしない
  attr_readonly :random_seed

  # NOT NULL のカラムは presence でも弾く。DB の例外ではなくフォームのエラーとして返すため
  validates :name, :invite_token, :random_seed,
            :registration_starts_at, :registration_ends_at, :wish_starts_at, :wish_ends_at,
            presence: true

  validate :registration_period_order
  validate :wish_period_order
  validate :periods_do_not_overlap

  after_initialize :assign_generated_attributes, if: :new_record?

  private

  # 招待トークンと乱数シードは交換会の作成時に発行する。
  # とくにシードは、マッチングの実行時に生成すると結果を作り直せてしまう
  def assign_generated_attributes
    self.invite_token ||= SecureRandom.urlsafe_base64(INVITE_TOKEN_BYTES)
    self.random_seed ||= SecureRandom.random_number(RANDOM_SEED_LIMIT)
  end

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
