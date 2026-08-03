# frozen_string_literal: true

class Exchange < ApplicationRecord
  # 招待トークンは URL に載る。総当たりで引き当てられない長さにする
  INVITE_TOKEN_BYTES = 16
  # 乱数シードは bigint に収める。Random.new_seed は 128bit あって入らない
  RANDOM_SEED_LIMIT = 2**62

  # フェーズは日時から導出する。状態カラムは持たない
  PHASES = [:preparing, :registration, :wish, :awaiting_matching, :published].freeze

  # 操作ごとに書き込みを許すフェーズ。spec.md 4. フェーズの表と補足に対応する。
  # 結果公開はどの操作も許さないため、値のどこにも現れない
  WRITABLE_PHASES = {
    participation: [:preparing, :registration],
    book: [:registration],
    wish: [:wish],
    matching: [:awaiting_matching],
  }.freeze

  # フェーズが許さない書き込みを拒否するときに投げる。
  # 応答の組み立ては ApplicationController の rescue_from に集約する
  class PhaseViolation < StandardError
    def initialize(exchange, operation, at:)
      super(I18n.t('exchange.phase_violation',
                   phase: exchange.phase_name(at:),
                   operation: I18n.t(operation, scope: 'exchange.operations')))
    end
  end

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

  # 基準時刻は必須にする。既定値を置くと呼ぶたびに現在時刻が進み、締切をまたいだ
  # 瞬間に1つの画面の中でフェーズが食い違う。現在時刻は入口で1回だけ読んで回す。
  # 各期間は開始時刻を含み、終了時刻を含まない。
  # 登録期間の終了と希望提出期間の開始は同時刻なので、両者の境目は1点になる
  def phase(at:)
    # 実行後に主催者が期間の日時を戻しても、公開済みであることは変わらない
    return :published if matched_at.present?

    return :preparing if at < registration_starts_at
    return :registration if at < registration_ends_at
    return :wish if at < wish_ends_at

    :awaiting_matching
  end

  # 未ログインの人も着地画面を見るため、利用者がいない場合も答える。
  # 呼ぶ側それぞれに nil の判定を書かせない
  def participant?(user)
    return false if user.nil?

    participations.exists?(user:)
  end

  def phase_name(at:)
    I18n.t(phase(at:), scope: 'exchange.phases')
  end

  # 次に来る節目。「いつまでに何をするか」を出すために使う。
  # マッチング実行待ちが待っているのは主催者の操作で日時では動かず、
  # 結果公開はもう終わっている。どちらも待つべき日時が無いので nil を返し、
  # 呼ぶ側に締切を出させない
  def next_deadline(at:)
    case phase(at:)
    when :preparing then registration_starts_at
    when :registration then registration_ends_at
    when :wish then wish_ends_at
    end
  end

  # 節目の呼び名はフェーズごとに変わる。準備中に待っているのは締切ではなく開始で、
  # 一律に「締切」と出すと、まだ始まってもいない登録がもう終わるように読める
  def next_deadline_name(at:)
    I18n.t(phase(at:), scope: 'exchange.next_deadlines', default: nil)
  end

  # 参加の入口は、招待画面のフォームと、ログインを終えて戻ってきた経路の2つある。
  # どちらから来ても同じ検証を通すため、フェーズの判定はコントローラに置かずここへ集める。
  # 二重参加は一意インデックスに任せる。先に exists? で調べても、
  # その隙に入られると防げない
  def join!(user, at:)
    raise PhaseViolation.new(self, :participation, at:) unless writable?(:participation, at:)

    participations.create_or_find_by!(user:)
  end

  # 辞退。参加と同じ操作名で表を引くため、抜けられる期間は参加できる期間と必ず一致する。
  # 別々に書くと、希望提出期間に入ってから抜けられて取得枠の計算が壊れる。
  # 登録した本は参加にぶら下がっているので、参加を消せば一緒に消える。
  # 参加が無ければ何もしない。二重送信や再送信で落とすようなことではない
  def withdraw!(user, at:)
    raise PhaseViolation.new(self, :participation, at:) unless writable?(:participation, at:)

    participations.find_by(user:)&.destroy!
  end

  # 書き込みを許すかどうかの判定はここだけに置く。
  # 各コントローラがフェーズを直接見て条件を手書きすると、口ごとに食い違うため。
  # 表に無い操作名は fetch が落とす。綴り間違いを黙って可否に化けさせない
  def writable?(operation, at:)
    WRITABLE_PHASES.fetch(operation).include?(phase(at:))
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
