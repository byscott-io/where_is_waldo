# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :name
    t.string :email
    t.string :avatar_url
    t.timestamps
  end

  create_table :presences, force: true do |t|
    t.string :session_id, null: false
    t.bigint :user_id, null: false
    t.datetime :connected_at, null: false
    t.datetime :last_heartbeat, null: false
    t.datetime :last_activity
    t.boolean :tab_visible, default: true, null: false
    t.boolean :subject_active, default: true, null: false
    t.json :metadata
    t.timestamps
  end

  add_index :presences, [:user_id, :session_id], unique: true
  add_index :presences, :user_id
  add_index :presences, :last_heartbeat
end
