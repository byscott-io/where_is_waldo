# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhereIsWaldo::RosterChannel, type: :channel do
  let(:user) { create(:user) }
  let(:org) { RosterTestOrg.new(id: 7, members: User.where(id: user.id)) }

  before do
    WhereIsWaldo::PresenceService.send(:reset_adapter!)
    WhereIsWaldo.config.roster_org = ->(_subject) { org }
    WhereIsWaldo.config.subject_data_proc = ->(u) { { id: u.id, name: u.name } }

    stub_connection(waldo_subject_id: user.id, waldo_session_id: "sess-1")
  end

  context "when mode is :broadcast" do
    before { WhereIsWaldo.config.roster_mode = :broadcast }

    it "streams from the shared org roster stream" do
      subscribe

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("where_is_waldo:roster:RosterTestOrg:7")
    end

    it "transmits a broadcast-mode snapshot" do
      create(:presence, subject: user, tab_visible: true, subject_active: true,
                        metadata: { "platform" => "web" })

      subscribe

      snapshot = transmissions.last
      expect(snapshot["type"]).to eq("roster_snapshot")
      expect(snapshot["mode"]).to eq("broadcast")
      member = snapshot["members"].find { |m| m["id"] == user.id }
      expect(member).to include("status" => "active", "name" => user.name)
    end
  end

  context "when mode is :poll (default)" do
    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "does not stream (data rides the poll transmit)" do
      subscribe

      expect(subscription).to be_confirmed
      expect(subscription.streams).to be_empty
    end

    it "transmits a pull-mode snapshot with a poll interval" do
      create(:presence, subject: user, tab_visible: true, subject_active: true)

      subscribe

      snapshot = transmissions.last
      expect(snapshot["type"]).to eq("roster_snapshot")
      expect(snapshot["mode"]).to eq("poll")
      expect(snapshot["poll_interval"]).to eq(15)
    end

    it "returns a diff on #poll only for members whose state changed" do
      presence = create(:presence, subject: user, tab_visible: true, subject_active: true)
      subscribe # snapshot + baseline (user active)

      # No change -> poll transmits nothing new.
      before_size = transmissions.size
      perform :poll
      expect(transmissions.size).to eq(before_size)

      # active -> idle transition -> one delta.
      presence.update!(subject_active: false)
      perform :poll
      delta = transmissions.last
      expect(delta["type"]).to eq("roster_delta")
      expect(delta["member"]).to include("id" => user.id, "status" => "idle")
    end
  end

  it "rejects the subscription when the roster is not configured" do
    WhereIsWaldo.config.roster_org = nil

    subscribe

    expect(subscription).to be_rejected
  end
end
