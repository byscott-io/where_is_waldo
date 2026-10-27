# frozen_string_literal: true

require "rails_helper"

# WHICH ROSTER A SESSION BELONGS TO.
#
# roster_org is handed only the subject, so an app whose users belong to more
# than one org has to guess -- and `accounts.first` guesses by association
# order. A person who has switched accounts is then put on the wrong roster:
# invisible to the teammates they are actually working with, and shown to an
# org they are not in right now.
#
# The connection knows the answer (its container), so the org is resolved there
# and STORED on the presence row. Everything afterwards reads the stored value
# rather than guessing again, which is what keeps the subscriber and the
# broadcaster on the same stream.
RSpec.describe WhereIsWaldo::Roster do
  let(:user) { create(:user, name: "Switcher") }
  let(:org_a) { RosterTestOrg.new(id: 1, members: User.where(id: user.id)) }
  let(:org_b) { RosterTestOrg.new(id: 2, members: User.where(id: user.id)) }

  before do
    WhereIsWaldo::PresenceService.send(:reset_adapter!)
    WhereIsWaldo.config.roster_mode = :broadcast
  end

  describe "container-aware resolution" do
    before do
      # The shape an app should use: prefer the connection's container, and
      # fall back only when there is not one.
      WhereIsWaldo.config.roster_org = ->(_subject) { org_a }
      WhereIsWaldo.config.roster_org_for = lambda { |subject, container|
        container || WhereIsWaldo.config.roster_org.call(subject)
      }
    end

    it "uses the container the connection is scoped to" do
      expect(WhereIsWaldo.config.resolve_roster_org(user, container: org_b)).to eq(org_b)
    end

    it "falls back to the subject-only lambda when there is no container" do
      expect(WhereIsWaldo.config.resolve_roster_org(user, container: nil)).to eq(org_a)
    end

    # The bug this whole change exists for.
    it "does not return the first org when the connection says otherwise" do
      expect(WhereIsWaldo.config.resolve_roster_org(user, container: org_b)).not_to eq(org_a)
    end
  end

  describe "a roster_org app that predates this" do
    before do
      WhereIsWaldo.config.roster_org_for = nil
      WhereIsWaldo.config.roster_org = ->(_subject) { org_a }
    end

    # Existing apps pass a one-argument lambda. Calling it with two would raise
    # ArgumentError and take presence down on connect.
    it "still resolves, and is not called with a container" do
      expect(WhereIsWaldo.config.resolve_roster_org(user, container: org_b)).to eq(org_a)
    end

    it "counts as enabled" do
      expect(WhereIsWaldo.config).to be_roster_enabled
    end
  end

  describe "roster_enabled?" do
    it "is true with only the container-aware form configured" do
      WhereIsWaldo.config.roster_org = nil
      WhereIsWaldo.config.roster_org_for = ->(_s, c) { c }

      expect(WhereIsWaldo.config).to be_roster_enabled
    end

    it "is false with neither" do
      WhereIsWaldo.config.roster_org = nil
      WhereIsWaldo.config.roster_org_for = nil

      expect(WhereIsWaldo.config).not_to be_roster_enabled
    end
  end

  describe "the org stored on the presence row" do
    before do
      WhereIsWaldo.config.roster_org = ->(_subject) { org_a }
      WhereIsWaldo.config.roster_org_for = nil
    end

    it "is what later broadcasts read, not a fresh guess" do
      create(:presence, subject: user, metadata: { described_class::ORG_KEY => described_class.org_key(org_b) })

      expect(described_class.org_keys_for_subject(user.id)).to eq([described_class.org_key(org_b)])
    end

    # Without the stored value, a background broadcast re-derives org_a while
    # the subscriber is listening to org_b. Nothing errors; the delta simply
    # goes to a stream nobody is on.
    it "wins over what the subject-only lambda would have said" do
      create(:presence, subject: user, metadata: { described_class::ORG_KEY => described_class.org_key(org_b) })

      expect(described_class.org_keys_for_subject(user.id)).not_to include(described_class.org_key(org_a))
    end

    # A subject id arriving from a cable connection is usually a STRING, while
    # the database adapter keys its result by the typecast column, an Integer.
    # A plain fetch misses, and the caller then falls back to resolving from
    # the subject alone -- silently, and straight back to the guess this whole
    # change exists to replace. Passing user.id on both sides, as the other
    # examples do, cannot catch that.
    it "finds the stored org when the subject id arrives as a string" do
      create(:presence, subject: user, metadata: { described_class::ORG_KEY => described_class.org_key(org_b) })

      expect(described_class.org_keys_for_subject(user.id.to_s))
        .to eq([described_class.org_key(org_b)])
    end

    # Rows written before this change carry no key, and must keep working.
    it "falls back to resolving from the subject when absent" do
      create(:presence, subject: user, metadata: { "platform" => "web" })

      expect(described_class.org_keys_for_subject(user.id)).to eq([described_class.org_key(org_a)])
    end

    # Two tabs in two accounts: the person really is present in both, so both
    # rosters have to hear about them.
    it "returns every org the subject is connected in" do
      create(:presence, subject: user, session_id: "tab-a",
                        metadata: { described_class::ORG_KEY => described_class.org_key(org_a) })
      create(:presence, subject: user, session_id: "tab-b",
                        metadata: { described_class::ORG_KEY => described_class.org_key(org_b) })

      expect(described_class.org_keys_for_subject(user.id))
        .to contain_exactly(described_class.org_key(org_a), described_class.org_key(org_b))
    end
  end

  describe "org keys" do
    it "round-trip a persisted org" do
      key = described_class.org_key(org_a)
      expect(key).to eq("RosterTestOrg:1")
    end

    it "are nil for no org" do
      expect(described_class.org_key(nil)).to be_nil
    end

    it "survive a key naming a class that no longer exists" do
      expect(described_class.org_from_key("NoSuchOrgClass:1")).to be_nil
    end

    it "survive a malformed key" do
      expect(described_class.org_from_key("garbage")).to be_nil
    end
  end
end
