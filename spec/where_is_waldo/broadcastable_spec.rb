# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhereIsWaldo::Broadcastable do
  # A lightweight stand-in so we can exercise the concern's logic without a DB
  # table. Callback *registration* (broadcasts_realtime) is proven end-to-end in
  # the consuming apps; here we cover event naming, payload, and audience.
  let(:klass) do
    Class.new do
      include WhereIsWaldo::Broadcastable

      def id = 7

      def self.model_name = ActiveModel::Name.new(self, nil, "Person")
    end
  end
  let(:record) { klass.new }

  describe "#realtime_payload" do
    it "defaults to a minimal { id: }" do
      expect(record.realtime_payload).to eq(id: 7)
    end
  end

  describe "event names" do
    it "builds <model>_<verb>" do
      expect(record.send(:wiw_event_name, :created)).to eq("person_created")
      expect(record.send(:wiw_event_name, :update)).to eq("person_update")
      expect(record.send(:wiw_event_name, :destroyed)).to eq("person_destroyed")
    end
  end

  describe "audience resolution" do
    it "calls a per-model scope lambda with the record" do
      expect(record.send(:wiw_audience, ->(rec) { "aud-#{rec.id}" })).to eq("aud-7")
    end

    it "falls back to the configured default audience" do
      WhereIsWaldo.configuration.broadcast_audience = ->(rec) { "default-#{rec.id}" }
      expect(record.send(:wiw_audience, nil)).to eq("default-7")
    ensure
      WhereIsWaldo.configuration.broadcast_audience = nil
    end

    it "is nil when nothing is configured" do
      expect(record.send(:wiw_audience, nil)).to be_nil
    end
  end

  describe "#wiw_broadcast" do
    it "broadcasts the event + payload to the resolved audience" do
      allow(WhereIsWaldo).to receive(:broadcast_to)
      record.send(:wiw_broadcast, :update, ->(_rec) { "aud" })
      expect(WhereIsWaldo).to have_received(:broadcast_to).with("aud", "person_update", { id: 7 })
    end

    it "sends only { id: } for destroy regardless of realtime_payload" do
      allow(record).to receive(:realtime_payload).and_return(id: 7, name: "x")
      allow(WhereIsWaldo).to receive(:broadcast_to)
      record.send(:wiw_broadcast, :destroyed, ->(_rec) { "aud" })
      expect(WhereIsWaldo).to have_received(:broadcast_to).with("aud", "person_destroyed", { id: 7 })
    end

    it "no-ops (no raise) when audience is blank" do
      allow(WhereIsWaldo).to receive(:broadcast_to)
      expect { record.send(:wiw_broadcast, :update, ->(_rec) {}) }.not_to raise_error
      expect(WhereIsWaldo).not_to have_received(:broadcast_to)
    end

    it "swallows + logs broadcaster errors" do
      allow(WhereIsWaldo).to receive(:broadcast_to).and_raise(StandardError, "boom")
      expect { record.send(:wiw_broadcast, :update, ->(_rec) { "aud" }) }.not_to raise_error
    end
  end
end
