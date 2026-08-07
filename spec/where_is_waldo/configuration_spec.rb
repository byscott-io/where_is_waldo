# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhereIsWaldo::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "sets adapter to :database" do
      expect(config.adapter).to eq(:database)
    end

    it "sets table_name to presences" do
      expect(config.table_name).to eq("presences")
    end

    it "sets session_column to :session_id" do
      expect(config.session_column).to eq(:session_id)
    end

    it "sets subject_column to :subject_id" do
      expect(config.subject_column).to eq(:subject_id)
    end

    it "sets timeout to 90" do
      expect(config.timeout).to eq(90)
    end

    it "sets heartbeat_interval to 30" do
      expect(config.heartbeat_interval).to eq(30)
    end

    it "enables ignore_heartbeat_apm by default" do
      expect(config.ignore_heartbeat_apm).to be(true)
    end
  end

  describe "#subject_class_constant" do
    context "when subject_class is nil" do
      it "returns nil" do
        config.subject_class = nil
        expect(config.subject_class_constant).to be_nil
      end
    end

    context "when subject_class is a string" do
      it "returns the constantized class" do
        config.subject_class = "User"
        expect(config.subject_class_constant).to eq(User)
      end
    end

    context "when subject_class is already a class" do
      it "returns the class" do
        config.subject_class = User
        expect(config.subject_class_constant).to eq(User)
      end
    end
  end

  describe "#build_subject_data" do
    let(:user) { create(:user, name: "Test User") }

    context "when subject is nil" do
      it "returns empty hash" do
        expect(config.build_subject_data(nil)).to eq({})
      end
    end

    context "when subject_data_proc is set" do
      it "calls the proc with the subject" do
        config.subject_data_proc = ->(s) { { name: s.name, custom: true } }
        result = config.build_subject_data(user)
        expect(result).to eq({ name: "Test User", custom: true })
      end
    end

    context "when subject_data_proc is not set" do
      it "returns hash with id" do
        result = config.build_subject_data(user)
        expect(result).to eq({ id: user.id })
      end
    end
  end
end

RSpec.describe WhereIsWaldo do
  describe ".configure" do
    it "yields the configuration" do
      described_class.configure do |config|
        config.timeout = 120
      end

      expect(described_class.config.timeout).to eq(120)
    end
  end

  describe ".reset_configuration!" do
    it "resets to defaults" do
      described_class.configure { |c| c.timeout = 999 }
      described_class.reset_configuration!
      expect(described_class.config.timeout).to eq(90)
    end
  end
end
