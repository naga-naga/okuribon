# frozen_string_literal: true

class Exchange < ApplicationRecord
  belongs_to :owner, class_name: 'User', inverse_of: :owned_exchanges

  has_many :participations, dependent: :destroy
  has_many :books, through: :participations
end
