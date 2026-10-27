# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/where_is_waldo/install/install_generator"

RSpec.describe WhereIsWaldo::Generators::InstallGenerator, type: :generator do
  let(:destination) { Rails.root.join("tmp/generator_spec") }

  def run_generator(args = [])
    described_class.start(args, destination_root: destination)
  end

  def read(path)
    File.read(File.join(destination, path))
  end

  before do
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)
  end

  after { FileUtils.rm_rf(destination) }

  describe "the migration" do
    # The library keys a presence row by (subject, session) -- 0.1.5 changed it
    # precisely so two authenticated subjects colliding on a session id cannot
    # upsert onto each other's row, and the adapter scopes every session lookup
    # by both columns. A generator that emits the session-only index hands every
    # new install the schema the library moved away from.
    it "makes (subject, session) unique together, not session alone" do
      run_generator
      migration = Dir[File.join(destination, "db/migrate/*create_presences.rb")].first
      content = File.read(migration)

      expect(content).to include("add_index :presences, [ :user_id, :jti ], unique: true")
      expect(content).not_to include("add_index :presences, :jti, unique: true")
    end

    it "targets the host app's Rails version rather than a hardcoded one" do
      run_generator
      migration = Dir[File.join(destination, "db/migrate/*create_presences.rb")].first

      expect(File.read(migration))
        .to include("ActiveRecord::Migration[#{ActiveRecord::VERSION::STRING.to_f}]")
    end

    it "is skipped entirely for the redis adapter" do
      run_generator(["--adapter=redis"])
      expect(Dir[File.join(destination, "db/migrate/*")]).to be_empty
    end
  end

  describe "channels" do
    it "installs them in an app that has none" do
      run_generator
      expect(File).to exist(File.join(destination, "app/channels/application_cable/connection.rb"))
    end

    # Installing into an EXISTING app is the common case. That app's connection
    # holds its auth, container scoping and session identity; the turnkey one
    # here provides only what this library needs, so overwriting silently drops
    # the rest.
    it "never overwrites a connection the app already has" do
      path = File.join(destination, "app/channels/application_cable/connection.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "# the app's own connection\n")

      run_generator

      expect(File.read(path)).to eq("# the app's own connection\n")
    end

    it "leaves an existing presence channel alone too" do
      path = File.join(destination, "app/channels/presence_channel.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "# the app's own presence channel\n")

      run_generator

      expect(File.read(path)).to eq("# the app's own presence channel\n")
    end
  end

  it "writes an initializer carrying the requested subject column" do
    run_generator(["--subject_column=member_id"])
    expect(read("config/initializers/where_is_waldo.rb")).to include("member_id")
  end
end
