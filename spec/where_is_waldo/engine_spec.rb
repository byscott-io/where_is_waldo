# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhereIsWaldo::Engine do
  # The engine used to add app/services, app/channels, app/jobs and app/models
  # to config.autoload_paths by hand. Rails::Engine already globs every app/*
  # directory into the engine's paths, so those entries were redundant — and
  # because config.autoload_paths is autoload-only, they marked the directories
  # as not-eager-loadable. These specs pin the behaviour they were papering over.
  let(:engine) { described_class.instance }

  describe "engine paths" do
    it "resolves its root to the gem root" do
      expect(engine.root.to_s).to eq(File.expand_path("../..", __dir__))
    end

    it "eager loads every app/* directory without any manual autoload_paths" do
      expect(engine.paths.eager_load).to include(
        engine.root.join("app/channels").to_s,
        engine.root.join("app/jobs").to_s,
        engine.root.join("app/models").to_s,
        engine.root.join("app/services").to_s
      )
    end

    it "adds no autoload-only paths of its own" do
      # Anything listed here is autoloadable but NOT eager loaded, which is
      # exactly the trap the hand-written autoload_paths entries fell into.
      expect(engine.config.autoload_paths).to be_empty
    end

    it "registers those directories as Zeitwerk roots on the main autoloader" do
      roots = Rails.autoloaders.main.dirs

      expect(roots).to include(
        engine.root.join("app/channels").to_s,
        engine.root.join("app/jobs").to_s,
        engine.root.join("app/models").to_s,
        engine.root.join("app/services").to_s
      )
    end
  end

  describe "framework requires" do
    # spec/dummy/config/application.rb deliberately requires none of these —
    # it stands in for `rails new --skip-action-cable`. The engine's app/*
    # classes name them in a superclass position, and Rails::Engine eager loads
    # every app/* directory, so without these requires such a host dies at boot
    # with NameError: uninitialized constant
    # WhereIsWaldo::ApplicationCable::ActionCable.
    it "loads ActionCable itself" do
      expect(defined?(ActionCable)).to eq("constant")
      expect(defined?(ActionCable::Channel::Base)).to eq("constant")
    end

    it "loads ActiveJob itself" do
      expect(defined?(ActiveJob::Base)).to eq("constant")
    end

    it "loads ActiveRecord itself" do
      expect(defined?(ActiveRecord::Base)).to eq("constant")
    end

    it "registers the ActionCable railtie so the host gets cable config" do
      expect(Rails.application.railties.map(&:class)).to include(ActionCable::Engine)
    end
  end

  describe "eager loading" do
    it "loads the whole engine without raising" do
      expect { Rails.application.eager_load! }.not_to raise_error
    end

    it "resolves a constant from each app/* directory" do
      expect(WhereIsWaldo::PresenceChannel).to be_a(Class)
      expect(WhereIsWaldo::PresenceCleanupJob).to be_a(Class)
      expect(WhereIsWaldo::Presence).to be_a(Class)
      expect(WhereIsWaldo::PresenceService).to be_a(Module)
    end
  end
end
