# frozen_string_literal: true

class Exchange < ApplicationRecord
  # 招待トークンは URL に載る。総当たりで引き当てられない長さにする
  INVITE_TOKEN_BYTES = 16
  # 乱数シードは bigint に収める。Random.new_seed は 128bit あって入らない
  RANDOM_SEED_LIMIT = 2**62

  # フェーズは日時から導出する。状態カラムは持たない
  PHASES = [:preparing, :registration, :wish, :awaiting_matching, :published].freeze

  belongs_to :owner, class_name: 'User', inverse_of: :owned_exchanges

  has_many :participations, dependent: :destroy
  has_many :books, through: :participations

  # シードを差し替えると結果を作り直せてしまうため、作成後は動かせない。
  # 招待トークンは主催者が再発行するので readonly にしない
  attr_readonly :random_seed

  # NOT NULL のカラムは presence でも弾く。DB の例外ではなくフォームのエラーとして返すため
  validates :name, :invite_token, :random_seed,
            :registration_starts_at, :registration_ends_at, :wish_ends_at,
            presence: true

  validate :registration_period_order
  validate :wish_period_order

  after_initialize :assign_generated_attributes, if: :new_record?

  # 希望提出期間は登録期間の終了と同時に始まる。
  # カラムに分けると等値をバリデーションでしか守れず二重管理になるため、導出する
  def wish_starts_at
    registration_ends_at
  end

  # 基準時刻をキーワード引数で受け取り、境界の spec を時刻ちょうどで書けるようにする。
  # 各期間は開始時刻を含み、終了時刻を含まない。
  # 登録期間の終了と希望提出期間の開始は同時刻なので、両者の境目は1点になる
  def phase(at: Time.current)
    # 実行後に主催者が期間の日時を戻しても、公開済みであることは変わらない
    return :published if matched_at.present?

    return :preparing if at < registration_starts_at
    return :registration if at < registration_ends_at
    return :wish if at < wish_ends_at

    :awaiting_matching
  end

  def phase_name(at: Time.current)
    I18n.t(phase(at:), scope: 'exchange.phases')
  end

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
end
