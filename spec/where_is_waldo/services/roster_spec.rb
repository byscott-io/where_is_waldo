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
  def session(user, tab_visible:, subject_active:, platform: "web")
    create(:presence, subject: user, tab_visible: tab_visible,
                      subject_active: subject_active, metadata: { "platform" => platform })
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

    it "reports offline (no devices) when no session is within the timeout" do
      user = create(:user)
      create(:presence, :stale, subject: user)

      expect(described_class.state_for(user.id)).to eq(status: "offline", devices: {})
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

        bo = snap.find { |m| m[:id] == bg_user.id }
        expect(bo[:status]).to eq("background")

        cy = snap.find { |m| m[:id] == offline_user.id }
        expect(cy[:status]).to eq("offline")
        expect(cy[:devices]).to eq({})
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
end
