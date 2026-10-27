# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module WhereIsWaldo
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :adapter, type: :string, default: "database",
                             desc: "Storage adapter (database or redis)"
      class_option :auth_method, type: :string, default: "jwt",
                                 desc: "Authentication method (jwt, devise, custom)"
      class_option :subject_class, type: :string, default: "User",
                                   desc: "The model class being tracked (User, Member, etc.)"
      class_option :subject_column, type: :string, default: "user_id",
                                    desc: "Foreign key column name for the subject"
      class_option :session_column, type: :string, default: "jti",
                                    desc: "Column name for session identifier"

      def create_initializer
        template "initializer.rb.tt", "config/initializers/where_is_waldo.rb"
      end

      def generate_migration
        return if adapter == "redis"

        migration_template "migration.rb.tt", "db/migrate/create_presences.rb"
      end

      def create_channels
        # NEVER overwrite an app's existing cable connection or channel base.
        # A host app that already authenticates ActionCable has its auth,
        # container scoping and session identity in those files, and the
        # turnkey versions here provide only what this library needs -- so
        # replacing them silently drops whatever else they did. Installing
        # into an existing app is the common case, not the exception.
        @kept_channels = []

        copy_channel "connection.rb.tt", "app/channels/application_cable/connection.rb"
        copy_channel "channel.rb.tt", "app/channels/application_cable/channel.rb"
        copy_channel "presence_channel.rb.tt", "app/channels/presence_channel.rb"
      end

      def show_post_install_message
        say ""
        say "WhereIsWaldo installed successfully!", :green
        say ""
        say "Next steps:"
        say "  1. Review config/initializers/where_is_waldo.rb"
        if adapter == "redis"
          say "  2. Ensure REDIS_URL is configured"
        else
          say "  2. Run: rails db:migrate"
        end
        say "  3. Configure your frontend PresenceProvider:"
        say ""
        say "     <PresenceProvider config={{ channelName: 'PresenceChannel' }}>"
        say "       <App />"
        say "     </PresenceProvider>"
        say ""
        report_kept_channels
      end

      private

      # Say plainly what was left alone. A silent skip is as confusing as a
      # silent overwrite: the install looks complete and presence then fails
      # because the app's own connection exposes no session identity.
      def report_kept_channels
        return if @kept_channels.blank?

        say "Kept your existing files (not overwritten):", :yellow
        @kept_channels.each { |f| say "  - #{f}" }
        say ""
        say "  WhereIsWaldo's channel reads connection.current_user and"
        say "  connection.session_id. If your connection does not identify"
        say "  both, add them -- or include WhereIsWaldo::JwtConnection."
        say ""
      end

      def copy_channel(source, destination)
        if File.exist?(File.join(destination_root, destination))
          @kept_channels << destination
        else
          template source, destination
        end
      end

      def migration_version
        "[#{ActiveRecord::VERSION::STRING.to_f}]"
      end

      def subject_class
        options[:subject_class]
      end

      def subject_column
        options[:subject_column]
      end

      def session_column
        options[:session_column]
      end

      def auth_method
        options[:auth_method]
      end

      def adapter
        options[:adapter]
      end

      # Detect database adapter and return appropriate JSON column type
      def json_column_type
        adapter_name = ActiveRecord::Base.connection.adapter_name.downcase
        case adapter_name
        when /postgresql/, /postgis/
          :jsonb
        when /mysql/, /trilogy/
          :json
        else
          # SQLite and others - use text with serialization
          :text
        end
      rescue StandardError
        # If we can't detect, default to text (most portable)
        :text
      end
    end
  end
end
