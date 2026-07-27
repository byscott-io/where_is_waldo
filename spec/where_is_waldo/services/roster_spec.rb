# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhereIsWaldo::Roster do
  let(:org) { RosterTestOrg.new(id: 1, members: User.where(id: member_ids)) }
  let(:member_ids) { [] }

  before do
    WhereIsWaldo::PresenceService.send(:reset_adapter!)
    WhereIsWaldo.config.roster_org = ->(_subject) { org }
    WhereIsWaldo.config.subject_data_proc = ->(u) { { id: u.id, name: u.name } }
  end

  # Build a live session for a user.
  def session(user, tab_visible:, subject_active:, platform: "web", last_activity: Time.current)
    create(:presence, subject: user, tab_visible: tab_visible, subject_active: subject_active,
                      last_activity: last_activity, metadata: { "platform" => platform })
  end

  describe ".state_for" do
    it "rolls up the highest activity across devices and reports per-device status" do
      user = create(:user)
      session(user, tab_visible: true, subject_active: false, platform: "web")   # web idle
      session(user, tab_visible: true, subject_active: true, platform: "mobile") # mobile active

      state = described_class.state_for(user.id)

      expect(state[:status]).to eq("active") # highest across devices
      expect(state[:devices]).to eq("web" => "idle", "mobile" => "active")
    end

    it "reports background when only hidden/backgrounded sessions are live" do
      user = create(:user)
      session(user, tab_visible: false, subject_active: true, platform: "web")

      expect(described_class.state_for(user.id)[:status]).to eq("background")
    end

    it "reports offline (no devices, no last_activity) when no session is within the timeout" do
      user = create(:user)
      create(:presence, :stale, subject: user)

      expect(described_class.state_for(user.id)).to eq(status: "offline", devices: {}, last_activity: nil)
    end

    # last_activity in the payload lets the client subtract from Date.now() and
    # derive seconds-idle at any time — hosts can apply their own thresholds
    # without needing the gem to broadcast on every heartbeat.
    describe "last_activity" do
      it "is the max last_activity across all of the subject's live sessions (ISO8601)" do
        user = create(:user)
        session(user, tab_visible: true, subject_active: true, platform: "web",
                      last_activity: 3.minutes.ago)
        session(user, tab_visible: true, subject_active: false, platform: "mobile",
                      last_activity: 30.seconds.ago)

        result = described_class.state_for(user.id)[:last_activity]

        expect(Time.iso8601(result)).to be_within(2.seconds).of(30.seconds.ago)
      end

      it "is nil when the subject has no live sessions" do
        user = create(:user)
        expect(described_class.state_for(user.id)[:last_activity]).to be_nil
      end

      it "normalizes to an ISO8601 string regardless of adapter shape" do
        user = create(:user)
        redis_time = Time.zone.parse("2026-07-27T15:00:00Z")
        allow(WhereIsWaldo::PresenceService).to receive(:sessions_for_subjects).and_return(
          user.id => [{ session_id: "s1", subject_id: user.id, tab_visible: true,
                        subject_active: true, last_activity: redis_time,
                        metadata: { "platform" => "web" } }]
        )

        expect(described_class.state_for(user.id)[:last_activity]).to eq("2026-07-27T15:00:00Z")
      end
    end
  end

  describe ".device_status" do
    it "answers presence for a specific platform" do
      user = create(:user)
      session(user, tab_visible: true, subject_active: false, platform: "web")   # web idle
      session(user, tab_visible: true, subject_active: true, platform: "mobile") # mobile active

      expect(described_class.device_status(user.id, :mobile)).to eq("active")
      expect(described_class.device_status(user.id, :web)).to eq("idle")
      expect(described_class.device_status(user.id, :desktop)).to eq("offline")
    end
  end

  describe ".snapshot" do
    let(:member_ids) { [active_user.id, bg_user.id, offline_user.id] }
    let!(:active_user) { create(:user, name: "Ana") }
    let!(:bg_user)     { create(:user, name: "Bo") }
    let!(:offline_user) { create(:user, name: "Cy") }

    before do
      session(active_user, tab_visible: true, subject_active: true)
      session(bg_user, tab_visible: false, subject_active: true)
      # offline_user has no live session
    end

    it "returns every roster member with merged subject data and current state" do
      snap = described_class.snapshot(org)

      aggregate_failures do
        expect(snap.pluck(:id)).to match_array(member_ids)

        ana = snap.find { |m| m[:id] == active_user.id }
        expect(ana[:name]).to eq("Ana") # subject_data merged in
        expect(ana[:status]).to eq("active")
        expect(ana[:devices]).to eq("web" => "active")
        expect(ana[:last_activity]).to match(/\AZ|\A\d{4}-\d{2}-\d{2}T/) # ISO8601 string

        bo = snap.find { |m| m[:id] == bg_user.id }
        expect(bo[:status]).to eq("background")

        cy = snap.find { |m| m[:id] == offline_user.id }
        expect(cy[:status]).to eq("offline")
        expect(cy[:devices]).to eq({})
        expect(cy[:last_activity]).to be_nil
      end
    end
  end

  describe ".publish" do
    before { allow(ActionCable.server).to receive(:broadcast) }

    it "broadcasts a single compact delta to the shared org roster stream" do
      user = create(:user)
      session(user, tab_visible: true, subject_active: true)

      described_class.publish(user.id)

      expect(ActionCable.server).to have_received(:broadcast).once
      expect(ActionCable.server).to have_received(:broadcast).with(
        "where_is_waldo:roster:RosterTestOrg:1",
        hash_including(type: "roster_delta",
                       member: hash_including(id: user.id, status: "active"))
      )
    end

    it "no-ops when the roster is not configured" do
      WhereIsWaldo.config.roster_org = nil
      user = create(:user)

      expect(described_class.publish(user.id)).to be(false)
      expect(ActionCable.server).not_to have_received(:broadcast)
    end
  end

  describe "config resolution" do
    it "infers the members association from subject_class" do
      expect(WhereIsWaldo.config.members_association).to eq(:users)
    end

    it "uses roster_members when provided, else the org's default association" do
      WhereIsWaldo.config.roster_members = ->(o) { o.users.where(id: 0) }
      expect(WhereIsWaldo.config.resolve_members(org).to_sql).to include("\"id\" = 0")

      WhereIsWaldo.config.roster_members = nil
      expect(WhereIsWaldo.config.resolve_members(org)).to eq(org.users)
    end
  end

  # The roster used to bypass PresenceService and read Presence.where(...)
  # directly, which meant a host configured with `adapter = :redis` wrote to
  # Redis while the roster read an empty `presences` table — dots stayed grey
  # forever. Route through PresenceService so writes and reads share one store.
  describe "reads via PresenceService.sessions_for_subjects (adapter-aware)" do
    let(:user_a) { create(:user) }
    let(:user_b) { create(:user) }

    it "returns adapter-supplied hashes verbatim to aggregate()" do # rubocop:disable RSpec/ExampleLength
      allow(WhereIsWaldo::PresenceService).to receive(:sessions_for_subjects) do |ids, **|
        pool = {
          user_a.id => [
            { session_id: "a-1", subject_id: user_a.id, tab_visible: true,
              subject_active: true, metadata: { "platform" => "web" } },
            { session_id: "a-2", subject_id: user_a.id, tab_visible: true,
              subject_active: false, metadata: { "platform" => "mobile" } }
          ],
          user_b.id => [
            { session_id: "b-1", subject_id: user_b.id, tab_visible: false,
              subject_active: false, metadata: { "platform" => "web" } }
          ]
        }
        pool.slice(*ids)
      end

      expect(described_class.state_for(user_a.id)).to eq(
        status: "active",
        devices: { "web" => "active", "mobile" => "idle" },
        last_activity: nil
      )
      expect(described_class.state_for(user_b.id)).to eq(
        status: "background",
        devices: { "web" => "background" },
        last_activity: nil
      )
    end

    it "does NOT touch the Presence table directly" do
      allow(WhereIsWaldo::PresenceService)
        .to receive(:sessions_for_subjects)
        .and_return({})

      # If Roster ever calls Presence.where again, this would fire.
      allow(WhereIsWaldo::Presence).to receive(:where).and_call_original

      described_class.state_for(user_a.id)

      expect(WhereIsWaldo::Presence).not_to have_received(:where)
    end

    it "aggregates cleanly when the adapter returns Redis-shaped hashes with string metadata keys" do
      returned = {
        user_a.id => [
          { session_id: "a-1", subject_id: user_a.id, tab_visible: true,
            subject_active: true, metadata: { "platform" => "web" } }
        ]
      }
      allow(WhereIsWaldo::PresenceService)
        .to receive(:sessions_for_subjects)
        .and_return(returned)

      expect(described_class.state_for(user_a.id)).to eq(
        status: "active",
        devices: { "web" => "active" },
        last_activity: nil
      )
    end
  end
end
