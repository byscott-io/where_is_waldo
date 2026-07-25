# frozen_string_literal: true

require "rails_helper"

# Cross-account (multi-tenant) isolation.
#
# A subject may only ever see their OWN account's roster: the org is derived
# from the authenticated connection's subject (never from client input here —
# the connection is stubbed as a specific subject), streams are namespaced per
# org, and snapshots carry only the viewer's own members. So a viewer in
# account A can neither subscribe to account B's roster stream, see B's
# members, nor receive B's deltas.
#
# NOTE: this proves the org-derivation + stream-scoping logic. It does NOT
# exercise the connection-layer `request.params[:subject_id]` fallback (see
# application_cable/connection.rb) — closing that spoofing path is a separate,
# versioned code change.
RSpec.describe WhereIsWaldo::RosterChannel, "cross-account isolation", type: :channel do
  let(:alice) { create(:user, name: "Alice") } # account A
  let(:bob)   { create(:user, name: "Bob") }   # account B

  let(:org_a) { RosterTestOrg.new(id: 1, members: User.where(id: alice.id)) }
  let(:org_b) { RosterTestOrg.new(id: 2, members: User.where(id: bob.id)) }

  before do
    WhereIsWaldo::PresenceService.send(:reset_adapter!)
    # Multi-tenant mapping: each subject resolves to their OWN account.
    WhereIsWaldo.config.roster_org = ->(subject) { subject.id == alice.id ? org_a : org_b }
    WhereIsWaldo.config.roster_visible_to = lambda do |viewer|
      viewer.id == alice.id ? User.where(id: alice.id) : User.where(id: bob.id)
    end
    WhereIsWaldo.config.subject_data_proc = ->(u) { { id: u.id, name: u.name } }
    WhereIsWaldo.config.roster_mode = :broadcast

    # Both accounts have a live, active presence.
    create(:presence, subject: alice, tab_visible: true, subject_active: true, metadata: { "platform" => "web" })
    create(:presence, subject: bob, tab_visible: true, subject_active: true, metadata: { "platform" => "web" })

    # Connection authenticated AS alice (account A).
    stub_connection(waldo_subject_id: alice.id, waldo_session_id: "sess-a")
  end

  it "streams only from the viewer's OWN account stream, never the other account's" do
    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("where_is_waldo:roster:RosterTestOrg:1")
    expect(subscription).not_to have_stream_from("where_is_waldo:roster:RosterTestOrg:2")
  end

  it "sends a snapshot containing only the viewer's own account members" do
    subscribe

    ids = transmissions.last["members"].pluck("id")
    expect(ids).to include(alice.id)
    expect(ids).not_to include(bob.id)
  end

  it "does not deliver the other account's roster delta to the viewer" do
    subscribe
    before_size = transmissions.size

    # A presence transition in account B publishes to B's stream only.
    WhereIsWaldo::Roster.publish(bob.id)

    # Alice (subscribed to A's stream) receives nothing from B.
    expect(transmissions.size).to eq(before_size)
  end
end
