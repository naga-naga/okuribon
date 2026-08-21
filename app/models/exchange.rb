# frozen_string_literal: true

class Exchange < ApplicationRecord
  # 招待トークンは URL に載る。総当たりで引き当てられない長さにする
  INVITE_TOKEN_BYTES = 16
  # 乱数シードは bigint に収める。Random.new_seed は 128bit あって入らない
  RANDOM_SEED_LIMIT = 2**62

  PHASES = [:preparing, :registration, :wish, :awaiting_matching, :published].freeze

  # #phase が読む日時のすべて。通知はこの時刻を予約して確かめに行くので、
  # #phase が読む日時を増やしたらここにも足す。
  # 足し忘れると、そのフェーズへの変わり目だけ通知が来ない。
  # マッチング実行日時が入っているのは、結果公開だけが日時では決まらないため
  PHASE_BOUNDARIES = [
    :registration_starts_at, :registration_ends_at, :wish_ends_at, :matched_at,
  ].freeze

  # #next_deadline が返す日時のうち、締切にあたるものだけを並べる。
  # 登録期間の開始が入っていないのは、待っているのが締切ではなく
  # 開始で、まだ促す行動が無いため（Notifications::DeadlineReminder::REMINDABLE_PHASES）。
  # 何時間前に知らせるかはリマインドの都合なので、ここには持たない
  REMINDER_DEADLINES = [:registration_ends_at, :wish_ends_at].freeze

  # 結果公開はどの操作も許さないため、値のどこにも現れない
  WRITABLE_PHASES = {
    participation: [:preparing, :registration],
    book: [:registration],
    wish: [:wish],
    matching: [:awaiting_matching],
  }.freeze

  # 段はフェーズと1対1ではない。マッチング実行待ちに当たる段は無く、
  # 希望提出が終わって結果公開を待っている状態にあたる
  SCHEDULE_STEPS = { registration: 0, wish: 1, published: 2 }.freeze

  # 招待画面の日程（SCHEDULE_STEPS）と違って結果公開を含まないのは、
  # あれが主催者の実行で起きて日時では決まらないため。動かせる期間だけを並べる
  PERIODS = [:registration, :wish].freeze

  # 準備中はまだ1段目も始まっていないので、登録期間と同じ位置に置く。
  # 進行中かどうかは位置ではなくフェーズ名の一致で見るため、
  # 同じ位置に2つ並べても取り違えない
  SCHEDULE_PHASE_POSITIONS = {
    preparing: 0, registration: 0, wish: 1, awaiting_matching: 2, published: 2,
  }.freeze

  # 応答の組み立ては ApplicationController の rescue_from に集約する。
  # 交換会を持たせるのは、拒否の画面が戻り先を出すため。コントローラの
  # インスタンス変数から拾うと、変数を置き忘れたアクションだけ戻り先を出せなくなる
  class PhaseViolation < StandardError
    attr_reader :exchange

    def initialize(exchange, operation, at:)
      @exchange = exchange

      super(I18n.t('exchange.phase_violation',
                   phase: exchange.phase_name(at:),
                   operation: I18n.t(operation, scope: 'exchange.operations')))
    end
  end

  # 辞退でも主催者による参加者の除外でも理由は同じ
  # 「主催者は必ず参加者を兼ねる」なので、操作ごとに例外を分けない。
  # 応答の組み立ては ApplicationController の rescue_from に集約する
  class OwnerLocked < StandardError
    attr_reader :exchange

    def initialize(exchange)
      @exchange = exchange

      super(I18n.t('exchange.owner_locked'))
    end
  end

  # 発行の規則を作成時と再発行で1つにする。別々に書くと、
  # 長さを見直したときに片方だけ短いトークンが出続ける
  def self.generate_invite_token
    SecureRandom.urlsafe_base64(INVITE_TOKEN_BYTES)
  end

  belongs_to :owner, class_name: 'User', inverse_of: :owned_exchanges

  has_many :participations, dependent: :destroy
  has_many :books, through: :participations

  # シードを差し替えると結果を作り直せてしまうため、作成後は動かせない。
  # 招待トークンは主催者が再発行するので readonly にしない
  attr_readonly :random_seed

  validates :name, :invite_token, :random_seed,
            :registration_starts_at, :registration_ends_at, :wish_ends_at,
            presence: true

  validate :registration_period_order
  validate :wish_period_order

  after_initialize :assign_generated_attributes, if: :new_record?

  # フェーズの変わり目に通知するため、切り替わる時刻を予約する。
  # 日時を書き込む経路は作成と編集の2つあるが、どちらも保存を通るのでここに集める。
  # 経路ごとに積むと、あとから足された経路だけ通知が来ない状態に気付けない。
  # commit のあとに積むのは、巻き戻った日時の予約を残さないため
  after_commit :reserve_phase_notifications, if: :saved_change_to_phase_boundaries?

  # 締切の前に知らせるため、締切を持つ日時も予約する。フェーズの変わり目の予約と分けるのは、
  # 予約する時刻が締切そのものではなく、そこから窓の分だけ手前になるため。
  # 1つのコールバックにまとめると、どちらの都合で引き算しているのかが読めなくなる
  after_commit :reserve_deadline_reminders, if: :saved_change_to_reminder_deadlines?

  # カラムに分けると等値をバリデーションでしか守れず二重管理になるため、導出する
  def wish_starts_at
    registration_ends_at
  end

  def phase(at:)
    # 実行後に主催者が期間の日時を戻しても、公開済みであることは変わらない
    return :published if matched_at.present?

    return :preparing if at < registration_starts_at
    return :registration if at < registration_ends_at
    return :wish if at < wish_ends_at

    :awaiting_matching
  end

  # ギフトコードの可視性も結果画面の可否もここに乗る。
  # フェーズ名との比較を呼ぶ側それぞれに書かせない。綴り間違いは黙って false になり、
  # 見えてはいけないものが見える側に倒れる
  def published?(at:)
    phase(at:) == :published
  end

  # 未ログインの人も着地画面を見るため、利用者がいない場合も答える。
  # 呼ぶ側それぞれに nil の判定を書かせない
  def participant?(user)
    return false if user.nil?

    participations.exists?(user:)
  end

  # 見せてよいフェーズかどうかは呼ぶ側が決める。
  # 成立を先に、返却を最後に置く。混ぜると、成立した冊数を読む側が数え直すことになる。
  # sort_by は同じ値どうしの順序を保証しないため、分けてから連結する
  def result_books
    ordered = books.includes(:registrant, assignment: { participation: :user })
                   .order(:participation_id, :id).to_a

    matched, returned = ordered.partition { it.assignment.nil? || !it.assignment.returned? }
    matched + returned
  end

  # 抽選順はマッチングを実行して初めて決まるので、
  # 実行前は空になる（Matching::Execution#save_draft_order）
  def draft_order
    participations.where.not(draft_position: nil).order(:draft_position).includes(:user)
  end

  # 未ログインの人も着地画面を見るため、participant? と同じく nil に答える
  def owner?(user)
    return false if user.nil?

    owner_id == user.id
  end

  # ボタンの出し分けと remove_participant! の拒否を同じ規則から引く。
  # 片方だけを直すと、押しても断られるボタンが残る
  def removable_participant?(user, at:)
    participant?(user) && !owner?(user) && writable?(:participation, at:)
  end

  # 確認画面を開けるかどうかと、交換会ページに実行への導線を出すかどうかを
  # 同じ規則から引く。片方だけを直すと、押しても断られる導線が残る。
  # 実行そのものの検証は Matching::Execution が行ロックの内側で持つので、これは
  # 見せてよいかの判定にあたる。
  # 実行済みで false になるのは phase が :published を返すため。
  # matched_at を直に見ない
  def matching_executable?(user, at:)
    owner?(user) && writable?(:matching, at:)
  end

  def phase_name(at:)
    I18n.t(phase(at:), scope: 'exchange.phases')
  end

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

  # 準備中に待っているのは締切ではなく開始で、一律に「締切」と出すと、
  # まだ始まってもいない登録がもう終わるように読める
  def next_deadline_name(at:)
    I18n.t(phase(at:), scope: 'exchange.next_deadlines', default: nil)
  end

  # 段の名前と日時カラムの対応をここだけに置く。
  # 結果公開が返すのは希望提出の締切で、公開そのものは主催者がマッチングを
  # 実行したときに起きる。日時では決まらないので、これは下限にあたる。
  # fetch で落として、綴り間違いを黙って nil に化けさせない
  def schedule_starts_at(step)
    {
      registration: registration_starts_at,
      wish: wish_starts_at,
      published: wish_ends_at,
    }.fetch(step)
  end

  # 段の名前と日時カラムの対応を schedule_starts_at と同じくここに集める。
  # 終端を含まない範囲にするのは、各期間が終了時刻を含まないため。
  # fetch で落として、綴り間違いを黙って nil に化けさせない
  def period(step)
    {
      registration: registration_starts_at...registration_ends_at,
      wish: wish_starts_at...wish_ends_at,
    }.fetch(step)
  end

  # フェーズをそのまま並べられないのは、マッチング実行待ちに当たる段が無いため。
  # 位置で数え、進行中だけは名前の一致で見る
  def schedule_state(step, at:)
    position = SCHEDULE_STEPS.fetch(step)
    current = phase(at:)

    return :current if step == current

    position < SCHEDULE_PHASE_POSITIONS.fetch(current) ? :done : :upcoming
  end

  # 参加の入口は、招待画面のフォームと、ログインを終えて戻ってきた経路の2つある。
  # どちらから来ても同じ検証を通すため、フェーズの判定はコントローラに置かずここへ集める。
  # 二重参加は一意インデックスに任せる。先に exists? で調べても、
  # その隙に入られると防げない
  def join!(user, at:)
    raise PhaseViolation.new(self, :participation, at:) unless writable?(:participation, at:)

    participations.create_or_find_by!(user:)
  end

  # 入口は本人の辞退と主催者による除外の2つあるが、通す検証は同じなので、
  # 経路ごとに分けずここへ集める。片方にだけ条件を書き足すと、辞退では
  # 断られるものが除外では通る。
  # 参加と同じ操作名で表を引くため、抜けられる期間は参加できる期間と必ず一致する。
  # 別々に書くと、希望提出期間に入ってから抜けられて取得枠の計算が壊れる。
  # 登録した本は参加にぶら下がっているので、参加を消せば一緒に消える。
  # 参加が無ければ何もしない。二重送信や再送信で落とすようなことではない
  def remove_participant!(user, at:)
    # 役割をフェーズより先に見る。主催者が抜けられないのは期間によらないため、
    # 順を逆にすると締切後に押したときだけ理由が入れ替わる
    raise OwnerLocked, self if owner?(user)
    raise PhaseViolation.new(self, :participation, at:) unless writable?(:participation, at:)

    participations.find_by(user:)&.destroy!
  end

  # 参加は user と交換会で結ばれていて招待トークンを持たないので、
  # 差し替えても既存の参加者は影響を受けない。古いURLは引けなくなり 404 になる。
  # フェーズでは閉じない。締切後に配り直しても、参加を断るのは着地画面の仕事
  def reissue_invite_token!
    update!(invite_token: self.class.generate_invite_token)
  end

  # 書き込みを許すかどうかの判定はここだけに置く。
  # 各コントローラがフェーズを直接見て条件を手書きすると、コントローラごとに食い違うため。
  # 表に無い操作名は fetch が落とす。綴り間違いを黙って可否に化けさせない
  def writable?(operation, at:)
    WRITABLE_PHASES.fetch(operation).include?(phase(at:))
  end

  private

  def saved_change_to_phase_boundaries?
    changed_phase_boundaries.any?
  end

  def reserve_phase_notifications
    Notifications::NotifyPhaseChangeJob.reserve(self, at: changed_phase_boundaries)
  end

  def changed_phase_boundaries
    changed_datetimes(PHASE_BOUNDARIES)
  end

  def saved_change_to_reminder_deadlines?
    changed_reminder_deadlines.any?
  end

  def reserve_deadline_reminders
    Notifications::RemindDeadlineJob.reserve(self, deadlines: changed_reminder_deadlines)
  end

  def changed_reminder_deadlines
    changed_datetimes(REMINDER_DEADLINES)
  end

  # 動いた日時だけを返す。全部を渡すと、日時を1つ動かすたびに
  # 動かしていないものの予約まで増える
  def changed_datetimes(columns)
    columns.filter_map { self[it] if saved_change_to_attribute?(it) }
  end

  # シードをマッチングの実行時に生成すると、結果を作り直せてしまう
  def assign_generated_attributes
    self.invite_token ||= self.class.generate_invite_token
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
