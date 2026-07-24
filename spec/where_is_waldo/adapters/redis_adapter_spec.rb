# frozen_string_literal: true

require "rails_helper"
require "mock_redis"

RSpec.describe WhereIsWaldo::Adapters::RedisAdapter do
  subject(:adapter) { described_class.new }

  let(:mock_redis) { MockRedis.new }
  let(:user) { create(:user) }
  let(:session_id) { "test-session-#{SecureRandom.hex(4)}" }

  before do
    WhereIsWaldo.configure do |config|
      config.adapter = :redis
      config.redis_client = mock_redis
    end
  end

  describe "#connect" do
    it "stores session data in Redis" do
      adapter.connect(session_id: session_id, subject_id: user.id)

      data = JSON.parse(mock_redis.get("where_is_waldo:session:#{user.id}:#{session_id}"))
      expect(data["session_id"]).to eq(session_id)
      expect(data["subject_id"]).to eq(user.id)
    end

    it "adds session to subject's sessions set" do
      adapter.connect(session_id: session_id, subject_id: user.id)

      sessions = mock_redis.smembers("where_is_waldo:subject:#{user.id}:sessions")
      expect(sessions).to include(session_id)
    end

    it "adds subject to online subjects sorted set" do
      adapter.connect(session_id: session_id, subject_id: user.id)

      subjects = mock_redis.zrange("where_is_waldo:online_subjects", 0, -1)
      expect(subjects).to include(user.id.to_s)
    end

    it "returns true on success" do
      result = adapter.connect(session_id: session_id, subject_id: user.id)
      expect(result).to be true
    end

    it "stores metadata" do
      adapter.connect(session_id: session_id, subject_id: user.id, metadata: { device: "mobile" })

      data = JSON.parse(mock_redis.get("where_is_waldo:session:#{user.id}:#{session_id}"))
      expect(data["metadata"]).to eq({ "device" => "mobile" })
    end
  end

  describe "#disconnect" do
    before { adapter.connect(session_id: session_id, subject_id: user.id) }

    context "by session_id (with subject_id)" do
      it "removes session data" do
        adapter.disconnect(session_id: session_id, subject_id: user.id)
        expect(mock_redis.get("where_is_waldo:session:#{user.id}:#{session_id}")).to be_nil
      end

      it "removes from subject's sessions set" do
        adapter.disconnect(session_id: session_id, subject_id: user.id)
        sessions = mock_redis.smembers("where_is_waldo:subject:#{user.id}:sessions")
        expect(sessions).not_to include(session_id)
      end

      it "removes subject from online set when no sessions remain" do
        adapter.disconnect(session_id: session_id, subject_id: user.id)
        subjects = mock_redis.zrange("where_is_waldo:online_subjects", 0, -1)
        expect(subjects).not_to include(user.id.to_s)
      end

      it "returns true" do
        expect(adapter.disconnect(session_id: session_id, subject_id: user.id)).to be true
      end

      it "raises when session_id is given without subject_id" do
        # Without subject_id, a caller-supplied session_id could reach into
        # another subject's row. Reject at the API boundary.
        expect { adapter.disconnect(session_id: session_id) }.to raise_error(ArgumentError)
      end
    end

    context "by subject_id" do
      let(:other_session) { "other-session-#{SecureRandom.hex(4)}" }

      before { adapter.connect(session_id: other_session, subject_id: user.id) }

      it "removes all sessions for the subject" do
        adapter.disconnect(subject_id: user.id)

        expect(mock_redis.get("where_is_waldo:session:#{user.id}:#{session_id}")).to be_nil
        expect(mock_redis.get("where_is_waldo:session:#{user.id}:#{other_session}")).to be_nil
      end
    end
  end

  describe "#heartbeat" do
    before { adapter.connect(session_id: session_id, subject_id: user.id) }

    it "updates last_heartbeat timestamp" do
      freeze_time do
        travel 1.minute
        adapter.heartbeat(session_id: session_id, subject_id: user.id)

        data = JSON.parse(mock_redis.get("where_is_waldo:session:#{user.id}:#{session_id}"))
        expect(data["last_heartbeat"]).to eq(Time.current.to_i)
      end
    end

    it "updates tab_visible" do
      adapter.heartbeat(session_id: session_id, subject_id: user.id, tab_visible: false)

      data = JSON.parse(mock_redis.get("where_is_waldo:session:#{user.id}:#{session_id}"))
      expect(data["tab_visible"]).to be false
    end

    it "returns true on success" do
      expect(adapter.heartbeat(session_id: session_id, subject_id: user.id)).to be true
    end

    it "returns false when session not found" do
      expect(adapter.heartbeat(session_id: "nonexistent", subject_id: user.id)).to be false
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

  describe "#sessions_for_subjects" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:user_a) { create(:user) }
    let(:user_b) { create(:user) }
    let(:user_c) { create(:user) }

    before do
      adapter.connect(session_id: "a-1", subject_id: user_a.id, metadata: { platform: "web" })
      adapter.connect(session_id: "a-2", subject_id: user_a.id, metadata: { platform: "mobile" })
      adapter.connect(session_id: "b-1", subject_id: user_b.id, metadata: { platform: "web" })
    end

    it "groups the sessions by subject_id" do
      grouped = adapter.sessions_for_subjects([user_a.id, user_b.id, user_c.id])

      expect(grouped.keys).to contain_exactly(user_a.id, user_b.id)
      expect(grouped[user_a.id].length).to eq(2)
      expect(grouped[user_b.id].length).to eq(1)
    end

    it "omits subjects with no live sessions" do
      expect(adapter.sessions_for_subjects([user_c.id])).to eq({})
    end

    it "returns each session in the same hash shape as #sessions_for_subject" do
      grouped = adapter.sessions_for_subjects([user_a.id])
      session = grouped[user_a.id].first

      expect(session).to include(:session_id, :subject_id, :tab_visible, :subject_active, :last_heartbeat, :metadata)
    end

    it "excludes sessions whose last_heartbeat is older than the timeout" do
      # Rewrite one session's timestamp directly in the stored JSON so it
      # looks stale — heartbeat() would refresh it.
      key = "where_is_waldo:session:#{user_a.id}:a-1"
      raw = JSON.parse(mock_redis.get(key))
      raw["last_heartbeat"] = 2.hours.ago.to_i
      mock_redis.set(key, raw.to_json)

      grouped = adapter.sessions_for_subjects([user_a.id], timeout: 60)

      expect(grouped[user_a.id].pluck(:session_id)).to contain_exactly("a-2")
    end

    it "returns an empty hash for empty input" do
      expect(adapter.sessions_for_subjects([])).to eq({})
      expect(adapter.sessions_for_subjects(nil)).to eq({})
    end
  end

  # If two authenticated subjects independently supplied the same
  # session_id, the pre-0.1.5 keyspace (`waldo:session:<sid>` global) let one
  # subject's connect overwrite the other's row. 0.1.5 namespaces the primary
  # key by subject_id so both rows coexist and no cross-subject clobber is
  # possible.
  describe "session-id collision isolation" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:user_a) { create(:user) }
    let(:user_b) { create(:user) }
    let(:shared) { "collision-session-id" }

    it "does not let one subject's connect overwrite another subject's row" do
      adapter.connect(session_id: shared, subject_id: user_a.id, metadata: { device: "a-tab" })
      adapter.connect(session_id: shared, subject_id: user_b.id, metadata: { device: "b-tab" })

      a_row = adapter.session_status(shared, user_a.id)
      b_row = adapter.session_status(shared, user_b.id)

      expect(a_row[:subject_id]).to eq(user_a.id)
      expect(a_row[:metadata]).to eq({ "device" => "a-tab" })
      expect(b_row[:subject_id]).to eq(user_b.id)
      expect(b_row[:metadata]).to eq({ "device" => "b-tab" })
    end

    it "heartbeats only the row for the given (subject, session) pair" do
      adapter.connect(session_id: shared, subject_id: user_a.id)
      adapter.connect(session_id: shared, subject_id: user_b.id)

      # heartbeat A with new metadata; B's row must be untouched
      adapter.heartbeat(session_id: shared, subject_id: user_a.id, metadata: { touched: "a" })

      a_row = adapter.session_status(shared, user_a.id)
      b_row = adapter.session_status(shared, user_b.id)
      expect(a_row[:metadata]).to include("touched" => "a")
      expect(b_row[:metadata]).not_to include("touched")
    end

    it "disconnects only the specified subject's session" do
      adapter.connect(session_id: shared, subject_id: user_a.id)
      adapter.connect(session_id: shared, subject_id: user_b.id)

      adapter.disconnect(session_id: shared, subject_id: user_a.id)

      expect(adapter.session_status(shared, user_a.id)).to be_nil
      expect(adapter.session_status(shared, user_b.id)).not_to be_nil
    end
  end

  describe "#session_status" do
    before { adapter.connect(session_id: session_id, subject_id: user.id) }

    it "returns session status hash" do
      status = adapter.session_status(session_id, user.id)

      expect(status[:session_id]).to eq(session_id)
      expect(status[:subject_id]).to eq(user.id)
      expect(status[:tab_visible]).to be true
    end

    it "returns nil for nonexistent session" do
      expect(adapter.session_status("nonexistent", user.id)).to be_nil
    end
  end
end
