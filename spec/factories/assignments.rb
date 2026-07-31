# frozen_string_literal: true

FactoryBot.define do
  factory :assignment do
    book
    participation
    round { 1 }
    returned { false }
  end
end
