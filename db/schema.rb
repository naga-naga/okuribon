# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_30_125443) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "exchanges", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "invite_token", null: false
    t.datetime "matched_at"
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.bigint "random_seed", null: false
    t.datetime "registration_ends_at", null: false
    t.datetime "registration_starts_at", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_url"
    t.datetime "wish_ends_at", null: false
    t.datetime "wish_starts_at", null: false
    t.index ["invite_token"], name: "index_exchanges_on_invite_token", unique: true
    t.index ["owner_id"], name: "index_exchanges_on_owner_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  add_foreign_key "exchanges", "users", column: "owner_id"
end
