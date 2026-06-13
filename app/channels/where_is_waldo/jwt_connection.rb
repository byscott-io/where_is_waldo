# frozen_string_literal: true

module WhereIsWaldo
  # Turnkey ActionCable connection auth for corebyscott apps. The cable client
  # appends the user's JWT as `?token=...`; this decodes it via
  # Corebyscott::JwtService and identifies the connection by the authenticated
  # user (the presence subject), the JWT's container (cid), and session (jti).
  #
  #   # app/channels/application_cable/connection.rb
  #   module ApplicationCable
  #     class Connection < ActionCable::Connection::Base
  #       include WhereIsWaldo::JwtConnection
  #     end
  #   end
  #
  # The subject model comes from WhereIsWaldo.configuration.subject_class
  # (e.g. "User"); the container class from Corebyscott.config. Opt-in: only
  # include it in apps that authenticate with corebyscott JWTs.
  module JwtConnection
    extend ActiveSupport::Concern

    included do
      identified_by :current_user, :current_container, :session_id
    end

    def connect
      self.current_user = wiw_verified_user
      self.current_container = wiw_container
      self.session_id = wiw_session_id
    end

    private

    # Memoized decode of the ?token= param. nil when absent/invalid.
    def wiw_token_payload
      return @wiw_token_payload if defined?(@wiw_token_payload)

      token = request.params[:token]
      @wiw_token_payload =
        if token.present? && defined?(::Corebyscott::JwtService)
          begin
            ::Corebyscott::JwtService.decode(token, touch_last_used: false)
          rescue StandardError
            nil
          end
        end
    end

    def wiw_verified_user
      payload = wiw_token_payload
      reject_unauthorized_connection unless payload

      klass = WhereIsWaldo.configuration.subject_class_constant
      user = klass&.find_by(id: payload["sub"] || payload[:sub])
      reject_unauthorized_connection unless user

      user
    end

    # Optional container scoping from the JWT's `cid` claim. nil when the app
    # doesn't scope tokens to a container, or corebyscott isn't present.
    def wiw_container
      payload = wiw_token_payload
      return nil unless payload && current_user
      return nil unless defined?(::Corebyscott)

      cid = payload["cid"] || payload[:cid]
      return nil if cid.blank?

      container_class = begin
        ::Corebyscott.config.container_class&.constantize
      rescue StandardError
        nil
      end
      container_class&.find_by(id: cid)
    end

    def wiw_session_id
      payload = wiw_token_payload
      payload&.dig("jti") || payload&.dig(:jti) || SecureRandom.uuid
    end
  end
end
