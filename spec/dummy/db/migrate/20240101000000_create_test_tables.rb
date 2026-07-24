# frozen_string_literal: true

class CreateTestTables < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.string :name
      t.string :email
      t.string :avatar_url
      t.timestamps
    end

    create_table :presences do |t|
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
end
