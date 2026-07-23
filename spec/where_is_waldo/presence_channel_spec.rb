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

  describe "suppress_presence_proc" do
    context "when the proc returns truthy" do
      before do
        WhereIsWaldo.config.suppress_presence_proc = ->(_connection) { true }
      end

      after { WhereIsWaldo.config.suppress_presence_proc = nil }

      it "does not register a Presence row" do
        expect { subscribe }.not_to change(WhereIsWaldo::Presence, :count)
      end

      it "still confirms the subscription (the subscriber isn't rejected)" do
        subscribe

        expect(subscription).to be_confirmed
      end

      it "still streams from the subject channel so broadcasts reach the client" do
        subscribe

        expect(subscription).to have_stream_from("where_is_waldo:subject:#{user.id}")
      end

      it "delivers broadcasts to a suppressed subscriber the same as an active one" do
        # Prove the subscriber gets messages published via WhereIsWaldo's own
        # signaling — suppression is presence-only, NOT a mute.
        subscribe

        expect do
          ActionCable.server.broadcast("where_is_waldo:subject:#{user.id}",
                                       { type: "test_event", payload: { hello: "world" } })
        end.to have_broadcasted_to("where_is_waldo:subject:#{user.id}")
          .with(hash_including(type: "test_event"))
      end

      it "no-ops on heartbeat" do
        subscribe
        # Would blow up on `data.with_indifferent_access` if heartbeat kept
        # processing after suppression — the guard returns first.
        expect { perform :heartbeat, { tab_visible: true, subject_active: false } }
          .not_to change(WhereIsWaldo::Presence, :count)
      end

      it "no-ops on unsubscribe (nothing to disconnect from)" do
        subscribe

        expect(WhereIsWaldo::PresenceService).not_to receive(:disconnect)
        subscription.unsubscribe_from_channel
      end

      it "does not publish a roster delta on connect" do
        # Roster deltas are announced on presence transitions. A suppressed
        # subject never registered, so there's nothing to announce.
        org = RosterTestOrg.new(id: 42, members: User.where(id: user.id))
        WhereIsWaldo.config.roster_org = ->(_) { org }
        WhereIsWaldo.config.roster_mode = :broadcast
        stream = "where_is_waldo:roster:RosterTestOrg:42"

        broadcasts = []
        allow(ActionCable.server).to receive(:broadcast) do |target, message|
          broadcasts << message if target == stream
        end

        subscribe

        expect(broadcasts).to be_empty
      ensure
        WhereIsWaldo.config.roster_org = nil
      end
    end

    context "when the proc returns falsy" do
      before { WhereIsWaldo.config.suppress_presence_proc = ->(_connection) { false } }
      after  { WhereIsWaldo.config.suppress_presence_proc = nil }

      it "registers presence normally" do
        expect { subscribe }.to change(WhereIsWaldo::Presence, :count).by(1)
      end
    end

    context "when no proc is configured (default)" do
      it "registers presence normally" do
        expect(WhereIsWaldo.config.suppress_presence_proc).to be_nil
        expect { subscribe }.to change(WhereIsWaldo::Presence, :count).by(1)
      end
    end

    context "when the proc receives the connection" do
      it "passes the ActionCable connection so hosts can read session/cookies/env" do
        received = nil
        WhereIsWaldo.config.suppress_presence_proc = ->(conn) do
          received = conn
          false
        end

        subscribe

        # In the test harness the connection is ActionCable::Channel::ConnectionStub;
        # in production it's ActionCable::Connection::Base. Both expose the
        # ActionCable::Connection::Identification API host apps read from.
        expect(received).to respond_to(:identifiers)
      ensure
        WhereIsWaldo.config.suppress_presence_proc = nil
      end
    end
  end

  describe "roster deltas (efficiency gate)" do
    let(:org) { RosterTestOrg.new(id: 3, members: User.where(id: user.id)) }
    let(:stream) { "where_is_waldo:roster:RosterTestOrg:3" }
    let(:deltas) { [] }

    before do
      WhereIsWaldo.config.roster_org = ->(_subject) { org }
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
