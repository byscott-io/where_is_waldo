# frozen_string_literal: true

require "rails_helper"

# Connection identity must come from an authenticated source, never from raw
# client input. Without an `authenticate_proc`, the only remaining source is
# `request.params[:subject_id]` — client-controlled — which must NOT be able to
# authenticate a real (production) connection; otherwise any client could
# impersonate any subject by passing ?subject_id=<anyone>.
#
# rspec-rails 6.x has no connection example group, so we exercise
# #authenticate_connection directly on an allocated instance whose #request and
# #reject_unauthorized_connection we control.
RSpec.describe WhereIsWaldo::ApplicationCable::Connection do
  def build_connection(params)
    conn = described_class.allocate
    allow(conn).to receive(:request).and_return(instance_double(ActionDispatch::Request, params: params))
    allow(conn).to receive(:reject_unauthorized_connection) { throw :rejected }
    conn
  end

  # Runs authenticate_connection; returns :rejected if the connection would be
  # refused, else :accepted.
  def authenticate(conn)
    catch(:rejected) do
      conn.send(:authenticate_connection)
      return :accepted
    end
    :rejected
  end

  before { WhereIsWaldo.config.authenticate_proc = nil }

  context "when in production with no authenticate_proc" do
    before { allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production")) }

    it "REJECTS a params-only subject_id and never adopts client-supplied identity" do
      conn = build_connection(subject_id: "99")

      expect(authenticate(conn)).to eq(:rejected)
      expect(conn.waldo_subject_id).to be_nil
    end
  end

  context "with an authenticate_proc" do
    before { WhereIsWaldo.config.authenticate_proc = ->(_request) { { subject_id: 7 } } }

    it "identifies from the proc and ignores client-supplied subject_id" do
      conn = build_connection(subject_id: "99")

      expect(authenticate(conn)).to eq(:accepted)
      expect(conn.waldo_subject_id).to eq(7)
    end
  end

  context "when in local dev/test with no authenticate_proc (escape hatch)" do
    it "allows a params-supplied subject_id (env is 'test')" do
      conn = build_connection(subject_id: "42")

      expect(authenticate(conn)).to eq(:accepted)
      expect(conn.waldo_subject_id).to eq("42")
    end
  end
end
