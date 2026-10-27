# frozen_string_literal: true

require "rails_helper"

# params[:metadata] IS CLIENT INPUT.
#
# The org key stored on a presence row decides which roster that subject is
# broadcast into. If a tab can put its own key there, it can make itself appear
# in an org it has no claim on -- so the server's value must not merely win,
# it must be the only one that can ever be written.
RSpec.describe WhereIsWaldo::PresenceChannel, type: :channel do
  let(:user) { create(:user, name: "Visitor") }
  let(:org_a) { RosterTestOrg.new(id: 1, members: User.where(id: user.id)) }
  let(:org_b) { RosterTestOrg.new(id: 2, members: User.where(id: user.id)) }

  let(:stored_key) do
    WhereIsWaldo::Presence.where(WhereIsWaldo.config.subject_column => user.id)
                          .first&.metadata&.dig(WhereIsWaldo::Roster::ORG_KEY)
  end

  before do
    WhereIsWaldo::PresenceService.send(:reset_adapter!)
    WhereIsWaldo.config.roster_mode = :broadcast
    stub_connection(waldo_subject_id: user.id, waldo_session_id: "sess-1")
  end

  context "when the server resolves an org" do
    before { WhereIsWaldo.config.roster_org = ->(_subject) { org_a } }

    it "stores the server's org, not the client's" do
      subscribe(metadata: { WhereIsWaldo::Roster::ORG_KEY => "RosterTestOrg:2" })

      expect(stored_key).to eq("RosterTestOrg:1")
    end
  end

  # The hole: with no org of its own, a connection could previously name any
  # org it liked and have it persist, because the server only OVERWROTE the
  # key when it had one of its own to write.
  context "when the server resolves no org" do
    before { WhereIsWaldo.config.roster_org = ->(_subject) {} }

    it "refuses to store a client-supplied org" do
      subscribe(metadata: { WhereIsWaldo::Roster::ORG_KEY => "RosterTestOrg:2" })

      expect(stored_key).to be_nil
    end

    it "refuses a symbol-keyed one too" do
      subscribe(metadata: { WhereIsWaldo::Roster::ORG_KEY.to_sym => "RosterTestOrg:2" })

      expect(stored_key).to be_nil
    end

    # And the subject must not then be broadcast into that org.
    it "does not let the smuggled org become a broadcast target" do
      subscribe(metadata: { WhereIsWaldo::Roster::ORG_KEY => "RosterTestOrg:2" })

      expect(WhereIsWaldo::Roster.org_keys_for_subject(user.id)).not_to include("RosterTestOrg:2")
    end
  end

  it "leaves the client's other metadata alone" do
    WhereIsWaldo.config.roster_org = ->(_subject) { org_a }
    subscribe(metadata: { "platform" => "web" })

    row = WhereIsWaldo::Presence.where(WhereIsWaldo.config.subject_column => user.id).first
    expect(row.metadata["platform"]).to eq("web")
  end
end
