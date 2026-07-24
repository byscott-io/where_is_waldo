# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhereIsWaldo::Broadcaster do
  let(:user) { create(:user) }
  let(:user2) { create(:user) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    WhereIsWaldo::PresenceService.send(:reset_adapter!)
  end

  describe ".broadcast_to" do
    context "with AR relation" do
      it "broadcasts to all subjects in scope" do
        described_class.broadcast_to(User.where(id: [user.id, user2.id]), :notification, { msg: "hi" })

        expect(ActionCable.server).to have_received(:broadcast)
          .with("where_is_waldo:subject:#{user.id}", hash_including(type: "notification"))
        expect(ActionCable.server).to have_received(:broadcast)
          .with("where_is_waldo:subject:#{user2.id}", hash_including(type: "notification"))
      end
    end

    context "with single record" do
      it "broadcasts to the subject" do
        described_class.broadcast_to(user, :alert, { level: "warning" })

        expect(ActionCable.server).to have_received(:broadcast)
          .with("where_is_waldo:subject:#{user.id}", hash_including(type: "alert"))
      end
    end

    context "with empty scope" do
      it "does not broadcast" do
        described_class.broadcast_to(User.none, :notification, {})
        expect(ActionCable.server).not_to have_received(:broadcast)
      end
    end

    it "includes message type in payload" do
      described_class.broadcast_to(user, :notification, { msg: "test" })

      expect(ActionCable.server).to have_received(:broadcast) do |_stream, message|
        expect(message[:type]).to eq("notification")
        expect(message[:data]).to eq({ msg: "test" })
      end
    end

    it "includes timestamp in payload" do
      freeze_time do
        described_class.broadcast_to(user, :notification, {})

        expect(ActionCable.server).to have_received(:broadcast) do |_stream, message|
          expect(message[:timestamp]).to eq(Time.current.iso8601)
        end
      end
    end
  end

  describe ".broadcast_to_online" do
    before do
      WhereIsWaldo.connect(session_id: "session-1", subject_id: user.id)
      # user2 is not online
    end

    it "only broadcasts to online subjects" do
      described_class.broadcast_to_online(User.all, :notification, { msg: "hi" })

      expect(ActionCable.server).to have_received(:broadcast)
        .with("where_is_waldo:subject:#{user.id}", anything)
      expect(ActionCable.server).not_to have_received(:broadcast)
        .with("where_is_waldo:subject:#{user2.id}", anything)
    end
  end

  describe ".broadcast_to_session" do
    let(:session_id) { "test-session-123" }

    before do
      WhereIsWaldo.connect(session_id: session_id, subject_id: user.id)
    end

    it "broadcasts with target session marker" do
      described_class.broadcast_to_session(session_id, user.id, :warning, { msg: "test" })

      expect(ActionCable.server).to have_received(:broadcast) do |_stream, message|
        expect(message[:_target_session]).to eq(session_id)
      end
    end

    it "returns true on success" do
      expect(described_class.broadcast_to_session(session_id, user.id, :warning, {})).to be true
    end

    it "returns false for nonexistent session" do
      expect(described_class.broadcast_to_session("nonexistent", user.id, :warning, {})).to be false
    end
  end
end
