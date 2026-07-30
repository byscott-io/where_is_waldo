# frozen_string_literal: true

require "rails_helper"

# Top-level convenience methods on the `WhereIsWaldo` module all delegate to
# `PresenceService`. These specs exist because 0.1.7 shipped with three of
# them written as `delegate :method, to: :PresenceService` (ActiveSupport),
# which generates the method body via `class_eval` with a string — a body
# whose `Module.nesting` is just the singleton class, without the outer
# `WhereIsWaldo`. Constant lookup for `PresenceService` inside such a body
# then can't find it and raises `uninitialized constant
# #<Class:WhereIsWaldo>::PresenceService` — silently broken for every host
# calling the top-level API, because Waldo's own internal code goes
# straight through `PresenceService` and never trips the delegate.
#
# Every method exposed on the module must therefore be exercised at the
# public boundary here, not just proxied to a lower-layer spec — that's the
# only way to catch a scope regression in the wrapper.
RSpec.describe WhereIsWaldo do
  let(:user) { create(:user) }
  let(:session_id) { "spec-#{SecureRandom.hex(4)}" }

  before { WhereIsWaldo::PresenceService.send(:reset_adapter!) }

  describe ".subject_online?" do
    it "returns true when the subject has a live session" do
      described_class.connect(session_id: session_id, subject_id: user.id)
      expect(described_class.subject_online?(user.id)).to be(true)
    end

    it "returns false when the subject has no live sessions" do
      expect(described_class.subject_online?(user.id)).to be(false)
    end
  end

  describe ".sessions_for_subject" do
    it "returns the session hashes for a live subject" do
      described_class.connect(session_id: session_id, subject_id: user.id)
      sessions = described_class.sessions_for_subject(user.id)
      expect(sessions.length).to eq(1)
      expect(sessions.first).to include(session_id: session_id, subject_id: user.id)
    end

    it "returns [] when the subject has no sessions" do
      expect(described_class.sessions_for_subject(user.id)).to eq([])
    end
  end

  describe ".session_status" do
    it "returns the session hash for a live (session_id, subject_id) pair" do
      described_class.connect(session_id: session_id, subject_id: user.id)
      status = described_class.session_status(session_id, user.id)
      expect(status).to include(session_id: session_id, subject_id: user.id)
    end

    it "returns nil for a nonexistent session" do
      expect(described_class.session_status("no-such-session", user.id)).to be_nil
    end
  end
end
