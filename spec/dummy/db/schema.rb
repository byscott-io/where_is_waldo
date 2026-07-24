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

ActiveRecord::Schema[8.1].define(version: 2024_01_01_000000) do
  create_table "presences", force: :cascade do |t|
    t.datetime "connected_at", null: false
    t.datetime "created_at", null: false
    t.datetime "last_activity"
    t.datetime "last_heartbeat", null: false
    t.json "metadata"
    t.string "session_id", null: false
    t.boolean "subject_active", default: true, null: false
    t.boolean "tab_visible", default: true, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["last_heartbeat"], name: "index_presences_on_last_heartbeat"
    t.index ["user_id", "session_id"], name: "index_presences_on_user_id_and_session_id", unique: true
    t.index ["user_id"], name: "index_presences_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.datetime "updated_at", null: false
  end
end
