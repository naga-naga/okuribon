# frozen_string_literal: true

class User < ApplicationRecord
  has_many :owned_exchanges,
           class_name: 'Exchange', foreign_key: :owner_id,
           inverse_of: :owner, dependent: :restrict_with_error

  has_many :participations, dependent: :destroy

  # OAuth のコールバックで受け取った認証情報から利用者を引く。
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
