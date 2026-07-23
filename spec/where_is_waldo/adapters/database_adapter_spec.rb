# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhereIsWaldo::Adapters::DatabaseAdapter do
  subject(:adapter) { described_class.new }

  let(:user) { create(:user) }
  let(:session_id) { "test-session-#{SecureRandom.hex(4)}" }

  describe "#connect" do
    it "creates a presence record" do
      expect do
        adapter.connect(session_id: session_id, subject_id: user.id)
      end.to change(WhereIsWaldo::Presence, :count).by(1)
    end

    it "returns true on success" do
      result = adapter.connect(session_id: session_id, subject_id: user.id)
      expect(result).to be true
    end

    it "sets default values" do
      adapter.connect(session_id: session_id, subject_id: user.id)
      presence = WhereIsWaldo::Presence.last

      expect(presence.tab_visible).to be true
      expect(presence.subject_active).to be true
      expect(presence.connected_at).to be_present
      expect(presence.last_heartbeat).to be_present
    end

    it "stores metadata" do
      adapter.connect(session_id: session_id, subject_id: user.id, metadata: { device: "mobile" })
      presence = WhereIsWaldo::Presence.last

      expect(presence.metadata).to eq({ "device" => "mobile" })
    end

    context "when session already exists" do
      before { adapter.connect(session_id: session_id, subject_id: user.id) }

      it "upserts the record" do
        expect do
          adapter.connect(session_id: session_id, subject_id: user.id, metadata: { new: true })
        end.not_to change(WhereIsWaldo::Presence, :count)
      end
    end
  end

  describe "#disconnect" do
    before { adapter.connect(session_id: session_id, subject_id: user.id) }

    context "by session_id" do
      it "removes the presence record" do
        expect do
          adapter.disconnect(session_id: session_id)
        end.to change(WhereIsWaldo::Presence, :count).by(-1)
      end

      it "returns true" do
        expect(adapter.disconnect(session_id: session_id)).to be true
      end
    end

    context "by subject_id" do
      let(:other_session) { "other-session-#{SecureRandom.hex(4)}" }

      before { adapter.connect(session_id: other_session, subject_id: user.id) }

      it "removes all presence records for the subject" do
        expect do
          adapter.disconnect(subject_id: user.id)
        end.to change(WhereIsWaldo::Presence, :count).by(-2)
      end
    end
  end

  describe "#heartbeat" do
    before { adapter.connect(session_id: session_id, subject_id: user.id) }

    it "updates last_heartbeat" do
      freeze_time do
        travel 1.minute
        adapter.heartbeat(session_id: session_id)
        presence = WhereIsWaldo::Presence.last
        expect(presence.last_heartbeat).to eq(Time.current)
      end
    end

    it "updates tab_visible" do
      adapter.heartbeat(session_id: session_id, tab_visible: false)
      presence = WhereIsWaldo::Presence.last
      expect(presence.tab_visible).to be false
    end

    it "updates subject_active" do
      adapter.heartbeat(session_id: session_id, subject_active: false)
      presence = WhereIsWaldo::Presence.last
      expect(presence.subject_active).to be false
    end

    it "updates last_activity when subject_active is true" do
      original_activity = WhereIsWaldo::Presence.last.last_activity
      travel 1.minute
      adapter.heartbeat(session_id: session_id, subject_active: true)
      presence = WhereIsWaldo::Presence.last
      expect(presence.last_activity).to be > original_activity
    end

    it "does not update last_activity when subject_active is false" do
      original_activity = WhereIsWaldo::Presence.last.last_activity
      travel 1.minute
      adapter.heartbeat(session_id: session_id, subject_active: false)
      presence = WhereIsWaldo::Presence.last
      expect(presence.last_activity).to eq(original_activity)
    end

    it "returns true on success" do
      expect(adapter.heartbeat(session_id: session_id)).to be true
    end

    it "returns false when session not found" do
      expect(adapter.heartbeat(session_id: "nonexistent")).to be false
    end
  end

  describe "#online_subject_ids" do
    let(:user2) { create(:user) }

    before do
      adapter.connect(session_id: "session-1", subject_id: user.id)
      adapter.connect(session_id: "session-2", subject_id: user2.id)
    end

    it "returns online subject IDs" do
      ids = adapter.online_subject_ids
      expect(ids).to contain_exactly(user.id, user2.id)
    end

    it "excludes stale sessions" do
      WhereIsWaldo::Presence.where(session_id: "session-2").update_all(last_heartbeat: 2.minutes.ago)
      ids = adapter.online_subject_ids
      expect(ids).to eq([user.id])
    end

    it "returns unique subject IDs" do
      adapter.connect(session_id: "session-3", subject_id: user.id)
      ids = adapter.online_subject_ids
      expect(ids.count(user.id)).to eq(1)
    end
  end

  describe "#sessions_for_subject" do
    before do
      adapter.connect(session_id: "session-1", subject_id: user.id, metadata: { device: "desktop" })
      adapter.connect(session_id: "session-2", subject_id: user.id, metadata: { device: "mobile" })
    end

    it "returns all sessions for the subject" do
      sessions = adapter.sessions_for_subject(user.id)
      expect(sessions.length).to eq(2)
    end

    it "returns session data as hashes" do
      sessions = adapter.sessions_for_subject(user.id)
      session = sessions.first

      expect(session).to include(
        :session_id,
        :subject_id,
        :connected_at,
        :tab_visible,
        :subject_active
      )
    end
  end

  describe "#sessions_for_subjects" do
    let(:user_a) { create(:user) }
    let(:user_b) { create(:user) }
    let(:user_c) { create(:user) }

    before do
      adapter.connect(session_id: "a-1", subject_id: user_a.id, metadata: { platform: "web" })
      adapter.connect(session_id: "a-2", subject_id: user_a.id, metadata: { platform: "mobile" })
      adapter.connect(session_id: "b-1", subject_id: user_b.id, metadata: { platform: "web" })
      # user_c intentionally has no session
    end

    it "groups the sessions by subject_id" do
      grouped = adapter.sessions_for_subjects([user_a.id, user_b.id, user_c.id])

      expect(grouped.keys).to contain_exactly(user_a.id, user_b.id)
      expect(grouped[user_a.id].length).to eq(2)
      expect(grouped[user_b.id].length).to eq(1)
    end

    it "omits subjects with no live sessions" do
      grouped = adapter.sessions_for_subjects([user_c.id])

      expect(grouped).to eq({})
    end

    it "returns each session in the same hash shape as #sessions_for_subject" do
      grouped = adapter.sessions_for_subjects([user_a.id])
      session = grouped[user_a.id].first

      expect(session).to include(:session_id, :subject_id, :tab_visible, :subject_active, :last_heartbeat, :metadata)
    end

    it "excludes sessions older than the timeout threshold" do
      stale_since = 2.hours.ago
      WhereIsWaldo::Presence.where(session_id: "a-1").update_all(last_heartbeat: stale_since)

      grouped = adapter.sessions_for_subjects([user_a.id], timeout: 60)

      expect(grouped[user_a.id].map { |s| s[:session_id] }).to contain_exactly("a-2")
    end

    it "returns an empty hash for empty input" do
      expect(adapter.sessions_for_subjects([])).to eq({})
      expect(adapter.sessions_for_subjects(nil)).to eq({})
    end

    it "issues the same number of queries for a big id list as a small one (no N+1)" do
      count = lambda do |ids|
        n = 0
        counter = ->(*, payload) { n += 1 unless payload[:name] == "SCHEMA" }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          adapter.sessions_for_subjects(ids)
        end
        n
      end

      small = count.call([user_a.id])
      big = count.call([user_a.id, user_b.id, user_c.id] + Array.new(20) { |i| 10_000 + i })

      expect(big).to eq(small)
    end
  end

  describe "#session_status" do
    before { adapter.connect(session_id: session_id, subject_id: user.id) }

    it "returns session status hash" do
      status = adapter.session_status(session_id)

      expect(status[:session_id]).to eq(session_id)
      expect(status[:subject_id]).to eq(user.id)
      expect(status[:tab_visible]).to be true
    end

    it "returns nil for nonexistent session" do
      expect(adapter.session_status("nonexistent")).to be_nil
    end
  end

  describe "#cleanup" do
    before do
      adapter.connect(session_id: "active", subject_id: user.id)
      adapter.connect(session_id: "stale", subject_id: create(:user).id)
      WhereIsWaldo::Presence.where(session_id: "stale").update_all(last_heartbeat: 2.minutes.ago)
    end

    it "removes stale records" do
      expect do
        adapter.cleanup
      end.to change(WhereIsWaldo::Presence, :count).by(-1)
    end

    it "keeps active records" do
      adapter.cleanup
      expect(WhereIsWaldo::Presence.find_by(session_id: "active")).to be_present
    end

    it "returns count of removed records" do
      expect(adapter.cleanup).to eq(1)
    end
  end
end
