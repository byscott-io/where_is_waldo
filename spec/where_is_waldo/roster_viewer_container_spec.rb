# frozen_string_literal: true

require "rails_helper"

# THE VIEWER SIDE HAS TO AGREE WITH THE WRITER SIDE.
#
# Making presence connect container-aware is only half of it. What a person
# watching the roster actually subscribes to is resolved here, and if this side
# still guesses from the subject alone, someone scoped to their SECOND org sits
# on their FIRST org's stream: the deltas go where they are not, and the roster
# simply stays empty. That is the same subscriber/broadcaster split, moved from
# connect to view.
RSpec.describe WhereIsWaldo::RosterChannel, type: :channel do
  let(:user) { create(:user, name: "Switcher") }
  let(:org_a) { RosterTestOrg.new(id: 1, members: User.where(id: user.id)) }
  let(:org_b) { RosterTestOrg.new(id: 2, members: User.where(id: user.id)) }

  before do
    WhereIsWaldo::PresenceService.send(:reset_adapter!)
    WhereIsWaldo.config.subject_data_proc = ->(u) { { id: u.id, name: u.name } }
    WhereIsWaldo.config.roster_mode = :broadcast
    # Exactly the shape the README recommends.
    WhereIsWaldo.config.roster_org = ->(_subject) { org_a }
    WhereIsWaldo.config.roster_org_for = lambda { |subject, container|
      container || WhereIsWaldo.config.roster_org.call(subject)
    }

    create(:presence, subject: user, tab_visible: true, subject_active: true)
  end

  context "when the connection is scoped to the second org" do
    before do
      stub_connection(waldo_subject_id: user.id, waldo_session_id: "sess-b", current_container: org_b)
    end

    it "subscribes to the org the connection is in" do
      subscribe

      expect(subscription).to have_stream_from("where_is_waldo:roster:RosterTestOrg:2")
    end

    # The failure this whole change exists to prevent: subscribed to a stream
    # nobody broadcasts into, which looks like presence being broken.
    it "does not subscribe to the first org's stream" do
      subscribe

      expect(subscription).not_to have_stream_from("where_is_waldo:roster:RosterTestOrg:1")
    end
  end

  context "when the connection carries no container" do
    before do
      stub_connection(waldo_subject_id: user.id, waldo_session_id: "sess-a")
    end

    # Apps that never wired a container keep the old behaviour exactly.
    it "falls back to resolving from the subject" do
      subscribe

      expect(subscription).to have_stream_from("where_is_waldo:roster:RosterTestOrg:1")
    end
  end
end
