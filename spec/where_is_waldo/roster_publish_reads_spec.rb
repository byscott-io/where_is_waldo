# frozen_string_literal: true

require "rails_helper"

# A presence transition is the hottest path in this library: every connect,
# disconnect and activity flip runs it. Publishing needs two things from a
# subject's sessions -- which rosters to broadcast into, and the aggregate
# state to send -- and both come from the same rows. Reading them separately
# doubled the adapter traffic for no new information, which is the kind of
# regression that never shows up in a green suite.
RSpec.describe WhereIsWaldo::Roster do
  let(:user) { create(:user, name: "Busy") }
  let(:org) { RosterTestOrg.new(id: 1, members: User.where(id: user.id)) }

  before do
    WhereIsWaldo::PresenceService.send(:reset_adapter!)
    WhereIsWaldo.config.roster_mode = :broadcast
    WhereIsWaldo.config.roster_org = ->(_subject) { org }
    WhereIsWaldo.config.roster_org_for = nil
    WhereIsWaldo.config.subject_data_proc = ->(u) { { id: u.id, name: u.name } }

    create(:presence, subject: user, tab_visible: true, subject_active: true,
                      metadata: { described_class::ORG_KEY => described_class.org_key(org) })
  end

  it "reads the subject's sessions exactly once per publish" do
    allow(WhereIsWaldo::PresenceService).to receive(:sessions_for_subjects).and_call_original

    described_class.publish(user.id)

    expect(WhereIsWaldo::PresenceService).to have_received(:sessions_for_subjects).once
  end

  # The saving must not have cost correctness: the delta still carries the
  # subject's real aggregate state, not a placeholder.
  it "still sends the subject's actual state" do
    allow(ActionCable.server).to receive(:broadcast)

    described_class.publish(user.id)

    expect(ActionCable.server).to have_received(:broadcast) do |_stream, message|
      expect(message[:member][:status].to_s).to eq("active")
      expect(message[:member][:name]).to eq("Busy")
    end
  end

  it "still reports offline for a subject with no live sessions" do
    WhereIsWaldo::Presence.delete_all
    create(:presence, subject: user, last_heartbeat: 1.day.ago,
                      metadata: { described_class::ORG_KEY => described_class.org_key(org) })

    allow(ActionCable.server).to receive(:broadcast)

    described_class.publish(user.id)

    expect(ActionCable.server).to have_received(:broadcast) do |_stream, message|
      expect(message[:member][:status].to_s).to eq("offline")
    end
  end
end
