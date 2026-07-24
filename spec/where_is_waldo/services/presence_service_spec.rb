# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhereIsWaldo::PresenceService do
  let(:user) { create(:user) }
  let(:user2) { create(:user) }
  let(:session_id) { "test-session-#{SecureRandom.hex(4)}" }

  before do
    described_class.send(:reset_adapter!)
  end

  describe ".connect" do
    it "delegates to adapter" do
      expect do
        described_class.connect(session_id: session_id, subject_id: user.id)
      end.to change(WhereIsWaldo::Presence, :count).by(1)
    end
  end

  describe ".disconnect" do
    before { described_class.connect(session_id: session_id, subject_id: user.id) }

    it "removes presence" do
      expect do
        described_class.disconnect(session_id: session_id, subject_id: user.id)
      end.to change(WhereIsWaldo::Presence, :count).by(-1)
    end
  end

  describe ".heartbeat" do
    before { described_class.connect(session_id: session_id, subject_id: user.id) }

    it "updates heartbeat" do
      freeze_time do
        travel 1.minute
        described_class.heartbeat(session_id: session_id, subject_id: user.id)
        presence = WhereIsWaldo::Presence.last
        expect(presence.last_heartbeat).to eq(Time.current)
      end
    end
  end

  describe ".online" do
    before do
      described_class.connect(session_id: "session-1", subject_id: user.id)
      described_class.connect(session_id: "session-2", subject_id: user2.id)
    end

    it "returns AR relation of online subjects from scope" do
      result = described_class.online(User.all)
      expect(result).to contain_exactly(user, user2)
    end

    it "filters by the given scope" do
      result = described_class.online(User.where(id: user.id))
      expect(result).to contain_exactly(user)
    end

    it "returns chainable AR relation" do
      result = described_class.online(User.all)
      expect(result).to be_a(ActiveRecord::Relation)
    end
  end

  describe ".online_ids" do
    before do
      described_class.connect(session_id: "session-1", subject_id: user.id)
      described_class.connect(session_id: "session-2", subject_id: user2.id)
    end

    it "returns array of online subject IDs" do
      result = described_class.online_ids(User.all)
      expect(result).to contain_exactly(user.id, user2.id)
    end
  end

  describe ".all_online_ids" do
    before do
      described_class.connect(session_id: "session-1", subject_id: user.id)
      described_class.connect(session_id: "session-2", subject_id: user2.id)
    end

    it "returns all online subject IDs without scope" do
      result = described_class.all_online_ids
      expect(result).to contain_exactly(user.id, user2.id)
    end
  end

  describe ".sessions_for_subject" do
    before do
      described_class.connect(session_id: "session-1", subject_id: user.id)
      described_class.connect(session_id: "session-2", subject_id: user.id)
    end

    it "returns all sessions for a subject" do
      result = described_class.sessions_for_subject(user.id)
      expect(result.length).to eq(2)
    end
  end

  describe ".session_status" do
    before { described_class.connect(session_id: session_id, subject_id: user.id) }

    it "returns status for a session" do
      result = described_class.session_status(session_id, user.id)
      expect(result[:session_id]).to eq(session_id)
    end

    it "returns nil for nonexistent session" do
      expect(described_class.session_status("nonexistent", user.id)).to be_nil
    end
  end

  describe ".subject_online?" do
    context "when subject has active sessions" do
      before { described_class.connect(session_id: session_id, subject_id: user.id) }

      it "returns true" do
        expect(described_class.subject_online?(user.id)).to be true
      end
    end

    context "when subject has no sessions" do
      it "returns false" do
        expect(described_class.subject_online?(user.id)).to be false
      end
    end
  end

  describe ".cleanup" do
    before do
      described_class.connect(session_id: "active", subject_id: user.id)
      described_class.connect(session_id: "stale", subject_id: user2.id)
      WhereIsWaldo::Presence.where(session_id: "stale").update_all(last_heartbeat: 2.minutes.ago)
    end

    it "removes stale records" do
      expect do
        described_class.cleanup
      end.to change(WhereIsWaldo::Presence, :count).by(-1)
    end
  end
end
