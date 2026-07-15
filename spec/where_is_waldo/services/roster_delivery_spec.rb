# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhereIsWaldo::RosterDelivery do
  let(:user)  { create(:user, name: "Ana") }
  let(:other) { create(:user, name: "Bo") }
  let(:org)   { RosterTestOrg.new(id: 1, members: User.where(id: [user.id, other.id])) }

  before do
    WhereIsWaldo::PresenceService.send(:reset_adapter!)
    WhereIsWaldo.config.roster_org = ->(_subject) { org }
    WhereIsWaldo.config.roster_visible_to = ->(_viewer) { User.where(id: [user.id, other.id]) }
    WhereIsWaldo.config.subject_data_proc = ->(u) { { id: u.id, name: u.name } }
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  describe ".for" do
    it "raises on an unknown mode" do
      expect { described_class.for(:nope) }.to raise_error(ArgumentError)
    end
  end

  describe WhereIsWaldo::RosterDelivery::Poll do
    subject(:strategy) { described_class.new }

    let(:session) { "sess-1" }

    it "subscribe_plan returns a poll snapshot (no stream) and seeds the baseline" do
      create(:presence, subject: user, tab_visible: true, subject_active: true)

      plan = strategy.subscribe_plan(user, session)

      expect(plan[:streams]).to be_empty
      expect(plan[:messages].first).to include(type: "roster_snapshot", mode: "poll")
    end

    it "poll returns nothing when no visible member changed" do
      create(:presence, subject: user, tab_visible: true, subject_active: true)
      strategy.subscribe_plan(user, session) # baseline

      expect(strategy.poll_messages(user, session)).to eq([])
    end

    it "poll emits a delta when a member's state changes (active -> idle)" do
      presence = create(:presence, subject: user, tab_visible: true, subject_active: true)
      strategy.subscribe_plan(user, session)

      presence.update!(subject_active: false)
      messages = strategy.poll_messages(user, session)

      expect(messages.size).to eq(1)
      expect(messages.first[:member]).to include(id: user.id, status: "idle")
    end

    it "resyncs with a full snapshot when the baseline is missing/expired" do
      create(:presence, subject: user, tab_visible: true, subject_active: true)

      messages = strategy.poll_messages(user, session) # no prior baseline

      expect(messages.first).to include(type: "roster_snapshot")
    end

    it "emits a _removed delta when a member leaves the viewer's visible scope" do
      create(:presence, subject: user, tab_visible: true, subject_active: true)
      strategy.subscribe_plan(user, session) # baseline includes user + other

      WhereIsWaldo.config.roster_visible_to = ->(_v) { User.where(id: user.id) }
      messages = strategy.poll_messages(user, session)

      removed = messages.find { |m| m[:member][:_removed] }
      expect(removed[:member][:id]).to eq(other.id)
    end
  end

  describe WhereIsWaldo::RosterDelivery::Nudge do
    subject(:strategy) { described_class.new }

    it "subscribe_plan streams the account (for nudges) and sends a nudge-mode snapshot" do
      create(:presence, subject: user, tab_visible: true, subject_active: true)

      plan = strategy.subscribe_plan(user, "sess-1")

      expect(plan[:streams]).to eq(["where_is_waldo:roster:RosterTestOrg:1"])
      expect(plan[:messages].first).to include(mode: "nudge", nudge_jitter: 0.5)
    end

    it "poll returns a server-filtered diff just like poll" do
      presence = create(:presence, subject: user, tab_visible: true, subject_active: true)
      strategy.subscribe_plan(user, "sess-1")

      presence.update!(subject_active: false)
      messages = strategy.poll_messages(user, "sess-1")

      expect(messages.first[:member]).to include(id: user.id, status: "idle")
    end

    it "on_transition broadcasts a content-free nudge (no identity/state)" do
      allow(ActionCable.server).to receive(:broadcast)
      create(:presence, subject: user, tab_visible: true, subject_active: true)

      strategy.on_transition(user.id)

      expect(ActionCable.server).to have_received(:broadcast)
        .with("where_is_waldo:roster:RosterTestOrg:1", { type: "roster_nudge" })
    end
  end

  describe WhereIsWaldo::RosterDelivery::Fanout do
    subject(:strategy) { described_class.new }

    before do
      # Asymmetric visibility: `user` (a "manager") is visible only to itself;
      # `other` (a "report") is visible to both. So audience(user) = [user],
      # audience(other) = [user, other].
      WhereIsWaldo.config.roster_viewers_of = lambda do |subject|
        subject.id == user.id ? User.where(id: user.id) : User.where(id: [user.id, other.id])
      end
    end

    it "subscribe_plan streams the viewer's own stream and sends a fanout snapshot" do
      plan = strategy.subscribe_plan(user, "sess-1")

      expect(plan[:streams]).to eq(["where_is_waldo:roster:viewer:#{user.id}"])
      expect(plan[:messages].first).to include(mode: "fanout")
    end

    it "pushes a subject's delta to every viewer in its audience" do
      allow(ActionCable.server).to receive(:broadcast)
      create(:presence, subject: other, tab_visible: true, subject_active: true)

      strategy.on_transition(other.id) # audience(other) = [user, other]

      expect(ActionCable.server).to have_received(:broadcast)
        .with("where_is_waldo:roster:viewer:#{user.id}", hash_including(type: "roster_delta"))
      expect(ActionCable.server).to have_received(:broadcast)
        .with("where_is_waldo:roster:viewer:#{other.id}", hash_including(type: "roster_delta"))
    end

    it "does NOT push to viewers outside the audience (asymmetric visibility)" do
      allow(ActionCable.server).to receive(:broadcast)
      create(:presence, subject: user, tab_visible: true, subject_active: true)

      strategy.on_transition(user.id) # audience(user) = [user] only

      expect(ActionCable.server).to have_received(:broadcast)
        .with("where_is_waldo:roster:viewer:#{user.id}", anything)
      expect(ActionCable.server).not_to have_received(:broadcast)
        .with("where_is_waldo:roster:viewer:#{other.id}", anything)
    end
  end

  describe WhereIsWaldo::RosterDelivery::Broadcast do
    subject(:strategy) { described_class.new }

    it "subscribe_plan streams the account and sends a broadcast snapshot" do
      plan = strategy.subscribe_plan(user, "sess-1")

      expect(plan[:streams]).to eq(["where_is_waldo:roster:RosterTestOrg:1"])
      expect(plan[:messages].first).to include(mode: "broadcast")
    end

    it "on_transition broadcasts a delta to the account stream" do
      allow(ActionCable.server).to receive(:broadcast)
      create(:presence, subject: user, tab_visible: true, subject_active: true)

      strategy.on_transition(user.id)

      expect(ActionCable.server).to have_received(:broadcast)
        .with("where_is_waldo:roster:RosterTestOrg:1", hash_including(type: "roster_delta"))
    end
  end
end
