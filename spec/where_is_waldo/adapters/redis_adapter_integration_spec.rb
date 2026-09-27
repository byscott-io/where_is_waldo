# frozen_string_literal: true

require "rails_helper"
require "redis"

# The other RedisAdapter spec runs against MockRedis, which is a pure-Ruby fake
# with no protocol layer. That makes it blind to anything the wire format
# changes -- redis-rb 6 switched to RESP3 by default, which alters reply types
# for several commands this adapter depends on, and a mock cannot tell you
# whether that matters.
#
# So this file drives the adapter against a REAL server. It skips when none is
# reachable, so a contributor without Redis installed is not blocked; CI runs it
# against a service container on more than one redis-rb major.
#
# Point it elsewhere with WHERE_IS_WALDO_TEST_REDIS_URL.
RSpec.describe WhereIsWaldo::Adapters::RedisAdapter, :redis_integration do
  redis_url = ENV.fetch("WHERE_IS_WALDO_TEST_REDIS_URL", "redis://localhost:6379/15")

  available =
    begin
      Redis.new(url: redis_url, timeout: 1).ping == "PONG"
    rescue StandardError
      false
    end

  let(:client) { Redis.new(url: redis_url) }
  let(:user) { create(:user) }
  let(:session_id) { "session-abc" }
  let(:adapter) { described_class.new }

  before do
    skip("no Redis reachable at #{redis_url}") unless available

    client.flushdb
    WhereIsWaldo.configure do |config|
      config.adapter = :redis
      config.redis_client = client
      config.redis_prefix = "wiw_itest"
    end
  end

  after { client.flushdb if available }

  # Record which protocol we actually exercised. If this ever reports RESP2 on a
  # redis-rb 6 run, the rest of the file is not testing what it claims to.
  it "reports the protocol and gem under test" do
    protocol = client.call("HELLO").is_a?(Hash) ? "RESP3" : "RESP2"
    expect(protocol).to be_in(%w[RESP2 RESP3])
    RSpec.configuration.reporter.message(
      "  redis-rb #{Redis::VERSION} speaking #{protocol} against #{client.info["redis_version"]}"
    )
  end

  describe "#connect" do
    it "writes session data, the online set and the session set" do
      expect(adapter.connect(session_id: session_id, subject_id: user.id)).to be(true)

      data = JSON.parse(client.get("wiw_itest:session:#{user.id}:#{session_id}"))
      expect(data["subject_id"]).to eq(user.id)
      expect(client.smembers("wiw_itest:subject:#{user.id}:sessions")).to include(session_id)
      expect(client.zrangebyscore("wiw_itest:online_subjects", "-inf", "+inf")).to include(user.id.to_s)
    end

    it "applies a TTL to the session key" do
      adapter.connect(session_id: session_id, subject_id: user.id)
      expect(client.ttl("wiw_itest:session:#{user.id}:#{session_id}")).to be > 0
    end
  end

  # smembers is the command most exposed to RESP3: the protocol types a set
  # reply distinctly from an array, and this adapter feeds the result straight
  # into filter_map and all?.
  describe "#sessions_for_subject" do
    it "returns a session per connection" do
      adapter.connect(session_id: "s1", subject_id: user.id)
      adapter.connect(session_id: "s2", subject_id: user.id)

      sessions = adapter.sessions_for_subject(user.id)
      expect(sessions.pluck(:session_id)).to contain_exactly("s1", "s2")
      expect(sessions.first[:connected_at]).to be_a(ActiveSupport::TimeWithZone)
    end
  end

  describe "#online_subject_ids" do
    it "returns integer ids for live subjects" do
      adapter.connect(session_id: session_id, subject_id: user.id)
      expect(adapter.online_subject_ids).to eq([user.id])
    end

    it "excludes subjects past the timeout" do
      adapter.connect(session_id: session_id, subject_id: user.id)
      expect(adapter.online_subject_ids(timeout: -1)).to be_empty
    end
  end

  describe "#heartbeat" do
    it "updates the stored heartbeat and flags" do
      adapter.connect(session_id: session_id, subject_id: user.id)

      expect(
        adapter.heartbeat(session_id: session_id, subject_id: user.id, tab_visible: false, subject_active: false)
      ).to be(true)

      data = JSON.parse(client.get("wiw_itest:session:#{user.id}:#{session_id}"))
      expect(data["tab_visible"]).to be(false)
      expect(data["subject_active"]).to be(false)
    end

    it "returns false for a session that was never connected" do
      expect(adapter.heartbeat(session_id: "ghost", subject_id: user.id)).to be(false)
    end
  end

  describe "#session_status" do
    it "returns nil once disconnected" do
      adapter.connect(session_id: session_id, subject_id: user.id)
      expect(adapter.session_status(session_id, user.id)).not_to be_nil

      adapter.disconnect(session_id: session_id, subject_id: user.id)
      expect(adapter.session_status(session_id, user.id)).to be_nil
    end
  end

  describe "#disconnect" do
    it "leaves the subject online while another session remains" do
      adapter.connect(session_id: "s1", subject_id: user.id)
      adapter.connect(session_id: "s2", subject_id: user.id)

      adapter.disconnect(session_id: "s1", subject_id: user.id)

      expect(adapter.online_subject_ids).to eq([user.id])
      expect(client.scard("wiw_itest:subject:#{user.id}:sessions")).to eq(1)
    end

    it "drops the subject from the online set with the last session" do
      adapter.connect(session_id: "s1", subject_id: user.id)
      adapter.disconnect(session_id: "s1", subject_id: user.id)

      expect(adapter.online_subject_ids).to be_empty
      expect(client.scard("wiw_itest:subject:#{user.id}:sessions")).to eq(0)
    end

    it "removes every session when given only a subject" do
      adapter.connect(session_id: "s1", subject_id: user.id)
      adapter.connect(session_id: "s2", subject_id: user.id)

      adapter.disconnect(subject_id: user.id)

      expect(adapter.online_subject_ids).to be_empty
      expect(client.scard("wiw_itest:subject:#{user.id}:sessions")).to eq(0)
    end
  end

  describe "#sessions_for_subjects" do
    it "keys live sessions by subject and omits subjects with none" do
      other = create(:user)
      adapter.connect(session_id: "s1", subject_id: user.id)

      result = adapter.sessions_for_subjects([user.id, other.id])

      expect(result.keys).to eq([user.id])
      expect(result[user.id].first[:session_id]).to eq("s1")
    end
  end

  describe "#cleanup" do
    it "removes stale subjects and reports how many" do
      adapter.connect(session_id: session_id, subject_id: user.id)

      expect(adapter.cleanup(timeout: -1)).to eq(1)
      expect(adapter.online_subject_ids).to be_empty
    end

    it "keeps fresh subjects" do
      adapter.connect(session_id: session_id, subject_id: user.id)

      expect(adapter.cleanup).to eq(0)
      expect(adapter.online_subject_ids).to eq([user.id])
    end
  end
end
