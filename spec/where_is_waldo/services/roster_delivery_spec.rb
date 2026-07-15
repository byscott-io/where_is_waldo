# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhereIsWaldo::RosterDelivery do
  let(:user)  { create(:user, name: "Ana") }
  let(:other) { create(:user, name: "Bo") }
  let(:org)   { RosterTestOrg.new(id: 1, members: User.where(id: [user.id, other.id])) }

  before do
    WhereIsWaldo::PresenceService.send(:reset_adapter!)
    WhereIsWaldo.config.presence_org = ->(_subject) { org }
    WhereIsWaldo.config.presence_visible_scope = ->(_viewer) { User.where(id: [user.id, other.id]) }
    WhereIsWaldo.config.subject_data_proc = ->(u) { { id: u.id, name: u.name } }
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  describe ".for" do
    it "raises on an unknown mode" do
      expect { described_class.for(:nope) }.to raise_error(ArgumentError)
    end
  end

  describe WhereIsWaldo::RosterDelivery::Pull do
    subject(:strategy) { described_class.new }

    let(:session) { "sess-1" }

    it "subscribe_plan returns a pull snapshot (no stream) and seeds the baseline" do
      create(:presence, subject: user, tab_visible: true, subject_active: true)

      plan = strategy.subscribe_plan(user, session)

      expect(plan[:streams]).to be_empty
      expect(plan[:messages].first).to include(type: "roster_snapshot", mode: "pull")
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

      WhereIsWaldo.config.presence_visible_scope = ->(_v) { User.where(id: user.id) }
      messages = strategy.poll_messages(user, session)

      removed = messages.find { |m| m[:member][:_removed] }
      expect(removed[:member][:id]).to eq(other.id)
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
