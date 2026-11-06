# frozen_string_literal: true

require "rails_helper"

# `sub` is not always the app's primary key.
#
# Under corebyscott's :identity_server mode it is the identity server's UUID, so
# the original find_by(id: sub) matched nothing and every cable connection was
# rejected -- silently, because a rejected connection looks exactly like a
# client that never subscribed. Measured in production before the fix:
# find_by(id: <uuid>) returned nil where find_by(identity_id: <uuid>) returned
# the user.
#
# corebyscott is an optional dependency and is NOT loaded here, so its resolver
# is a plain double rather than a verified one -- there is no constant in this
# repo to verify against. The contract asserted is the one this file calls:
# .resolve(payload).
RSpec.describe WhereIsWaldo::JwtConnection do
  let(:conn) do
    Class.new do
      # Defined BEFORE the include: the concern's `included do identified_by
      # ... end` runs at include time, so a later stub is too late.
      def self.identified_by(*); end

      include WhereIsWaldo::JwtConnection

      attr_accessor :current_user, :current_container, :session_id
    end.allocate
  end

  let(:payload) { { "sub" => "d2e63706-121e-45ef-a719-e538208d1510" } }
  let(:resolver) { double("IdentityResolver", resolve: :identity_user) } # rubocop:disable RSpec/VerifiedDoubles

  def resolve = conn.send(:wiw_resolve_subject, payload)

  def configure(subject:, identity_mode:, core_user: nil)
    allow(WhereIsWaldo.configuration).to receive(:subject_class_constant).and_return(subject)
    allow(conn).to receive_messages(wiw_identity_mode?: identity_mode, wiw_core_user_class: core_user)
    stub_const("Corebyscott::IdentityResolver", resolver)
  end

  context "when corebyscott is not in :identity_server mode" do
    let(:subject_class) { class_double(User, find_by: :local_user) }

    before { configure(subject: subject_class, identity_mode: false) }

    it "looks the subject up by primary key" do
      expect(resolve).to eq(:local_user)
    end

    it "passes the sub as the id" do
      resolve

      expect(subject_class).to have_received(:find_by).with(id: payload["sub"])
    end
  end

  context "when in :identity_server mode and the subject is core's user class" do
    let(:subject_class) { class_double(User, find_by: nil) }

    before { configure(subject: subject_class, identity_mode: true, core_user: subject_class) }

    it "resolves through core" do
      expect(resolve).to eq(:identity_user)
    end

    it "hands core the whole payload" do
      resolve

      expect(resolver).to have_received(:resolve).with(payload)
    end

    # The bug this spec exists for.
    it "does not look the subject up by primary key" do
      resolve

      expect(subject_class).not_to have_received(:find_by)
    end
  end

  context "when in :identity_server mode but the subject is another model" do
    let(:subject_class) { class_double(WhereIsWaldo::Presence, find_by: :other_subject) }

    before { configure(subject: subject_class, identity_mode: true, core_user: class_double(User)) }

    it "keeps the primary-key lookup, since core's resolver returns a user" do
      expect(resolve).to eq(:other_subject)
    end

    it "does not call core's resolver" do
      resolve

      expect(resolver).not_to have_received(:resolve)
    end
  end

  context "without a configured subject class" do
    before { configure(subject: nil, identity_mode: false) }

    it "returns nil rather than raising" do
      expect(resolve).to be_nil
    end
  end
end
