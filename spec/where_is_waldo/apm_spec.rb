# frozen_string_literal: true

require "rails_helper"

# newrelic_rpm is deliberately NOT a dependency of this gem, so there is no real
# agent to drive here. These specs pin the CONTRACT the host app relies on:
# no agent -> pure pass-through; agent present -> ignore the transaction and,
# because an ignored transaction never reaches New Relic's commit! (where
# exceptions are normally harvested), hand any failure straight to the error
# collector and re-raise. The real agent integration is exercised in the host
# app against the live tracer.
RSpec.describe WhereIsWaldo::Apm do
  describe ".ignoring_transaction" do
    context "when no APM agent is loaded" do
      before { allow(described_class).to receive(:agent).and_return(nil) }

      it "runs the block and returns its value" do
        expect(described_class.ignoring_transaction { 42 }).to eq(42)
      end

      it "lets the block's exception propagate unchanged" do
        boom = StandardError.new("no agent here")

        expect { described_class.ignoring_transaction { raise boom } }.to raise_error(boom)
      end
    end

    context "when an agent is present" do
      # newrelic_rpm is not a dependency, so NewRelic::Agent isn't a loadable
      # constant here — the verified doubles are referenced by name on purpose.
      # rubocop:disable RSpec/VerifiedDoubleReference
      let(:error_collector) { instance_spy("error_collector", notice_error: nil) }
      let(:agent) do
        instance_double(
          "NewRelic::Agent",
          ignore_transaction: nil,
          instance: instance_double("NewRelic::Agent::Agent", error_collector: error_collector)
        )
      end
      # rubocop:enable RSpec/VerifiedDoubleReference

      before { allow(described_class).to receive(:agent).and_return(agent) }

      it "ignores the transaction and returns the block's value" do
        result = described_class.ignoring_transaction { 42 }

        expect(agent).to have_received(:ignore_transaction)
        expect(result).to eq(42)
      end

      it "hands a block failure to the error collector and re-raises it" do
        boom = StandardError.new("heartbeat exploded")

        expect { described_class.ignoring_transaction { raise boom } }.to raise_error(boom)
        expect(error_collector).to have_received(:notice_error).with(boom)
      end

      context "when the host has opted out via config.ignore_heartbeat_apm = false" do
        before { WhereIsWaldo.config.ignore_heartbeat_apm = false }

        it "does not touch the transaction and just runs the block" do
          result = described_class.ignoring_transaction { 42 }

          expect(agent).not_to have_received(:ignore_transaction)
          expect(result).to eq(42)
        end

        it "leaves exception reporting to the normal commit path (no hand-off)" do
          boom = StandardError.new("reported at commit instead")

          expect { described_class.ignoring_transaction { raise boom } }.to raise_error(boom)
          expect(error_collector).not_to have_received(:notice_error)
        end
      end
    end
  end

  describe ".agent" do
    it "returns nil when New Relic is not loaded" do
      # The gem's suite runs without newrelic_rpm, so this is the live answer,
      # not a stub — the guard that keeps every no-op path a genuine no-op.
      skip "newrelic_rpm is loaded in this environment" if defined?(NewRelic::Agent)

      expect(described_class.agent).to be_nil
    end
  end
end
