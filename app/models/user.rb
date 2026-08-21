# frozen_string_literal: true

class User < ApplicationRecord
  has_many :owned_exchanges,
           class_name: 'Exchange', foreign_key: :owner_id,
           inverse_of: :owner, dependent: :restrict_with_error

  has_many :participations, dependent: :destroy

  # 一覧に並ぶのは参加した交換会だけ。主催者は必ず参加者を兼ねるので、
  # 主催した交換会もここから引ける。主催であることは条件にしない
  has_many :exchanges, through: :participations

  # プロバイダと uid は OmniAuth から、表示名は初回だけプロバイダの名前を借りて入る。
  # 名前を返さないプロバイダを足したときに、ログインの経路で 500 になるのを防ぐ
  validates :provider, :uid, :display_name, presence: true

  # 表示名は本人が変えられるため、初回の初期値としてだけプロバイダの名前を借りる。
  # アバターはプロバイダが返す URL をそのまま持つので、ログインのたびに追従する
  def self.from_omniauth(auth)
    user = find_or_initialize_by(provider: auth.provider, uid: auth.uid)
    user.display_name = auth.info.name if user.new_record?
    user.avatar_url = auth.info.image
    user.save!
    user
  end
end
