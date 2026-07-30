# frozen_string_literal: true

class Participation < ApplicationRecord
  belongs_to :exchange
  belongs_to :user
end
