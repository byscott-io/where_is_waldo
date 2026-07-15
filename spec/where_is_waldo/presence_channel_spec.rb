# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhereIsWaldo::PresenceChannel, type: :channel do
  let(:user) { create(:user) }
  let(:session_id) { "test-session-#{SecureRandom.hex(4)}" }

  before do
    WhereIsWaldo::PresenceService.send(:reset_adapter!)

    stub_connection(
      waldo_subject_id: user.id,
      waldo_session_id: session_id
    )
  end

  describe "#subscribed" do
    it "registers presence" do
      expect do
        subscribe
      end.to change(WhereIsWaldo::Presence, :count).by(1)
    end

    it "streams from subject channel" do
      subscribe
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("where_is_waldo:subject:#{user.id}")
    end

    it "stores metadata from params" do
      subscribe(metadata: { device: "mobile" })
      presence = WhereIsWaldo::Presence.last
      expect(presence.metadata).to eq({ "device" => "mobile" })
    end
  end

  describe "#unsubscribed" do
    before { subscribe }

    it "removes presence" do
      expect do
        subscription.unsubscribe_from_channel
      end.to change(WhereIsWaldo::Presence, :count).by(-1)
    end
  end

  describe "#heartbeat" do
    before { subscribe }

    it "updates presence heartbeat" do
      freeze_time do
        travel 1.minute
        perform :heartbeat, { tab_visible: true, subject_active: false }

        presence = WhereIsWaldo::Presence.last.reload
        expect(presence.last_heartbeat).to eq(Time.current)
        expect(presence.subject_active).to be false
      end
    end
  end

  describe "roster deltas (efficiency gate)" do
    let(:org) { RosterTestOrg.new(id: 3, members: User.where(id: user.id)) }
    let(:stream) { "where_is_waldo:roster:RosterTestOrg:3" }
    let(:deltas) { [] }

    before do
      WhereIsWaldo.config.presence_org = ->(_subject) { org }
      WhereIsWaldo.config.roster_mode = :broadcast # transitions only push in broadcast mode
      captured = deltas
      allow(ActionCable.server).to receive(:broadcast) do |target, message|
        captured << message if target == stream
      end
    end

    it "publishes a delta on connect" do
      subscribe

      expect(deltas.pluck(:type)).to include("roster_delta")
    end

    it "publishes on an activity transition but not on unchanged heartbeats" do
      subscribe # connect delta (active + visible)
      deltas.clear

      # No change (still active + visible) -> no new delta.
      perform :heartbeat, { tab_visible: true, subject_active: true }
      expect(deltas).to be_empty

      # active -> idle transition -> exactly one delta.
      perform :heartbeat, { tab_visible: true, subject_active: false }
      expect(deltas.size).to eq(1)
    end
  end
end
