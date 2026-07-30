# frozen_string_literal: true

class User < ApplicationRecord
  has_many :owned_exchanges,
           class_name: 'Exchange', foreign_key: :owner_id,
           inverse_of: :owner, dependent: :restrict_with_error
end
