# frozen_string_literal: true

class Book < ApplicationRecord
  belongs_to :participation
  has_one :exchange, through: :participation

  has_many :wishes, dependent: :destroy
  has_one :assignment, dependent: :destroy
end
