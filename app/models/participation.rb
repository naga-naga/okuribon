# frozen_string_literal: true

class Participation < ApplicationRecord
  belongs_to :exchange
  belongs_to :user

  has_many :books, dependent: :destroy
  has_many :wishes, dependent: :destroy
end
