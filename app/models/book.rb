# frozen_string_literal: true

class Book < ApplicationRecord
  belongs_to :participation
  has_one :exchange, through: :participation

  # 登録者。一覧のカードに名前を出すため、参加を経由せず引けるようにする。
  # 参加は交換会ごとに作られるので、本から見た利用者は必ず1人に定まる
  has_one :registrant, through: :participation, source: :user

  has_many :wishes, dependent: :destroy
  has_one :assignment, dependent: :destroy

  # DB のダンプやバックアップからギフトコードが漏れないようにする。
  # 決定的暗号化にすると同じコードが同じ暗号文になり、突き合わせるだけで一致が分かる。
  # 値で検索する用事も無いので、既定の非決定的暗号化のままにする
  encrypts :gift_code

  # ギフトコードが見えるのは「登録した本人（常時）」と「受け取った人（結果公開後）」の
  # 2者のみ。主催者に特権はない（docs/spec.md 8. 情報の可視性ルール）。
  # 伏せ字の出し分けと gift_code_for を同じ規則から引く。片方だけを直すと、
  # 開いても中身の出ないボタンが残る
  def gift_code_visible_to?(user, at:)
    return false if user.nil?

    registrant?(user) || recipient?(user, at:)
  end

  # 平文の取得経路はここだけ。素のリーダーは private にしてあるので、
  # 権限判定を迂回して読む道が無い。
  # 見えない相手には nil を返す。呼ぶ側それぞれに可視性の条件を書かせない
  def gift_code_for(user, at:)
    return nil unless gift_code_visible_to?(user, at:)

    gift_code
  end

  # 既定の出力からギフトコードを落とす。only: で名指しされても出さない。
  # 一覧を JSON で返す口が増えたときに、指定を書き忘れて漏れるのを防ぐ
  def serializable_hash(options = nil)
    super.except('gift_code')
  end

  private

  # 権限判定を通らない読み取りを外へ出さない。平文が要るのは gift_code_for だけなので、
  # 属性のリーダーを private で上書きする。
  # super でも同じだが、中身の無い定義に見えて rubocop に消される
  def gift_code
    read_attribute(:gift_code)
  end

  def registrant?(user)
    participation.user_id == user.id
  end

  # 返却は誰にも渡せなかった本が登録者へ戻ることなので、受け取りとして数えない
  def recipient?(user, at:)
    return false unless exchange.phase(at:) == :published
    return false if assignment.nil? || assignment.returned?

    assignment.participation.user_id == user.id
  end
end
